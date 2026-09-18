"""Provenance impact analysis over the existing batch genealogy.

When something upstream becomes questionable, the question a supply chain
actually needs answered is: WHICH downstream lots are affected? This service
walks the existing `batch_genealogy` relations (children direction) and, for
each affected descendant, reports its current verification picture and appends
an append-only impact marker to that lot's own ledger chain.

Truth rules:
  * Historical results are never rewritten. A confirmed problem ADDS evidence
    and can change the CURRENT status; the original lab PASS/FAIL stays in the
    history exactly as recorded.
  * Nothing is inferred where the graph is silent: an affected set is only the
    real descendants reachable through stored relations.
  * No accusation: the marker is REVIEW_REQUIRED — a review task, not a verdict.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository, new_id
from .assertion_service import AssertionService
from .batch_service import BatchService
from .event_ledger import EventLedger
from .reconciliation_service import ReconciliationService

IMPACT_EVENT_TYPE = "provenance_impact"

IMPACT_STATUSES = ("REVIEW_REQUIRED", "CLEARED", "CONFIRMED")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class ProvenanceImpactService:
    """Downstream traversal + append-only impact marking."""

    def __init__(
        self,
        repo: Repository,
        batches: BatchService | None = None,
        assertions: AssertionService | None = None,
        reconciliation: ReconciliationService | None = None,
        ledger: EventLedger | None = None,
    ) -> None:
        self._repo = repo
        self._batches = batches or BatchService(repo)
        self._ledger = ledger or EventLedger(repo)
        self._assertions = assertions or AssertionService(repo, self._ledger)
        self._reconciliation = reconciliation or ReconciliationService(
            repo, self._assertions, self._batches, self._ledger
        )

    # ------------------------------------------------------------ traversal
    def descendants(self, batch_id: str, *, max_depth: int = 32) -> list[dict[str, Any]]:
        """Every batch downstream of [batch_id] through stored relations.

        BFS over ``batch_genealogy`` (children direction) so a split child, a
        merged lot and multi-hop processing chains (raw -> processed -> jar)
        are all reached. Cycle-safe and depth-bounded.
        """
        seen: set[str] = {batch_id}
        frontier: list[tuple[str, int, list[str]]] = [(batch_id, 0, [batch_id])]
        out: list[dict[str, Any]] = []
        while frontier:
            current, depth, path = frontier.pop(0)
            if depth >= max_depth:
                continue
            for rel in self._repo.list_batch_relations(current, direction="children"):
                child_id = str(rel.get("child_batch_id") or "")
                if not child_id or child_id in seen:
                    continue
                seen.add(child_id)
                child = self._repo.get_batch(child_id)
                if child is None:
                    continue
                row = {
                    "batch_id": child_id,
                    "batch_code": child.get("batch_code", ""),
                    "quantity_kg": child.get("quantity_kg"),
                    "status": child.get("status", ""),
                    "trust_tier": child.get("trust_tier", ""),
                    "relation_type": rel.get("relation_type", ""),
                    "depth": depth + 1,
                    "path": path + [child_id],
                    "path_codes": [
                        str((self._repo.get_batch(p) or {}).get("batch_code") or "")
                        for p in path + [child_id]
                    ],
                }
                out.append(row)
                frontier.append((child_id, depth + 1, path + [child_id]))
        out.sort(key=lambda r: (r["depth"], r["batch_code"]))
        return out

# -------------------------------------------------------------- analysis
    def analyse(
        self,
        *,
        entity_ref: str,
        reason: str,
        entity_type: str = "batch",
        evidence_root: str = "",
        evidence_bundle_id: str = "",
        actor_ref: str = "",
        status: str = "REVIEW_REQUIRED",
        record: bool = True,
    ) -> dict[str, Any]:
        """Identify the affected downstream lineage and mark it append-only."""
        if status not in IMPACT_STATUSES:
            raise ValueError(f"unknown impact status: {status}")
        if entity_type != "batch":
            raise ValueError("impact analysis currently requires entity_type 'batch'")

        source = self._repo.get_batch(entity_ref)
        if source is None:
            raise ValueError(f"batch not found: {entity_ref}")
        if evidence_bundle_id and not evidence_root:
            bundle = self._repo.get_evidence_bundle(evidence_bundle_id)
            if bundle is None:
                raise ValueError(f"evidence bundle not found: {evidence_bundle_id}")
            evidence_root = str(bundle.get("root_hash") or "")

        affected_rows = self.descendants(entity_ref)
        impact_id = new_id()
        at = _now()
        affected: list[dict[str, Any]] = []
        for row in affected_rows:
            state = self._assertions.verification_state(
                str(row["batch_id"]), entity_type="batch"
            )
            tests = self._repo.list_lab_tests(str(row["batch_id"]))
            affected.append(
                {
                    **row,
                    "current_verification_level": state.get("current_verification_level"),
                    "review_state": state.get("review_state"),
                    "open_discrepancies": state.get("open_discrepancies", 0),
                    "historical_lab_results": [
                        {
                            "status": t.get("status"),
                            "result": t.get("result"),
                            "at": t.get("tested_at"),
                        }
                        for t in tests
                    ],
                }
            )

        origin_state = self._assertions.verification_state(entity_ref, entity_type="batch")
        recorded: list[str] = []
        if record:
            targeted = [{"batch_id": entity_ref, "batch_code": source.get("batch_code"),
                         "depth": 0, "path_codes": [source.get("batch_code")]}]
            targeted.extend(affected)
            for row in targeted:
                payload = {
                    "impact_id": impact_id,
                    "source_entity_ref": entity_ref,
                    "source_batch_code": source.get("batch_code", ""),
                    "reason": reason,
                    "status": status,
                    "evidence_root": evidence_root,
                    "depth": row.get("depth", 0),
                    "path_codes": row.get("path_codes", []),
                    "actor_ref": actor_ref,
                    "at": at,
                    "note": (
                        "Append-only provenance marker. Historical results are "
                        "unchanged; current verification state may differ."
                    ),
                }
                event = self._ledger.append(
                    chain_id=str(row["batch_id"]),
                    event_type=IMPACT_EVENT_TYPE,
                    entity_ref=str(row["batch_id"]),
                    payload=payload,
                    device_id=actor_ref,
                )
                recorded.append(event.hash)

        return {
            "impact_id": impact_id,
            "source": {
                "batch_id": entity_ref,
                "batch_code": source.get("batch_code", ""),
                "quantity_kg": source.get("quantity_kg"),
                "current_verification_level": origin_state.get("current_verification_level"),
                "review_state": origin_state.get("review_state"),
            },
            "reason": reason,
            "status": status,
            "evidence_root": evidence_root,
            "affected": affected,
            "affected_count": len(affected),
            "recorded": bool(record),
            "ledger_hashes": recorded,
            "at": at,
        }

    def impacts_for(self, batch_id: str) -> list[dict[str, Any]]:
        """Every impact marker recorded on [batch_id]'s own chain."""
        out: list[dict[str, Any]] = []
        for row in self._repo.list_ledger_events(batch_id):
            if row.get("event_type") != IMPACT_EVENT_TYPE:
                continue
            payload = dict(row.get("payload") or {})
            payload["ledger_hash"] = row.get("hash", "")
            out.append(payload)
        return out