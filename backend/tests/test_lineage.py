from __future__ import annotations

import pytest

from app.db.supabase import InMemoryRepository
from app.services.event_ledger import EventLedger
from app.services.lineage_service import LineageService, StateTransitionError, validate_transition


def _service():
    repo = InMemoryRepository()
    return LineageService(repo, EventLedger(repo)), repo


def _seed_batch(repo, batch_id="BATCH-L1", status="created"):
    return repo.create_batch(
        {
            "id": batch_id,
            "batch_code": f"CODE-{batch_id}",
            "organization_id": "ORG-TN-001",
            "quantity_kg": 10.0,
            "status": status,
            "trust_tier": "self_declared",
        }
    )


def test_valid_transition():
    svc, repo = _service()
    _seed_batch(repo)
    result = svc.transition(batch_id="BATCH-L1", to_state="processing", actor_ref="op-1")
    assert result["from_state"] == "created"
    assert result["status"] == "processing"


def test_illegal_backwards_transition_rejected():
    svc, repo = _service()
    _seed_batch(repo, "BATCH-L2", status="distribution")
    with pytest.raises(StateTransitionError):
        svc.transition(batch_id="BATCH-L2", to_state="created")


def test_custody_moves_holder():
    svc, repo = _service()
    _seed_batch(repo, "BATCH-L3")
    svc.custody(
        batch_id="BATCH-L3", sender_ref="FPO-A", receiver_ref="PROC-B",
        quantity_kg=5.0, action="TRANSFER",
    )
    holder = svc.current_holder("BATCH-L3")
    assert holder["holder_ref"] == "PROC-B"


def test_validate_transition_table():
    assert validate_transition("created", "processing")
    assert validate_transition("packaged", "retail")
    assert not validate_transition("retail", "created")
    assert not validate_transition("rejected", "packaged")