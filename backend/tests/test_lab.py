from __future__ import annotations

from tests.conftest import auth


def _seed_batch(client, token, code="HC-LAB-1", qty=8.0):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-L"}
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


def test_request_test_into_queue(client, fpo_token, lab_token):
    batch = _seed_batch(client, fpo_token)
    resp = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"], "lab_id": "LAB-TN-001"},
    )
    assert resp.status_code == 201
    test_id = resp.json()["id"]

    queue = client.get("/api/v1/labs/LAB-TN-001/queue", headers=auth(lab_token))
    assert queue.status_code == 200
    assert any(t["id"] == test_id for t in queue.json())


def test_only_lab_can_submit_result(client, fpo_token, lab_token):
    batch = _seed_batch(client, fpo_token, code="HC-LAB-2")
    test = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"]},
    ).json()

    denied = client.post(
        f"/api/v1/labs/tests/{test['id']}/result",
        headers=auth(fpo_token),
        json={"result": "PASS"},
    )
    assert denied.status_code == 403

    passed = client.post(
        f"/api/v1/labs/tests/{test['id']}/result",
        headers=auth(lab_token),
        json={"result": "PASS", "notes": "within range"},
    )
    assert passed.status_code == 200
    assert passed.json()["status"] == "passed"

    refreshed = client.get(
        f"/api/v1/batches/{batch['id']}", headers=auth(fpo_token)
    ).json()
    assert refreshed["trust_tier"] == "lab_verified"


def test_fail_keeps_self_declared(client, fpo_token, lab_token):
    batch = _seed_batch(client, fpo_token, code="HC-LAB-3")
    test = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"]},
    ).json()
    failed = client.post(
        f"/api/v1/labs/tests/{test['id']}/result",
        headers=auth(lab_token),
        json={"result": "FAIL", "notes": "contamination suspected"},
    )
    assert failed.json()["status"] == "failed"
    refreshed = client.get(
        f"/api/v1/batches/{batch['id']}", headers=auth(fpo_token)
    ).json()
    assert refreshed["trust_tier"] == "self_declared"


def test_submit_unknown_test(client, lab_token):
    resp = client.post(
        "/api/v1/labs/tests/nope/result",
        headers=auth(lab_token),
        json={"result": "PASS"},
    )
    assert resp.status_code == 404


def test_later_failure_rejects_processed_batch(client, fpo_token, lab_token):
    batch = _seed_batch(client, fpo_token, code="HC-LAB-LATE-FAIL")
    first = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token), json={"batch_id": batch["id"]},
    ).json()
    assert client.post(
        f"/api/v1/labs/tests/{first['id']}/result",
        headers=auth(lab_token), json={"result": "PASS"},
    ).status_code == 200
    assert client.post(
        "/api/v1/batches/transition", headers=auth(fpo_token),
        json={"batch_id": batch["id"], "to_state": "processing"},
    ).status_code == 200
    assert client.post(
        "/api/v1/batches/transition", headers=auth(fpo_token),
        json={"batch_id": batch["id"], "to_state": "packaged"},
    ).status_code == 200
    second = client.post(
        f"/api/v1/batches/{batch['id']}/lab-test",
        headers=auth(fpo_token), json={"batch_id": batch["id"]},
    ).json()
    assert client.post(
        f"/api/v1/labs/tests/{second['id']}/result",
        headers=auth(lab_token), json={"result": "FAIL"},
    ).status_code == 200
    refreshed = client.get(
        f"/api/v1/batches/{batch['id']}", headers=auth(fpo_token)
    ).json()
    assert refreshed["trust_tier"] == "self_declared"
    assert refreshed["status"] == "rejected"
    tests = client.get(
        f"/api/v1/batches/{batch['id']}/lab-tests", headers=auth(fpo_token)
    ).json()
    assert len(tests) == 2
