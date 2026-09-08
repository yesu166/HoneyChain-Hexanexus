from __future__ import annotations

from tests.conftest import auth, make_token


def test_push_hive_once_and_replay(client, demo_token):
    payload = {
        "items": [
            {
                "entity": "hive",
                "client_id": "sync-hive-1",
                "data": {"hive_code": "HIVE-SYNC"},
            }
        ]
    }
    first = client.post("/api/v1/sync/push", json=payload, headers=auth(demo_token))
    assert first.status_code == 200
    accepted = first.json()["accepted"]
    assert len(accepted) == 1 and accepted[0]["accepted"] is True
    backend_id = accepted[0]["backend_id"]

    replay = client.post("/api/v1/sync/push", json=payload, headers=auth(demo_token))
    replayed = replay.json()["accepted"][0]
    assert replayed["accepted"] is True
    assert replayed["backend_id"] == backend_id  # idempotent: no duplicate


def test_push_mixed_entities(client, demo_token):
    hive = client.post(
        "/api/v1/sync/push",
        json={
            "items": [
                {"entity": "hive", "client_id": "h1", "data": {"hive_code": "HIVE-X"}}
            ]
        },
        headers=auth(demo_token),
    ).json()["accepted"][0]
    payload = {
        "items": [
            {"entity": "hive", "client_id": "h1", "data": {"hive_code": "HIVE-X"}},
            {
                "entity": "harvest",
                "client_id": "r0",
                "data": {"hive_id": hive["backend_id"], "quantity_kg": 2.0},
            },
            {"entity": "nonsense", "client_id": "z1", "data": {}},
            {"entity": "reading", "client_id": "zz", "data": {"hive_id": "nope"}},
        ]
    }
    resp = client.post("/api/v1/sync/push", json=payload, headers=auth(demo_token))
    assert resp.status_code == 200
    body = resp.json()
    assert {item["client_id"] for item in body["accepted"]} == {"h1", "r0"}
    assert {item["client_id"] for item in body["rejected"]} == {"zz", "z1"}


def test_push_requires_auth(client):
    resp = client.post("/api/v1/sync/push", json={"items": []})
    assert resp.status_code == 401


def test_push_reading_requires_own_hive(client, demo_token, fpo_token):
    payload = {
        "items": [
            {
                "entity": "reading",
                "client_id": "reading-1",
                "data": {"hive_id": "foreign-hive", "temperature_c": 30.0},
            }
        ]
    }
    resp = client.post("/api/v1/sync/push", json=payload, headers=auth(demo_token))
    assert resp.status_code == 200
    assert resp.json()["rejected"]


def test_pull_returns_own_entities(client, demo_token):
    client.post(
        "/api/v1/sync/push",
        json={
            "items": [
                {"entity": "hive", "client_id": "p-hive", "data": {"hive_code": "HIVE-PULL"}}
            ]
        },
        headers=auth(demo_token),
    )
    resp = client.post("/api/v1/sync/pull", json={"scope": "mine"}, headers=auth(demo_token))
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert any(i["entity"] == "hive" and i["data"].get("hive_code") == "HIVE-PULL" for i in items)


def test_pull_requires_auth(client):
    assert client.post("/api/v1/sync/pull", json={}).status_code == 401