from __future__ import annotations

from tests.conftest import auth


def _seed_batch(client, token, code="HC-C-1", qty=7.0):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-C"}
    ).json()
    harvest = client.post(
        "/api/v1/harvests",
        headers=auth(token),
        json={"hive_id": hive["id"], "quantity_kg": qty},
    ).json()
    return client.post(
        "/api/v1/batches",
        headers=auth(token),
        json={
            "batch_code": code,
            "quantity_kg": qty,
            "harvest_ids": [harvest["id"]],
            "organization_id": "ORG-TN-001",
        },
    ).json()


def test_all_valid_custody_actions(client, fpo_token):
    batch = _seed_batch(client, fpo_token)
    actions = [
        "COLLECTION",
        "PROCESSING",
        "PACKAGING",
        "TRANSFER",
        "DISTRIBUTION",
        "SALE",
    ]
    for action in actions:
        resp = client.post(
            f"/api/v1/batches/{batch['id']}/custody-events",
            headers=auth(fpo_token),
            json={"batch_id": batch["id"], "action": action, "notes": action},
        )
        assert resp.status_code == 201, action
    listed = client.get(
        f"/api/v1/batches/{batch['id']}/custody-events", headers=auth(fpo_token)
    )
    assert len(listed.json()) == len(actions)


def test_invalid_custody_action_rejected(client, fpo_token):
    batch = _seed_batch(client, fpo_token, code="HC-C-2")
    resp = client.post(
        f"/api/v1/batches/{batch['id']}/custody-events",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"], "action": "LAUNCH_NUCLEAR"},
    )
    assert resp.status_code == 422


def test_custody_events_require_batch_access(client, demo_token, fpo_token):
    batch = _seed_batch(client, fpo_token, code="HC-C-3")
    foreign = client.post(  # demo beekeeper has no relation to fpo batch
        f"/api/v1/batches/{batch['id']}/custody-events",
        headers=auth(demo_token),
        json={"batch_id": batch["id"], "action": "SALE"},
    )
    assert foreign.status_code == 404 or foreign.status_code == 403