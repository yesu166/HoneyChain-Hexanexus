"""Workflow notifications emitted from the SAME write that changed state.

The inbox may never advertise an action the database did not record, and each
event must reach the organisation that actually has to act on it.
"""
from __future__ import annotations

from tests.conftest import auth, make_token


def _seed_batch(client, token, code="HC-WF-1", qty=8.0, org="ORG-TN-001"):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-WF"}
    ).json()
    harvest = client.post(
        "/api/v1/harvests",
        headers=auth(token),
        json={"hive_id": hive["id"], "quantity_kg": qty},
    ).json()
    batch = client.post(
        "/api/v1/batches",
        headers=auth(token),
        json={
            "batch_code": code,
            "quantity_kg": qty,
            "harvest_ids": [harvest["id"]],
            "organization_id": org,
        },
    ).json()
    return harvest, batch


def _events(client, token):
    inbox = client.get("/api/v1/notifications", headers=auth(token)).json()
    return inbox["items"]


def test_harvest_created_reaches_the_fpo(client, demo_token, fpo_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-WF-H"}
    ).json()
    client.post(
        "/api/v1/harvests",
        headers=auth(demo_token),
        json={"hive_id": hive["id"], "quantity_kg": 6.0},
    )
    rows = [r for r in _events(client, fpo_token) if r["category"] == "HARVEST_CREATED"]
    assert rows, "the FPO must be told a harvest exists"
    assert rows[0]["source"] == "workflow"
    assert rows[0]["is_simulated"] is False


def test_batch_created_emits_workflow_event(client, fpo_token):
    _seed_batch(client, fpo_token, code="HC-WF-2")
    rows = [r for r in _events(client, fpo_token) if r["category"] == "BATCH_CREATED"]
    assert rows
    assert rows[0]["severity"] == "info"
    assert rows[0]["recommended_action"]


def test_custody_collection_emits_collection_accepted(client, fpo_token):
    _, batch = _seed_batch(client, fpo_token, code="HC-WF-3")
    client.post(
        f"/api/v1/batches/{batch['id']}/custody-events",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"], "action": "COLLECTION", "quantity_kg": 8.0},
    )
    rows = [
        r for r in _events(client, fpo_token) if r["category"] == "COLLECTION_ACCEPTED"
    ]
    assert rows
    assert rows[0]["batch_id"] == batch["id"]


def test_custody_transfer_notifies_both_parties(client, fpo_token):
    receiver_token = make_token(
        "processor-user-id", "processor", "PROCESSOR-TN-01"
    )
    _, batch = _seed_batch(client, fpo_token, code="HC-WF-4")
    client.post(
        f"/api/v1/batches/{batch['id']}/custody-events",
        headers=auth(fpo_token),
        json={
            "batch_id": batch["id"],
            "action": "TRANSFER",
            "quantity_kg": 8.0,
            "to_org": "PROCESSOR-TN-01",
        },
    )
    # Sender organisation records the handover it just persisted.
    sender = [
        r for r in _events(client, fpo_token) if r["category"] == "CUSTODY_TRANSFER"
    ]
    assert sender
    # The receiving organisation is told to confirm receipt.
    receiver = [
        r
        for r in _events(client, receiver_token)
        if r["category"] == "CUSTODY_TRANSFER"
    ]
    assert receiver, "the receiver must see the transfer in its own inbox"


def test_idempotent_replay_does_not_duplicate_notifications(client, fpo_token):
    payload = {
        "batch_code": "HC-WF-5",
        "quantity_kg": 8.0,
        "client_id": "wf-replay-1",
        "organization_id": "ORG-TN-001",
    }
    client.post("/api/v1/batches", headers=auth(fpo_token), json=payload)
    first = len(
        [r for r in _events(client, fpo_token) if r["category"] == "BATCH_CREATED"]
    )
    assert first == 1
    client.post("/api/v1/batches", headers=auth(fpo_token), json=payload)
    again = len(
        [r for r in _events(client, fpo_token) if r["category"] == "BATCH_CREATED"]
    )
    assert again == first, "an idempotent replay must not re-notify"


def test_workflow_notifications_are_not_simulated(client, fpo_token):
    _seed_batch(client, fpo_token, code="HC-WF-6")
    rows = [r for r in _events(client, fpo_token) if r["source"] == "workflow"]
    assert rows
    assert all(r["is_simulated"] is False for r in rows)
