"""Explicit lab workflow: request -> IN TESTING -> result, plus the lab directory.

The backend previously jumped from `requested` straight to a final result. These
tests pin the explicit intermediate state and the real laboratory selector.
"""
from __future__ import annotations

from tests.conftest import auth


def _seed_batch(client, token, code="HC-LABWF-1", qty=8.0):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-LWF"}
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


def test_lab_directory_is_listable(client, fpo_token):
    resp = client.get("/api/v1/labs", headers=auth(fpo_token))
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)


def test_lab_directory_denied_to_beekeeper(client, demo_token):
    resp = client.get("/api/v1/labs", headers=auth(demo_token))
    assert resp.status_code == 403


def test_start_test_moves_to_in_progress_then_result(client, fpo_token, lab_token):
    batch = _seed_batch(client, fpo_token)
    test = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"], "lab_id": "LAB-TN-001"},
    ).json()

    started = client.post(
        f"/api/v1/labs/tests/{test['id']}/start", headers=auth(lab_token)
    )
    assert started.status_code == 200
    assert started.json()["status"] == "in_progress"

    passed = client.post(
        f"/api/v1/labs/tests/{test['id']}/result",
        headers=auth(lab_token),
        json={"result": "PASS"},
    )
    assert passed.status_code == 200
    assert passed.json()["status"] == "passed"


def test_start_test_requires_lab_role(client, fpo_token):
    batch = _seed_batch(client, fpo_token, code="HC-LABWF-2")
    test = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"], "lab_id": "LAB-TN-001"},
    ).json()
    denied = client.post(
        f"/api/v1/labs/tests/{test['id']}/start", headers=auth(fpo_token)
    )
    assert denied.status_code == 403


def test_start_unknown_test_is_404(client, lab_token):
    resp = client.post("/api/v1/labs/tests/nope/start", headers=auth(lab_token))
    assert resp.status_code == 404


def test_lab_pass_emits_workflow_notification_to_fpo(client, fpo_token, lab_token):
    batch = _seed_batch(client, fpo_token, code="HC-LABWF-3")
    test = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"], "lab_id": "LAB-TN-001"},
    ).json()
    client.post(
        f"/api/v1/labs/tests/{test['id']}/result",
        headers=auth(lab_token),
        json={"result": "PASS"},
    )

    inbox = client.get("/api/v1/notifications", headers=auth(fpo_token)).json()
    events = {item["category"] for item in inbox["items"]}
    assert "LAB_REQUESTED" in events
    assert "LAB_PASS" in events
    assert all(
        item["source"] in ("workflow", "iot", "ledger", "evidence", "system")
        for item in inbox["items"]
    )


def test_lab_fail_emits_critical_notification(client, fpo_token, lab_token):
    batch = _seed_batch(client, fpo_token, code="HC-LABWF-4")
    test = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"], "lab_id": "LAB-TN-001"},
    ).json()
    client.post(
        f"/api/v1/labs/tests/{test['id']}/result",
        headers=auth(lab_token),
        json={"result": "FAIL"},
    )
    inbox = client.get("/api/v1/notifications", headers=auth(fpo_token)).json()
    fails = [item for item in inbox["items"] if item["category"] == "LAB_FAIL"]
    assert fails
    assert fails[0]["severity"] == "critical"
