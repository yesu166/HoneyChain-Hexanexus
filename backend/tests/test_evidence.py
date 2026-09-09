from __future__ import annotations

import pytest

from app.adapters.blockchain.gateway import LocalLedgerAdapter, build_blockchain_gateway
from app.core.config import Settings
from app.db.supabase import InMemoryRepository
from app.services.evidence_service import BundleNotFound, HarvestEvidenceService


def _service():
    repo = InMemoryRepository()
    gateway = build_blockchain_gateway()
    return HarvestEvidenceService(repo, gateway), repo


def test_create_bundle_builds_merkle_root_and_anchor():
    service, _ = _service()
    bundle = service.create_bundle(
        entity_type="harvest",
        entity_ref="HARV-1",
        evidence=[
            {"kind": "photo", "content_hash": "abc123"},
            {"kind": "gps", "latitude": 11.4, "longitude": 76.7},
        ],
        operator="op-1",
        anchor=True,
    )
    assert bundle["root_hash"]
    assert bundle["leaf_count"] == 2
    assert bundle["anchor"]["state"] == "CONFIRMED"


def test_verify_bundle_pass():
    service, _ = _service()
    bundle = service.create_bundle(
        entity_type="batch",
        entity_ref="BATCH-E1",
        evidence=[{"kind": "photo", "content_hash": "h1"}],
        anchor=True,
    )
    result = service.verify_bundle(bundle["bundle_id"])
    assert result["evidence_intact"] is True
    assert result["anchored"] is True


def test_evidence_proof_verifies_against_root():
    service, _ = _service()
    bundle = service.create_bundle(
        entity_type="harvest",
        entity_ref="HARV-2",
        evidence=[
            {"kind": "gps", "latitude": 1.0, "longitude": 2.0},
            {"kind": "photo", "content_hash": "p2"},
            {"kind": "photo", "content_hash": "p3"},
        ],
        anchor=True,
    )
    ev = bundle["evidence"][1]
    proof = service.evidence_proof(bundle["bundle_id"], ev["evidence_id"])
    assert proof["proof"]
    check = service.verify_evidence_proof(
        leaf_hash=proof["leaf_hash"],
        proof=proof["proof"],
        root_hash=proof["root_hash"],
    )
    assert check["proof_valid"] is True


def test_tampered_evidence_detected():
    service, repo = _service()
    bundle = service.create_bundle(
        entity_type="harvest",
        entity_ref="HARV-3",
        evidence=[{"kind": "photo", "content_hash": "orig"}],
        anchor=True,
    )
    stored = repo.get_evidence_bundle(bundle["bundle_id"])
    stored["evidence"][0]["payload"]["content_hash"] = "changed"
    result = service.verify_bundle(bundle["bundle_id"])
    assert result["evidence_intact"] is False


def test_bundle_not_found_raises():
    service, _ = _service()
    with pytest.raises(BundleNotFound):
        service.verify_bundle("nope")


def test_include_telemetry_appends_commitment_leaf():
    service, repo = _service()
    for seq in (1, 2, 3):
        repo.add_telemetry_event(
            {
                "event_id": f"EV-{seq}",
                "device_id": "HC-SIM-1",
                "sequence": seq,
                "timestamp": f"2026-09-09T08:0{seq}:00+00:00",
                "payload": {"temperature_c": 30.0 + seq},
                "payload_hash": f"hash{seq}",
                "previous_event_hash": "",
                "signature": "",
                "hive_id": "HIVE-T-1",
                "organization_id": "ORG-TN-001",
                "is_simulated": True,
                "created_at": "2026-09-09T08:00:00+00:00",
            }
        )
    bundle = service.create_bundle(
        entity_type="harvest",
        entity_ref="HARV-4",
        evidence=[{"kind": "photo", "content_hash": "shot"}],
        operator="op-1",
        anchor=True,
        include_telemetry=True,
        telemetry_hive_id="HIVE-T-1",
    )
    kinds = [e["payload"]["kind"] for e in bundle["evidence"]]
    assert "telemetry_reference" in kinds
    ref = next(e for e in bundle["evidence"] if e["payload"]["kind"] == "telemetry_reference")
    assert ref["payload"]["value"]
    assert "commitment" in ref["payload"]["value"]
    assert bundle["leaf_count"] == 2

    result = service.verify_bundle(bundle["bundle_id"])
    assert result["evidence_intact"] is True

    # Tampering with a referenced event changes the leaf hash
    stored = repo.get_evidence_bundle(bundle["bundle_id"])
    packed = stored["evidence"][1]
    stored["evidence"][1]["payload"] = {
        **packed["payload"],
        "value": packed["payload"]["value"].replace("HIVE-T-1", "HIVE-T-2"),
    }
    result = service.verify_bundle(bundle["bundle_id"])
    assert result["evidence_intact"] is False


def test_include_telemetry_without_events_raises():
    service, _ = _service()
    with pytest.raises(ValueError, match="no telemetry"):
        service.create_bundle(
            entity_type="harvest",
            entity_ref="HARV-5",
            evidence=[{"kind": "photo", "content_hash": "x"}],
            include_telemetry=True,
            telemetry_hive_id="HIVE-EMPTY",
        )