"""Canonical provenance aggregation endpoint.

`GET /api/v1/batches/{id}/provenance` must return the same records the batch
detail page needs — material lineage plus operational provenance — from real
persisted state, with an honest mass balance.
"""
from __future__ import annotations

from tests.conftest import auth


def _harvest(client, token, code, qty):
    hive = client.post(
        "/api/v1/hives", headers=auth(token), json={"hive_code": code}
    ).json()
    harvest = client.post(
        "/api/v1/harvests",
        headers=auth(token),
        json={"hive_id": hive["id"], "quantity_kg": qty, "honey_type": "Wildflower"},
    ).json()
    return hive, harvest


def test_provenance_multi_harvest_mass_balance(client, fpo_token):
    hives, harvests = [], []
    for code, qty in (("NLG-101", 8.0), ("NLG-102", 9.0), ("NLG-103", 7.0)):
        hive, harvest = _harvest(client, fpo_token, code, qty)
        hives.append(hive)
        harvests.append(harvest)

    batch = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": "HC-TN-NLG-001",
            "quantity_kg": 24.0,
            "honey_type": "Wildflower",
            "organization_id": "ORG-TN-001",
            "harvest_ids": [h["id"] for h in harvests],
            "harvest_allocations": [
                {"harvest_id": harvests[0]["id"], "quantity_kg": 8.0},
                {"harvest_id": harvests[1]["id"], "quantity_kg": 9.0},
                {"harvest_id": harvests[2]["id"], "quantity_kg": 7.0},
            ],
        },
    )
    assert batch.status_code == 201, batch.text

    resp = client.get(
        f"/api/v1/batches/{batch.json()['id']}/provenance", headers=auth(fpo_token)
    )
    assert resp.status_code == 200
    payload = resp.json()

    assert payload["batch"]["batch_code"] == "HC-TN-NLG-001"
    assert len(payload["harvest_sources"]) == 3
    assert len(payload["hive_sources"]) == 3
    assert payload["mass_balance"]["allocated_kg"] == 24.0
    assert payload["mass_balance"]["balanced"] is True
    assert {h["hive_code"] for h in payload["hive_sources"]} == {
        "NLG-101",
        "NLG-102",
        "NLG-103",
    }
    # Every documented key must exist even when a stage has no records yet.
    for key in (
        "batch",
        "harvest_sources",
        "hive_sources",
        "relations",
        "custody",
        "lab_tests",
        "certificates",
        "anchor",
        "mass_balance",
        "timeline",
    ):
        assert key in payload


def test_provenance_reflects_lab_and_custody_events(client, fpo_token, lab_token):
    _, harvest = _harvest(client, fpo_token, "NLG-201", 5.0)
    batch = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={
            "batch_code": "HC-TN-NLG-002",
            "quantity_kg": 5.0,
            "organization_id": "ORG-TN-001",
            "harvest_ids": [harvest["id"]],
        },
    ).json()

    client.post(
        f"/api/v1/batches/{batch['id']}/custody-events",
        headers=auth(fpo_token),
        json={"batch_id": batch["id"], "action": "COLLECTION", "notes": "received"},
    )
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

    payload = client.get(
        f"/api/v1/batches/{batch['id']}/provenance", headers=auth(fpo_token)
    ).json()
    assert any(c["action"] == "COLLECTION" for c in payload["custody"])
    assert any(t["status"] == "passed" for t in payload["lab_tests"])
    stages = {row["stage"] for row in payload["timeline"]}
    assert "HARVEST" in stages
    assert "COLLECTION" in stages
    assert "LAB_RESULT" in stages


def test_provenance_unknown_batch_is_404(client, fpo_token):
    resp = client.get("/api/v1/batches/does-not-exist/provenance", headers=auth(fpo_token))
    assert resp.status_code == 404
