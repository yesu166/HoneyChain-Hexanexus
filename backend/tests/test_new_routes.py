from __future__ import annotations

from tests.conftest import auth, make_token


def test_health_ready_endpoints(client):
    assert client.get("/health/live").status_code == 200
    ready = client.get("/health/ready").json()
    assert ready["check"] == "ready"
    assert ready["dependencies"]["database"] == "ok"


def test_create_and_verify_evidence_bundle(client, demo_token):
    resp = client.post(
        "/api/v1/evidence/bundles",
        headers=auth(demo_token),
        json={
            "entity_type": "harvest",
            "entity_ref": "HARV-API-1",
            "operator": "Ravi",
            "evidence": [
                {"kind": "photo", "content_hash": "apihash1", "captured_at": "2026-01-01T00:00:00Z"},
                {"kind": "gps", "latitude": 11.4, "longitude": 76.7},
            ],
            "anchor": True,
        },
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["root_hash"]
    assert data["anchor"]["state"] == "CONFIRMED"

    verify = client.post(
        f"/api/v1/evidence/bundles/{data['bundle_id']}/verify",
        headers=auth(demo_token),
    )
    assert verify.status_code == 200
    assert verify.json()["evidence_intact"] is True


def test_evidence_proof_endpoint(client, demo_token):
    bundle = client.post(
        "/api/v1/evidence/bundles",
        headers=auth(demo_token),
        json={
            "entity_type": "harvest",
            "entity_ref": "HARV-API-1",
            "evidence": [
                {"kind": "photo", "content_hash": "p1"},
                {"kind": "photo", "content_hash": "p2"},
            ],
            "anchor": True,
        },
    ).json()
    ev = bundle["evidence"][0]
    proof = client.post(
        f"/api/v1/evidence/proof/{bundle['bundle_id']}/{ev['evidence_id']}",
        headers=auth(demo_token),
    )
    assert proof.status_code == 200
    verify = client.post(
        "/api/v1/evidence/verify-proof",
        headers=auth(demo_token),
        json={
            "leaf_hash": proof.json()["leaf_hash"],
            "proof": proof.json()["proof"],
            "root_hash": proof.json()["root_hash"],
        },
    )
    assert verify.json()["proof_valid"] is True


def test_batch_evidence_requires_batch_in_scope(client, fpo_token, demo_token):
    created = client.post(
        "/api/v1/batches",
        headers=auth(fpo_token),
        json={"batch_code": "B-API-2", "quantity_kg": 12.5},
    )
    assert created.status_code == 201, created.text
    batch_id = created.json()["id"]

    ok = client.post(
        "/api/v1/evidence/bundles",
        headers=auth(fpo_token),
        json={
            "entity_type": "batch",
            "entity_ref": batch_id,
            "evidence": [{"kind": "photo", "content_hash": "p1"}],
            "anchor": True,
        },
    )
    assert ok.status_code == 200, ok.text

    not_owned = client.post(
        "/api/v1/evidence/bundles",
        headers=auth(demo_token),
        json={
            "entity_type": "batch",
            "entity_ref": batch_id,
            "evidence": [{"kind": "photo", "content_hash": "p1"}],
            "anchor": True,
        },
    )
    assert not_owned.status_code == 403

    unknown = client.post(
        "/api/v1/evidence/bundles",
        headers=auth(fpo_token),
        json={
            "entity_type": "batch",
            "entity_ref": "NO-SUCH-BATCH",
            "evidence": [{"kind": "photo", "content_hash": "p1"}],
            "anchor": True,
        },
    )
    assert unknown.status_code == 403


def test_lab_certificate_lifecycle_via_api(client, lab_token, fpo_token, admin_token):
    issued = client.post(
        "/api/v1/certificates/issue",
        headers=auth(lab_token),
        json={
            "batch_id": "BATCH-CERT-1",
            "lab_id": "LAB-TN-001",
            "certificate_type": "analysis",
            "issuer_name": "Lab One",
        },
    )
    assert issued.status_code == 200, issued.text
    cert_id = issued.json()["certificate_id"]

    verify = client.get(f"/api/v1/certificates/verify/{cert_id}")
    assert verify.json()["verified"] is True

    revoked = client.post(
        f"/api/v1/certificates/{cert_id}/revoke",
        headers=auth(lab_token),
        json={"reason": "sample contamination"},
    )
    assert revoked.status_code == 200
    assert revoked.json()["status"] == "revoked"
    assert client.get(f"/api/v1/certificates/verify/{cert_id}").json()["verified"] is False


def test_batch_transition_via_api(client, fpo_token):
    resp = client.post(
        "/api/v1/batches/transition",
        headers=auth(fpo_token),
        json={"batch_id": "BATCH-LG-1", "to_state": "processing", "note": "qa begin"},
    )
    assert resp.status_code == 400  # batch does not exist
    assert "not found" in resp.json()["detail"]


def test_state_transition_rbac(client, demo_token):
    resp = client.post(
        "/api/v1/batches/transition",
        headers=auth(demo_token),
        json={"batch_id": "x", "to_state": "processing"},
    )
    assert resp.status_code == 403  # beekeeper lacks batch.update_status


def test_demo_tamper_requires_permission(client, demo_token):
    resp = client.post(
        "/api/v1/admin/tamper/ledger/CHAIN/0", headers=auth(demo_token)
    )
    assert resp.status_code == 403  # beekeeper has no demo.tamper


def test_blockchain_status_endpoint(client, fpo_token):
    resp = client.get("/api/v1/blockchain/status", headers=auth(fpo_token))
    assert resp.status_code == 200
    assert resp.json()["ledger"] == "local"