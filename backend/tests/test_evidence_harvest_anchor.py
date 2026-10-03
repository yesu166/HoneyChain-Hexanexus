"""Regression: a harvest evidence bundle must anchor against a real ledger batch.

The deployed chaincode's anchorMerkleRoot does
getStateOrThrow(ctx, "BATCH:{batchId}") before writing, so an anchor sent with an
empty batch id fails endorsement with NOT_FOUND and the app shows
"Saved — blockchain anchor pending". These tests pin the batch id the service
hands to the gateway for each entity type.
"""
from __future__ import annotations

import pytest

HARVEST_UUID = "3f2b7c14-9a55-4d1e-8c33-77b1e2a9d510"
BATCH_UUID = "6befa64d-8027-4779-b6b5-b0f95cd28d7f"


class _RecordingGateway:
    """Captures the batch_id the evidence service sends to the ledger."""

    ledger_name = "local"

    def __init__(self) -> None:
        self.calls: list[dict] = []

    def submit_anchor(self, *, batch_id, evidence_root, anchor_type="", organization_ref=""):
        self.calls.append(
            {
                "batch_id": batch_id,
                "evidence_root": evidence_root,
                "anchor_type": anchor_type,
                "organization_ref": organization_ref,
            }
        )
        return {
            "tx_hash": "a" * 64,
            "network": "fabric:mychannel",
            "state": "CONFIRMED",
        }

    def verify_anchor(self, ref, expected_root=""):
        return True


@pytest.fixture
def service():
    from app.services.evidence_service import HarvestEvidenceService

    return HarvestEvidenceService(repo=None, gateway=_RecordingGateway())


def _leaf(value: str) -> dict:
    return {"kind": "gps", "value": value, "content_hash": ""}


def test_harvest_anchor_uses_the_harvest_id_as_the_ledger_target(service):
    """A harvest must not anchor with an empty batch id."""
    gateway = service._gateway  # noqa: SLF001 - asserting the outbound call
    bundle = service.create_bundle(
        entity_type="harvest",
        entity_ref=HARVEST_UUID,
        evidence=[_leaf("9.8765,77.1234")],
        operator="Test Beekeeper",
        anchor=True,
    )

    assert gateway.calls, "the gateway must have been asked to anchor"
    sent = gateway.calls[0]["batch_id"]
    assert sent == HARVEST_UUID, (
        "harvest anchors must target the harvest id so the chaincode finds a "
        f"ledger batch; got {sent!r}"
    )
    # uuid-shaped, which is what _ensure_batch_on_ledger recognises
    assert len(sent) == 36 and sent.count("-") == 4
    assert bundle["anchor"]["state"] == "CONFIRMED"


def test_batch_anchor_is_unchanged(service):
    """The batch path must keep anchoring against the batch id itself."""
    gateway = service._gateway  # noqa: SLF001
    service.create_bundle(
        entity_type="batch",
        entity_ref=BATCH_UUID,
        evidence=[_leaf("batch-evidence")],
        operator="Nilgiris Honey FPO",
        anchor=True,
    )
    assert gateway.calls[0]["batch_id"] == BATCH_UUID
    assert gateway.calls[0]["anchor_type"] == "batch_evidence_bundle"


def test_harvest_anchor_type_is_still_harvest_specific(service):
    gateway = service._gateway  # noqa: SLF001
    service.create_bundle(
        entity_type="harvest",
        entity_ref=HARVEST_UUID,
        evidence=[_leaf("x")],
        operator="Test Beekeeper",
        anchor=True,
    )
    assert gateway.calls[0]["anchor_type"] == "harvest_evidence_bundle"


def test_non_uuid_ref_is_not_invented_into_a_batch_id(service):
    """Non-uuid refs stay empty rather than fabricating a ledger id."""
    gateway = service._gateway  # noqa: SLF001
    service.create_bundle(
        entity_type="assertion",
        entity_ref="not-a-uuid",
        evidence=[_leaf("y")],
        operator="KVIC",
        anchor=True,
    )
    assert gateway.calls[0]["batch_id"] == ""


def test_anchor_false_never_calls_the_ledger(service):
    gateway = service._gateway  # noqa: SLF001
    bundle = service.create_bundle(
        entity_type="harvest",
        entity_ref=HARVEST_UUID,
        evidence=[_leaf("z")],
        operator="Test Beekeeper",
        anchor=False,
    )
    assert gateway.calls == []
    assert bundle["anchor"] == {}
