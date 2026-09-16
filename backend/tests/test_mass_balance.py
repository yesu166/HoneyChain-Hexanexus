from __future__ import annotations

import uuid

from tests.conftest import auth


def _hive_harvest(client, token, qty: float):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-MB"}
    ).json()
    return client.post(
        "/api/v1/harvests",
        headers=auth(token),
        json={"hive_id": hive["id"], "quantity_kg": qty},
    ).json()


def test_batch_cannot_exceed_linked_harvest_quantity(client, fpo_token):
    """Mass balance: batch qty > linked harvest qty must be a 409, not a mint."""
    harvest = _hive_harvest(client, fpo_token, qty=5.0)
    resp = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 9.9,
            "harvest_ids": [harvest["id"]],
            "organization_id": "ORG-TN-001",
        },
    )
    assert resp.status_code == 409, resp.text


def test_batch_within_harvest_quantity_is_accepted(client, fpo_token):
    harvest = _hive_harvest(client, fpo_token, qty=8.0)
    resp = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-OK-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 7.5,
            "harvest_ids": [harvest["id"]],
            "organization_id": "ORG-TN-001",
        },
    )
    assert resp.status_code == 201, resp.text


def test_sync_push_rejects_batch_with_unknown_harvest(client, demo_token):
    """Offline sync surfaces batch errors as a rejected item, never a 500."""
    resp = client.post(
        "/api/v1/sync/push",
        headers=auth(demo_token),
        json={
            "items": [
                {
                    "entity": "batch",
                    "client_id": f"mb-sync-{uuid.uuid4().hex[:10]}",
                    "data": {
                        "batch_code": f"MB-S-{uuid.uuid4().hex[:10]}",
                        "quantity_kg": 1.0,
                        "harvest_ids": ["no-such-harvest"],
                    },
                }
            ]
        },
    )
    body = resp.json()
    assert resp.status_code == 200, resp.text
    assert body.get("accepted") == []
    assert body.get("rejected"), body
    assert "not found" in (body["rejected"][0].get("error") or ""), body
