from __future__ import annotations

import pytest

from app.db.supabase import InMemoryRepository
from app.services.event_ledger import EventLedger, LedgerIntegrityError


def _repo():
    return InMemoryRepository()


def test_append_chains_hashes():
    repo = _repo()
    ledger = EventLedger(repo)
    e1 = ledger.append(chain_id="BATCH-1", event_type="harvest", entity_ref="BATCH-1", payload={"q": 5})
    e2 = ledger.append(chain_id="BATCH-1", event_type="custody", entity_ref="BATCH-1", payload={"to": "X"})
    assert e2.prev_hash == e1.hash
    assert e1.hash != e2.hash
    report = ledger.verify_chain("BATCH-1")
    assert report["integrity_ok"] is True


def test_verify_chain_detects_tamper():
    repo = _repo()
    ledger = EventLedger(repo)
    ledger.append(chain_id="BATCH-2", event_type="harvest", entity_ref="BATCH-2", payload={"q": 10})
    ledger.append(chain_id="BATCH-2", event_type="custody", entity_ref="BATCH-2", payload={"to": "X"})
    ledger.tamper_chain("BATCH-2", 0)
    report = ledger.verify_chain("BATCH-2")
    assert report["integrity_ok"] is False
    assert any(i["kind"] == "hash_mismatch" for i in report["issues"])


def test_fork_preserves_both_records():
    repo = _repo()
    ledger = EventLedger(repo)
    e0 = ledger.append(chain_id="BATCH-3", event_type="harvest", entity_ref="BATCH-3", payload={"q": 3})
    branch_a = ledger.append(chain_id="BATCH-3", event_type="custody", entity_ref="BATCH-3", payload={"to": "A"})
    branch_b = ledger.append(
        chain_id="BATCH-3",
        event_type="custody",
        entity_ref="BATCH-3",
        payload={"to": "B"},
        prev_hash=e0.hash,  # explicit: diverges from branch_a at the same head
    )
    assert branch_a.hash != branch_b.hash
    heads = ledger.chain_heads("BATCH-3")
    # Both branches survive; never silently collapsed.
    assert len(heads) == 2
    assert {h.payload.get("to") for h in heads} == {"A", "B"}
    events = repo.list_ledger_events("BATCH-3")
    assert any(e.get("event_type") == "fork" for e in events)


def test_head_hash_is_stable():
    repo = _repo()
    ledger = EventLedger(repo)
    ledger.append(chain_id="C", event_type="a", entity_ref="C", payload={"i": 1})
    h1 = ledger.head_hash("C")
    h2 = ledger.head_hash("C")
    assert h1 == h2