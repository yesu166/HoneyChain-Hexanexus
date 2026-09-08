from __future__ import annotations

from datetime import timedelta

from tests.conftest import DEMO_EMAIL, DEMO_PASSWORD, auth, make_token


def test_valid_login(client):
    resp = client.post(
        "/api/v1/auth/login",
        json={"identifier": DEMO_EMAIL, "password": DEMO_PASSWORD},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"]


def test_wrong_password(client):
    resp = client.post(
        "/api/v1/auth/login",
        json={"identifier": DEMO_EMAIL, "password": "wrong-password"},
    )
    assert resp.status_code == 401


def test_unknown_user(client):
    resp = client.post(
        "/api/v1/auth/login",
        json={"identifier": "nobody@honeychain.in", "password": DEMO_PASSWORD},
    )
    assert resp.status_code == 401


def test_me_requires_token(client):
    assert client.get("/api/v1/auth/me").status_code == 401


def test_me_expired_token(client):
    expired = make_token("demo-beekeeper-id", "beekeeper", minutes=-5)
    resp = client.get("/api/v1/auth/me", headers=auth(expired))
    assert resp.status_code == 401


def test_me_invalid_token(client):
    resp = client.get("/api/v1/auth/me", headers=auth("garbage.token.value"))
    assert resp.status_code == 401


def test_register_and_login(client):
    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": "newbeek@honeychain.in",
            "name": "New Beekeeper",
            "phone": "+919111111111",
            "password": "StrongPass123",
            "role": "beekeeper",
            "org_id": "ORG-TN-001",
        },
    )
    assert resp.status_code == 201
    user_id = resp.json()["id"]
    login = client.post(
        "/api/v1/auth/login",
        json={"identifier": "newbeek@honeychain.in", "password": "StrongPass123"},
    )
    assert login.status_code == 200
    me = client.get("/api/v1/auth/me", headers=auth(login.json()["access_token"]))
    assert me.status_code == 200
    assert me.json()["id"] == user_id


def test_register_rejects_unknown_role(client):
    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": "consumer@honeychain.in",
            "name": "Buyer",
            "phone": "",
            "password": "StrongPass123",
            "role": "consumer",
        },
    )
    assert resp.status_code == 422

    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": "x@honeychain.in",
            "name": "X",
            "phone": "",
            "password": "StrongPass123",
            "role": "superuser",
        },
    )
    assert resp.status_code == 422