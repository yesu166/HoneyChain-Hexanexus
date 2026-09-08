from __future__ import annotations

from tests.conftest import auth


def _make_hive(client, token, code="HIVE-HV-1"):
    return client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": code}
    ).json()


def _make_harvest(client, token, hive_id, qty=8.5, client_id=""):
    return client.post(
        "/api/v1/harvests",
        headers=auth(token),
        json={"hive_id": hive_id, "quantity_kg": qty, "client_id": client_id},
    )


def test_create_harvest_for_own_hive(client, demo_token):
    hive = _make_hive(client, demo_token)
    resp = _make_harvest(client, demo_token, hive["id"], qty=8.5)
    assert resp.status_code == 201
    assert resp.json()["quantity_kg"] == 8.5


def test_harvest_quantity_must_be_positive(client, demo_token):
    hive = _make_hive(client, demo_token)
    resp = _make_harvest(client, demo_token, hive["id"], qty=0)
    assert resp.status_code == 422


def test_harvest_list_and_get(client, demo_token):
    hive = _make_hive(client, demo_token)
    harvest = _make_harvest(client, demo_token, hive["id"], qty=3.0).json()
    listed = client.get("/api/v1/harvests", headers=auth(demo_token))
    assert any(h["id"] == harvest["id"] for h in listed.json())
    assert (
        client.get(f"/api/v1/harvests/{harvest['id']}", headers=auth(demo_token))
        .status_code
        == 200
    )


def test_harvest_idempotent_client_id(client, demo_token):
    hive = _make_hive(client, demo_token)
    first = _make_harvest(client, demo_token, hive["id"], client_id="client-hv-1").json()
    second = _make_harvest(client, demo_token, hive["id"], client_id="client-hv-1").json()
    assert first["id"] == second["id"]