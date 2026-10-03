from __future__ import annotations

from tests.conftest import auth, make_token


def _admin() -> dict:
    return auth(make_token("u-admin-journey", "admin"))


def test_admin_can_run_the_whole_honey_journey(client):
    """The master demo role must drive the full chain unaided.

    organization -> beekeeper -> hive -> harvest -> batch -> evidence
    (SHA-256 / Merkle) -> anchor + read-back -> processing -> packaging
    -> Honey Passport. Asserted on status codes, so a regression that hides
    a page from admin fails here rather than in front of a judge.
    """
    admin = _admin()

    # --- organization + governance -------------------------------------
    org = client.post(
        "/api/v1/platform/organizations", json={"name": "Journey FPO"}, headers=admin
    )
    assert org.status_code == 201, org.text
    org_key = org.json()["organization_key"]
    assert client.post(
        f"/api/v1/platform/organizations/{org_key}/activate", headers=admin
    ).status_code == 200

    # --- beekeeper, onboarded and assigned by admin --------------------
    invite = client.post(
        f"/api/v1/platform/organizations/{org_key}/admins",
        json={"email": "journey-chief@example.in", "role": "fpo"},
        headers=admin,
    )
    assert invite.status_code == 200, invite.text

    beekeeper = client.post(
        "/api/v1/auth/register",
        json={
            "email": "journey-bee@example.in",
            "name": "Journey Beekeeper",
            "phone": "+919000000901",
            "password": "Str0ngPass!42",
            "role": "beekeeper",
        },
    )
    assert beekeeper.status_code == 201, beekeeper.text
    assigned = client.post(
        f"/api/v1/platform/organizations/{org_key}/beekeepers",
        json={"user_id": beekeeper.json()["id"]},
        headers=admin,
    )
    assert assigned.status_code == 200, assigned.text
    assert client.get(
        f"/api/v1/platform/organizations/{org_key}/members", headers=admin
    ).status_code == 200

    # --- hive + harvest + batch ----------------------------------------
    hive = client.post("/api/v1/hives", json={"hive_code": "HIVE-JOURNEY-1"}, headers=admin)
    assert hive.status_code == 201, hive.text
    harvest = client.post(
        "/api/v1/harvests",
        json={"hive_id": hive.json()["id"], "quantity_kg": 12.5},
        headers=admin,
    )
    assert harvest.status_code == 201, harvest.text
    batch = client.post(
        "/api/v1/batches",
        json={
            "batch_code": "HC-JOURNEY-1",
            "quantity_kg": 12.5,
            "harvest_ids": [harvest.json()["id"]],
        },
        headers=admin,
    )
    assert batch.status_code == 201, batch.text
    batch_id = batch.json()["id"]
    batch_code = batch.json()["batch_code"]

    # --- evidence: Merkle root, anchor, read-back -----------------------
    bundle = client.post(
        "/api/v1/evidence/bundles",
        json={
            "entity_type": "batch",
            "entity_ref": batch_id,
            "evidence": [
                {"kind": "photo", "content_hash": "a" * 64},
                {"kind": "gps", "latitude": 11.4, "longitude": 76.7},
            ],
            "operator": "u-admin-journey",
            "anchor": True,
        },
        headers=admin,
    )
    assert bundle.status_code == 200, bundle.text
    body = bundle.json()
    assert body["root_hash"], "Merkle root must be computed"
    anchor = body["anchor"]
    assert anchor["state"] == "CONFIRMED", anchor
    assert anchor["tx_hash"], "a real anchor must return a transaction hash"
    # NB: conftest pins BLOCKCHAIN_ADAPTER=simulated, so this suite anchors
    # against the local ledger and its ids are the honest "LOCAL-*" ones. That is
    # correct here, not a defect: the real Hyperledger Fabric anchor (a 64-hex tx
    # id with no LOCAL-) is proven live against EC2, never simulated in tests.

    verify = client.post(f"/api/v1/evidence/bundles/{body['bundle_id']}/verify", headers=admin)
    assert verify.status_code == 200, verify.text
    assert verify.json()["evidence_intact"] is True
    assert verify.json()["anchored"] is True

    # --- processing + packaging ----------------------------------------
    for stage in ("processing", "packaged"):
        resp = client.put(f"/api/v1/batches/{batch_id}", json={"status": stage}, headers=admin)
        assert resp.status_code == 200, f"{stage}: {resp.text}"
    assert client.get(f"/api/v1/batches/{batch_id}", headers=admin).status_code == 200

    # --- Honey Passport read-back ---------------------------------------
    passport = client.get(f"/api/v1/passport/{batch_code}", headers=admin)
    assert passport.status_code == 200, passport.text
    assert passport.json()["batch_code"] == batch_code


def test_admin_reaches_ledger_audit_and_alert_surfaces(client):
    admin = _admin()
    assert client.get("/api/v1/blockchain/health", headers=admin).status_code == 200
    assert client.get("/api/v1/platform/audit", headers=admin).status_code == 200
    assert client.get("/api/v1/platform/organizations", headers=admin).status_code == 200
    assert client.get("/api/v1/platform/beekeepers", headers=admin).status_code == 200
    assert client.get("/api/v1/notifications", headers=admin).status_code == 200


def test_beekeeper_still_cannot_reach_platform_governance(client):
    """Admin's new access must not leak into any other role."""
    beekeeper = auth(make_token("u-journey-bk", "beekeeper", "ORG-TN-001"))
    assert client.get("/api/v1/platform/organizations", headers=beekeeper).status_code == 403
    assert client.get("/api/v1/platform/beekeepers", headers=beekeeper).status_code == 403
    assert client.post(
        "/api/v1/platform/organizations", json={"name": "Rogue"}, headers=beekeeper
    ).status_code == 403