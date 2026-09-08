from __future__ import annotations

from tests.conftest import make_token


def test_liveness(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
    assert resp.json()["service"] == "honeychain-api"


def test_versioned_health(client):
    resp = client.get("/api/v1/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["service"] == "honeychain-api"
    assert "dependencies" in body


def test_health_is_public(client):
    assert client.get("/api/v1/health").status_code == 200