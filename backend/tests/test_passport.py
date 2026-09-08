from __future__ import annotations

from tests.conftest import auth


def _seed_batch(client, token, code="HC-P-1", qty=6.0):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-P"}
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
            "origin": "Kotagiri, Tamil Nadu",
            "honey_type": "Multifloral",
            "organization_id": "ORG-TN-001",
        },
    ).json()


def test_public_passport_no_auth(client, fpo_token):
    batch = _seed_batch(client, fpo_token)
    resp = client.get(f"/api/v1/passport/{batch['batch_code']}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["batch_code"] == batch["batch_code"]
    assert body["subject"] == "batch"
    assert "caveat" in body


def test_passport_not_found(client):
    resp = client.get("/api/v1/passport/HC-NOPE-123")
    assert resp.status_code == 404


def test_passport_invalid_code_no_crash(client):
    resp = client.get("/api/v1/passport/!%21%21invalid")
    assert resp.status_code in (200, 404)
    assert resp.status_code != 500


def test_passport_has_no_pii(client, fpo_token):
    batch = _seed_batch(client, fpo_token)
    body = client.get(f"/api/v1/passport/{batch['batch_code']}").json()
    serialized = str(body).lower()
    for marker in ("demo@", "email", "@honeychain.in"):
        assert marker not in serialized


def test_passport_includes_custody_events(client, fpo_token):
    batch = _seed_batch(client, fpo_token)
    client.post(
        f"/api/v1/batches/{batch['id']}/custody-events",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"], "action": "PACKAGING", "notes": "packed"},
    )
    body = client.get(f"/api/v1/passport/{batch['batch_code']}").json()
    types = [e["type"] for e in body["events"]]
    assert "PACKAGING" in types