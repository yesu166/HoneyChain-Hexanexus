from __future__ import annotations

from tests.conftest import auth


def _seed_harvest(client, token, qty=10.0):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": "HIVE-B"}
    ).json()
    return client.post(
        "/api/v1/harvests",
        headers=auth(token),
        json={"hive_id": hive["id"], "quantity_kg": qty},
    ).json()


def _create_batch(client, token, code, harvest_ids, qty=None, client_id=""):
    return client.post(
        "/api/v1/batches",
        headers=auth(token),
        json={
            "batch_code": code,
            "quantity_kg": qty or 10.0,
            "harvest_ids": harvest_ids,
            "organization_id": "ORG-TN-001",
            "origin": "Kotagiri",
            "honey_type": "Multifloral",
            "client_id": client_id,
        },
    )


def test_create_and_read_batch(client, fpo_token):
    harvest = _seed_harvest(client, fpo_token)
    resp = _create_batch(client, fpo_token, "HC-TN-9001", [harvest["id"]])
    assert resp.status_code == 201
    batch = resp.json()
    assert batch["batch_code"] == "HC-TN-9001"
    assert batch["trust_tier"] == "self_declared"

    listed = client.get("/api/v1/batches", headers=auth(fpo_token))
    assert any(b["id"] == batch["id"] for b in listed.json())
    assert (
        client.get(f"/api/v1/batches/{batch['id']}", headers=auth(fpo_token))
        .status_code
        == 200
    )


def test_batch_code_unique_on_replay(client, fpo_token):
    harvest = _seed_harvest(client, fpo_token)
    first = _create_batch(
        client, fpo_token, "HC-TN-9002", [harvest["id"]], client_id="client-b-1"
    ).json()
    second = _create_batch(
        client, fpo_token, "HC-TN-9002", [harvest["id"]], client_id="client-b-1"
    ).json()
    assert first["id"] == second["id"]


def test_beekeeper_sees_batch_of_own_harvest(client, demo_token, fpo_token):
    harvest = _seed_harvest(client, fpo_token)
    # link the harvest to demo beekeeper
    hive = client.post(
        "/api/v1/hives",
        headers=auth(demo_token),
        json={"hive_code": "HIVE-DB"},
    ).json()
    harvest2 = client.post(
        "/api/v1/harvests",
        headers=auth(demo_token),
        json={"hive_id": hive["id"], "quantity_kg": 10.0},
    ).json()
    batch = _create_batch(client, fpo_token, "HC-TN-9003", [harvest2["id"]]).json()
    listed = client.get("/api/v1/batches", headers=auth(demo_token))
    assert any(b["id"] == batch["id"] for b in listed.json())


def test_split_sum_validation(client, fpo_token):
    harvest = _seed_harvest(client, fpo_token)
    batch = _create_batch(client, fpo_token, "HC-TN-9004", [harvest["id"]], qty=10.0).json()
    bad = client.post(
        f"/api/v1/batches/{batch['id']}/split",
        headers=auth(fpo_token),
        json={"child_quantities_kg": [4.0, 4.0]},
    )
    assert bad.status_code == 409
    good = client.post(
        f"/api/v1/batches/{batch['id']}/split",
        headers=auth(fpo_token),
        json={"child_quantities_kg": [6.0, 4.0]},
    )
    assert good.status_code == 200
    children = good.json()["children"]
    assert len(children) == 2
    genea = client.get(
        f"/api/v1/batches/{batch['id']}/genealogy", headers=auth(fpo_token)
    )
    assert genea.status_code == 200
    assert len(genea.json()) == 3


def test_merge_uses_weakest_trust(client, fpo_token):
    harvest = _seed_harvest(client, fpo_token)
    b1 = _create_batch(client, fpo_token, "HC-M-1", [harvest["id"]], qty=5.0).json()
    b2 = _create_batch(client, fpo_token, "HC-M-2", [harvest["id"]], qty=5.0).json()
    client.put(
        f"/api/v1/batches/{b1['id']}",
        headers=auth(fpo_token),
        json={"status": "created"},
    )
    result = client.post(
        "/api/v1/batches/merge",
        headers=auth(fpo_token),
        json={"batch_ids": [b1["id"], b2["id"]], "new_batch_code": "HC-MERGED"},
    )
    assert result.status_code == 200
    merged = result.json()["merged"]
    assert merged["quantity_kg"] == 10.0
    assert merged["trust_tier"] == "self_declared"


def test_merge_missing_source(client, fpo_token):
    resp = client.post(
        "/api/v1/batches/merge",
        headers=auth(fpo_token),
        json={"batch_ids": ["no-such-batch", "also-none"], "new_batch_code": "HC-NO"},
    )
    assert resp.status_code == 409


def test_genealogy_no_cycles(client, fpo_token):
    harvest = _seed_harvest(client, fpo_token)
    batch = _create_batch(client, fpo_token, "HC-CYCLE", [harvest["id"]]).json()
    client.post(
        f"/api/v1/batches/{batch['id']}/split",
        headers=auth(fpo_token),
        json={"child_quantities_kg": [6.0, 4.0]},
    )
    resp = client.get(
        f"/api/v1/batches/{batch['id']}/genealogy", headers=auth(fpo_token)
    )
    ids = [node["id"] for node in resp.json()]
    assert len(ids) == len(set(ids))