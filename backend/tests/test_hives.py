from __future__ import annotations

from tests.conftest import auth


def test_create_and_list_hive(client, demo_token):
    resp = client.post(
        "/api/v1/hives",
        headers=auth(demo_token),
        json={"hive_code": "HIVE-TN-100", "location": "Kotagiri"},
    )
    assert resp.status_code == 201
    hive = resp.json()
    assert hive["hive_code"] == "HIVE-TN-100"
    assert hive["beekeeper_id"]

    listed = client.get("/api/v1/hives", headers=auth(demo_token))
    assert listed.status_code == 200
    assert any(h["id"] == hive["id"] for h in listed.json())


def test_create_hive_requires_code(client, demo_token):
    resp = client.post("/api/v1/hives", headers=auth(demo_token), json={})
    assert resp.status_code == 422


def test_get_hive_not_found(client, demo_token):
    resp = client.get("/api/v1/hives/nope", headers=auth(demo_token))
    assert resp.status_code == 404


def test_update_hive(client, demo_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-U1"}
    ).json()
    resp = client.put(
        f"/api/v1/hives/{hive['id']}",
        headers=auth(demo_token),
        json={"status": "inactive"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "inactive"


def test_readings_roundtrip(client, demo_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-R1"}
    ).json()
    reading = client.post(
        f"/api/v1/hives/{hive['id']}/readings",
        headers=auth(demo_token),
        json={"temperature_c": 31.0, "humidity_percent": 68.0, "weight_kg": 22.4},
    )
    assert reading.status_code == 201
    assert reading.json()["temperature_c"] == 31.0

    listed = client.get(
        f"/api/v1/hives/{hive['id']}/readings", headers=auth(demo_token)
    )
    assert listed.status_code == 200
    assert len(listed.json()) == 1


def test_health_score_no_readings(client, demo_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-H1"}
    ).json()
    resp = client.get(
        f"/api/v1/hives/{hive['id']}/health-score", headers=auth(demo_token)
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["risk_level"] in ("LOW", "MEDIUM", "HIGH")
    assert 0 <= body["risk_score"] <= 100
    assert "timestamp" in body


def test_health_score_uses_real_readings(client, demo_token):
    hive = client.post(
        "/api/v1/hives", headers=auth(demo_token), json={"hive_code": "HIVE-H2"}
    ).json()
    client.post(
        f"/api/v1/hives/{hive['id']}/readings",
        headers=auth(demo_token),
        json={"temperature_c": 41.0},
    )
    resp = client.get(
        f"/api/v1/hives/{hive['id']}/health-score", headers=auth(demo_token)
    )
    assert resp.status_code == 200
    assert any(
        "above the colony comfort band" in f["factor"]
        for f in resp.json()["contributing_factors"]
    )


def test_create_hive_idempotent_client_id(client, demo_token):
    first = client.post(
        "/api/v1/hives",
        headers=auth(demo_token),
        json={"hive_code": "HIVE-ID1", "client_id": "client-hive-1"},
    ).json()
    second = client.post(
        "/api/v1/hives",
        headers=auth(demo_token),
        json={"hive_code": "HIVE-ID1", "client_id": "client-hive-1"},
    ).json()
    assert first["id"] == second["id"]