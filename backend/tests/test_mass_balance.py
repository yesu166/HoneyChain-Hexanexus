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


def _links_for_batch(client, token, batch_id):
    # The public API does not expose per-harvest allocation links directly;
    # verify through the app repository via the batch detail (batch reads are
    # role-scoped) plus the genealogy/provenance behaviour. We assert on the
    # observable outcomes instead: create-time rejection/acceptance.
    del client, token, batch_id


def test_multi_harvest_batch_requires_allocations(client, fpo_token):
    """Two 30 kg harvests, 50 kg batch, NO allocations -> 409.

    Without explicit allocations the old logic claimed the full batch quantity
    against EACH harvest, silently double-counting 20 kg.
    """
    h1 = _hive_harvest(client, fpo_token, qty=30.0)
    h2 = _hive_harvest(client, fpo_token, qty=30.0)
    resp = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-MH-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 50.0,
            "harvest_ids": [h1["id"], h2["id"]],
            "organization_id": "ORG-TN-001",
        },
    )
    assert resp.status_code == 409, resp.text


def test_multi_harvest_batch_with_exact_allocations_accepted(client, fpo_token):
    """Harvest A=30 kg, B=30 kg, batch=50 kg: A=30 + B=20 is the only honest
    allocation and is accepted; a 25/25 split is also exact and accepted."""
    h1 = _hive_harvest(client, fpo_token, qty=30.0)
    h2 = _hive_harvest(client, fpo_token, qty=30.0)
    resp = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-MH-OK-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 50.0,
            "harvest_ids": [h1["id"], h2["id"]],
            "harvest_allocations": [
                {"harvest_id": h1["id"], "quantity_kg": 30.0},
                {"harvest_id": h2["id"], "quantity_kg": 20.0},
            ],
            "organization_id": "ORG-TN-001",
        },
    )
    assert resp.status_code == 201, resp.text


def test_multi_harvest_allocations_must_sum_to_batch_quantity(client, fpo_token):
    """Allocations summing to more (or less) than the batch qty are rejected."""
    h1 = _hive_harvest(client, fpo_token, qty=30.0)
    h2 = _hive_harvest(client, fpo_token, qty=30.0)
    resp = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-MH-SUM-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 50.0,
            "harvest_ids": [h1["id"], h2["id"]],
            "harvest_allocations": [
                {"harvest_id": h1["id"], "quantity_kg": 30.0},
                {"harvest_id": h2["id"], "quantity_kg": 30.0},
            ],
            "organization_id": "ORG-TN-001",
        },
    )
    assert resp.status_code == 409, resp.text


def test_double_spending_a_harvest_across_batches_rejected(client, fpo_token):
    """A 30 kg harvest cannot back a second 20 kg batch after a 30 kg one."""
    harvest = _hive_harvest(client, fpo_token, qty=30.0)
    first = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-DS-1-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 30.0,
            "harvest_ids": [harvest["id"]],
            "organization_id": "ORG-TN-001",
        },
    )
    assert first.status_code == 201, first.text
    second = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-DS-2-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 20.0,
            "harvest_ids": [harvest["id"]],
            "organization_id": "ORG-TN-001",
        },
    )
    assert second.status_code == 409, second.text


def test_merge_conserves_per_harvest_quantities(client, fpo_token):
    """Merging two single-harvest lots must not claim the merged total from
    each harvest: the merged lot consumes A=5 kg + B=5 kg, not 10 kg twice."""
    h1 = _hive_harvest(client, fpo_token, qty=6.0)
    h2 = _hive_harvest(client, fpo_token, qty=6.0)
    b1 = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-MG-1-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 5.0,
            "harvest_ids": [h1["id"]],
            "organization_id": "ORG-TN-001",
        },
    ).json()
    b2 = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-MG-2-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 5.0,
            "harvest_ids": [h2["id"]],
            "organization_id": "ORG-TN-001",
        },
    ).json()
    merged = client.post(
        "/api/v1/batches/merge",
        headers=auth(fpo_token),
        json={
            "batch_ids": [b1["id"], b2["id"]],
            "new_batch_code": f"MB-MG-M-{uuid.uuid4().hex[:10]}",
        },
    )
    assert merged.status_code == 200, merged.text
    # Conservation observable outcome: harvest h1 (6 kg) has 5 kg consumed by
    # b1 and, after merge, b1 is a merged source. A follow-up batch may still
    # claim only the 1 kg remainder of each harvest, never 5 kg.
    remainder = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-MG-R-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 1.0,
            "harvest_ids": [h1["id"]],
            "organization_id": "ORG-TN-001",
        },
    )
    assert remainder.status_code == 201, remainder.text
    overflow = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": f"MB-MG-O-{uuid.uuid4().hex[:10]}",
            "quantity_kg": 2.0,
            "harvest_ids": [h1["id"]],
            "organization_id": "ORG-TN-001",
        },
    )
    assert overflow.status_code == 409, overflow.text
