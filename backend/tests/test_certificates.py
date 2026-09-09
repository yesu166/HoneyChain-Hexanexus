from __future__ import annotations

import pytest

from app.adapters.blockchain.gateway import build_blockchain_gateway
from app.db.supabase import InMemoryRepository
from app.services.event_ledger import EventLedger
from app.services.lab_certificate import CertificateError, LabCertificateService


def _service():
    repo = InMemoryRepository()
    gateway = build_blockchain_gateway()
    ledger = EventLedger(repo)
    return LabCertificateService(repo, gateway, ledger), repo


def test_issue_certificate_active_and_anchored():
    service, _ = _service()
    cert = service.issue(
        batch_id="BATCH-C1",
        lab_id="LAB-TN-001",
        certificate_type="analysis",
        issuer_name="Test Lab",
    )
    assert cert["status"] == "active"
    assert cert["content_hash"]
    assert cert["anchor"]["state"] == "CONFIRMED"
    assert cert["certificate_id"]


def test_issue_then_verify():
    service, _ = _service()
    cert = service.issue(batch_id="BATCH-C2", lab_id="LAB", certificate_type="analysis")
    result = service.verify(cert["certificate_id"])
    assert result["verified"] is True
    assert result["status"] == "active"


def test_revoke_certificate_flips_verification():
    service, _ = _service()
    cert = service.issue(batch_id="BATCH-C3", lab_id="LAB", certificate_type="analysis")
    revoked = service.revoke(cert["certificate_id"], reason="fraud detected")
    assert revoked["status"] == "revoked"
    result = service.verify(cert["certificate_id"])
    assert result["verified"] is False
    assert any("revoked" in r for r in result["reasons"])


def test_revoke_missing_raises():
    service, _ = _service()
    with pytest.raises(CertificateError):
        service.revoke("does-not-exist", reason="x")


def test_certificates_for_batch():
    service, _ = _service()
    service.issue(batch_id="BATCH-C4", lab_id="LAB", certificate_type="analysis")
    service.issue(batch_id="BATCH-C4", lab_id="LAB", certificate_type="organic")
    assert len(service.for_batch("BATCH-C4")) == 2