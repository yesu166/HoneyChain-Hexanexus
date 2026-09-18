"""Quantity reconciliation: preserve conflicting assertions, never overwrite.

When two organizations report different facts about the same subject (a
collector says 100 kg was received, the processor says 98.6 kg), the platform
must NOT silently pick a winner. It records BOTH side by side and opens an
explicit discrepancy carrying:

  reference  (what is being compared against: organization + value + authority)
  claimant   (the deviating assertion: organization + value + authority)
  delta      (absolute difference in kg)
  tolerance  (explicitly recorded: max(absolute_kg, percent * reference))
  status     OPEN -> UNDER_REVIEW -> RESOLVED | UNRESOLVED

Nothing here accuses an organization of fraud: a discrepancy is a reconciliation
task with preserved evidence, and the resolution is itself an append-only ledger
event carrying the resolver, note and evidence commitment.

Storage: the existing hash-chained ledger (``ledger_events``). Original
assertion events are never modified — resolution appends, it does not rewrite.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository, new_id
from .assertion_service import QUANTITY_SUBJECTS, AssertionService
from .batch_service import BatchService
from .event_ledger import EventLedger

DISCREPANCY_EVENT_TYPE = "quantity_discrepancy"
RESOLUTION_EVENT_TYPE = "discrepancy_resolution"

DISCREPANCY_STATES = ("OPEN", "UNDER_REVIEW", "RESOLVED", "UNRESOLVED")
OPEN_STATES = ("OPEN", "UNDER_REVIEW")

# Explicit, documented tolerance defaults. A discrepancy is raised only when the
# difference exceeds BOTH the absolute floor and the relative band, so rounding
# noise (0.01 kg on a 5 kg jar lot) does not create false conflicts while a real
# 1.5 kg gap on 60 kg does.
DEFAULT_TOLERANCE_KG = 0.01
DEFAULT_TOLERANCE_PCT = 0.005  # 0.5 %

_AUTHORITY_RANK = {
    "SELF_DECLARED": 0,
    "ORGANIZATION_VERIFIED": 1,
    "LAB_VERIFIED": 2,
    "AUTHORITY_VERIFIED": 3,
    "PLATFORM_VERIFIED": 4,
}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def tolerance_for(reference: float, *, tolerance_kg: float, tolerance_pct: float) -> float:
    """The band that must be exceeded before a discrepancy is raised."""
    return max(abs(tolerance_kg), abs(tolerance_pct) * abs(reference))


class ReconciliationService:
    def __init__(
        self,
        repo: Repository,
        assertions: AssertionService | None = None,
        batch_service: BatchService | None = None,
        ledger: EventLedger | None = None,
    ) -> None:
        self._repo = repo
        self._assertions = assertions or AssertionService(repo)
        self._batches = batch_service or BatchService(repo)
        self._ledger = ledger or EventLedger(repo)

    # ------------------------------------------------------------------ read
    def _events(self, entity_ref: str) -> list[dict[str, Any]]:
        if self._repo is None:
            return []
        rows = self._repo.list_ledger_events(entity_ref)
        return sorted(rows, key=lambda r: (r.get("index", 0), str(r.get("ts") or "")))

    def _raw(self, entity_ref: str, event_type: str) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for row in self._events(entity_ref):
            if row.get("event_type") != event_type:
                continue
            payload = dict(row.get("payload") or {})
            payload["ledger_hash"] = row.get("hash", "")
            payload["ledger_index"] = row.get("index")
            out.append(payload)
        return out

    def ledger(self, entity_ref: str) -> list[dict[str, Any]]:
        """Every discrepancy about [entity_ref] with its CURRENT status folded on.

        The stored discrepancy event itself is immutable; the status shown here
        is derived from the latest resolution event, which is preserved too.
        """
        discrepancies = self._raw(entity_ref, DISCREPANCY_EVENT_TYPE)
        resolutions = self._raw(entity_ref, RESOLUTION_EVENT_TYPE)
        by_id: dict[str, list[dict[str, Any]]] = {}
        for row in resolutions:
            by_id.setdefault(str(row.get("discrepancy_id") or ""), []).append(row)
        out: list[dict[str, Any]] = []
        for row in discrepancies:
            did = str(row.get("discrepancy_id") or "")
            history = by_id.get(did, [])
            latest = history[-1] if history else None
            merged = dict(row)
            merged["status"] = (
                str(latest.get("state")) if latest else str(row.get("status") or "OPEN")
            )
            merged["resolution"] = latest
            merged["resolution_history"] = history
            out.append(merged)
        return out

    def get(self, entity_ref: str, discrepancy_id: str) -> dict[str, Any] | None:
        for row in self.ledger(entity_ref):
            if row.get("discrepancy_id") == discrepancy_id:
                return row
        return None

# --------------------------------------------------------------- detect
    def detect(
        self,
        *,
        entity_ref: str,
        subject: str | None = None,
        tolerance_kg: float = DEFAULT_TOLERANCE_KG,
        tolerance_pct: float = DEFAULT_TOLERANCE_PCT,
        actor_ref: str = "",
        persist: bool = True,
    ) -> dict[str, Any]:
        """Compare each organization's current claim and open discrepancies."""
        latest = self._assertions.latest_per_org(entity_ref)
        groups: dict[str, dict[str, dict[str, Any]]] = {}
        for (org_ref, item_subject), row in latest.items():
            if subject and item_subject != subject:
                continue
            if item_subject not in QUANTITY_SUBJECTS:
                continue  # non-quantitative claims are not compared numerically
            if row.get("asserted_quantity_kg") is None:
                continue  # missing data is NOT treated as zero
            groups.setdefault(item_subject, {})[org_ref] = row

        found: list[dict[str, Any]] = []
        for item_subject, per_org in groups.items():
            if len(per_org) < 2:
                continue
            ranked = sorted(
                per_org.items(),
                key=lambda kv: (
                    -_AUTHORITY_RANK.get(str(kv[1].get("authority") or ""), 0),
                    str(kv[1].get("recorded_at") or ""),
                ),
            )
            ref_org, ref_row = ranked[0]
            ref_value = float(ref_row.get("asserted_quantity_kg") or 0)
            band = tolerance_for(
                ref_value, tolerance_kg=tolerance_kg, tolerance_pct=tolerance_pct
            )
            for org_ref, row in ranked[1:]:
                value = float(row.get("asserted_quantity_kg") or 0)
                delta = abs(value - ref_value)
                if delta <= band:
                    continue
                record = self._build_record(
                    entity_ref=entity_ref,
                    subject=item_subject,
                    kind="cross_organization_quantity",
                    reference=ref_org,
                    ref_row=ref_row,
                    ref_value=ref_value,
                    claimant=org_ref,
                    row=row,
                    value=value,
                    delta=delta,
                    band=band,
                    tolerance_kg=tolerance_kg,
                    tolerance_pct=tolerance_pct,
                    actor_ref=actor_ref,
                )
                found.extend(self._persist(record, persist=persist))

        control = self._control_total(
            entity_ref, tolerance_kg=tolerance_kg, tolerance_pct=tolerance_pct
        )
        if control is not None:
            found.extend(self._persist(control, persist=persist))

        open_rows = [r for r in self.ledger(entity_ref) if r.get("status") in OPEN_STATES]
        return {
            "entity_ref": entity_ref,
            "subjects_compared": sorted(groups.keys()),
            "tolerance_kg": tolerance_kg,
            "tolerance_percent": tolerance_pct,
            "raised": found,
            "open_discrepancies": open_rows,
            "open_count": len(open_rows),
        }

    def _persist(self, record: dict[str, Any], *, persist: bool) -> list[dict[str, Any]]:
        if not persist:
            return [record]
        existing = self._find_open(record)
        if existing is not None:
            existing = dict(existing)
            existing["deduplicated"] = True
            return [existing]
        event = self._ledger.append(
            chain_id=str(record.get("entity_ref") or ""),
            event_type=DISCREPANCY_EVENT_TYPE,
            entity_ref=str(record.get("entity_ref") or ""),
            payload=record,
            device_id=str(record.get("actor_ref") or ""),
        )
        record["ledger_hash"] = event.hash
        return [record]

    def _build_record(
        self,
        *,
        entity_ref: str,
        subject: str,
        kind: str,
        reference: str,
        ref_row: dict[str, Any],
        ref_value: float,
        claimant: str,
        row: dict[str, Any],
        value: float,
        delta: float,
        band: float,
        tolerance_kg: float,
        tolerance_pct: float,
        actor_ref: str,
    ) -> dict[str, Any]:
        """Both assertions are preserved verbatim inside the discrepancy."""
        return {
            "discrepancy_id": new_id(),
            "kind": kind,
            "subject": subject,
            "entity_ref": entity_ref,
            "status": "OPEN",
            "reference": {
                "organization_ref": reference,
                "asserted_quantity_kg": ref_value,
                "authority": ref_row.get("authority"),
                "assertion_id": ref_row.get("assertion_id"),
                "assertion_hash": ref_row.get("ledger_hash"),
                "recorded_at": ref_row.get("recorded_at"),
            },
            "claimant": {
                "organization_ref": claimant,
                "asserted_quantity_kg": value,
                "authority": row.get("authority"),
                "assertion_id": row.get("assertion_id"),
                "assertion_hash": row.get("ledger_hash"),
                "recorded_at": row.get("recorded_at"),
            },
            "delta_kg": round(delta, 6),
            "tolerance_kg": round(band, 6),
            "tolerance_absolute_kg": tolerance_kg,
            "tolerance_percent": tolerance_pct,
            "created_at": _now(),
            "actor_ref": actor_ref,
            "note": (
                "Both assertions are preserved as recorded. A discrepancy is a "
                "reconciliation task, not a finding of wrongdoing."
            ),
        }

    def _control_total(
        self, entity_ref: str, *, tolerance_kg: float, tolerance_pct: float
    ) -> dict[str, Any] | None:
        """Batch quantity vs the sum of its harvest allocations (mass balance)."""
        batch = self._repo.get_batch(entity_ref)
        if batch is None:
            return None
        linked = self._repo.list_batch_harvests(entity_ref)
        if not linked:
            return None
        allocated = sum(float(link.get("quantity_kg", 0) or 0) for link in linked)
        batch_qty = float(batch.get("quantity_kg", 0) or 0)
        delta = abs(allocated - batch_qty)
        band = tolerance_for(
            batch_qty, tolerance_kg=tolerance_kg, tolerance_pct=tolerance_pct
        )
        if delta <= band:
            return None
        return {
            "discrepancy_id": new_id(),
            "kind": "control_total",
            "subject": "batch_quantity",
            "entity_ref": entity_ref,
            "status": "OPEN",
            "reference": {
                "source": "batches.quantity_kg",
                "asserted_quantity_kg": batch_qty,
            },
            "claimant": {
                "source": "sum(batch_harvest_links.quantity_kg)",
                "asserted_quantity_kg": round(allocated, 6),
            },
            "delta_kg": round(delta, 6),
            "tolerance_kg": round(band, 6),
            "tolerance_absolute_kg": tolerance_kg,
            "tolerance_percent": tolerance_pct,
            "created_at": _now(),
            "note": "Upstream allocations do not explain the batch quantity.",
        }

    def _find_open(self, record: dict[str, Any]) -> dict[str, Any] | None:
        """Avoid duplicating an unresolved discrepancy for the same pair."""
        ref_org = str((record.get("reference") or {}).get("organization_ref") or "")
        claim_org = str((record.get("claimant") or {}).get("organization_ref") or "")
        subject = str(record.get("subject") or "")
        kind = str(record.get("kind") or "")
        for row in self.ledger(str(record.get("entity_ref") or "")):
            if row.get("status") not in OPEN_STATES:
                continue
            if row.get("subject") != subject or row.get("kind") != kind:
                continue
            if str((row.get("reference") or {}).get("organization_ref") or "") != ref_org:
                continue
            if str((row.get("claimant") or {}).get("organization_ref") or "") != claim_org:
                continue
            return row
        return None

# --------------------------------------------------------------- resolve
    def resolve(
        self,
        *,
        entity_ref: str,
        discrepancy_id: str,
        state: str,
        note: str = "",
        evidence_bundle_id: str = "",
        evidence_root: str = "",
        actor_ref: str = "",
    ) -> dict[str, Any]:
        """Append a resolution event. The original discrepancy is untouched."""
        if state not in ("UNDER_REVIEW", "RESOLVED", "UNRESOLVED"):
            raise ValueError("state must be one of UNDER_REVIEW, RESOLVED, UNRESOLVED")
        target = self.get(entity_ref, discrepancy_id)
        if target is None:
            raise ValueError(f"unknown discrepancy: {discrepancy_id}")
        if evidence_bundle_id and not evidence_root:
            bundle = self._repo.get_evidence_bundle(evidence_bundle_id)
            if bundle is None:
                raise ValueError(f"evidence bundle not found: {evidence_bundle_id}")
            evidence_root = str(bundle.get("root_hash") or "")

        record = {
            "discrepancy_id": discrepancy_id,
            "entity_ref": entity_ref,
            "state": state,
            "note": note,
            "evidence_bundle_id": evidence_bundle_id,
            "evidence_root": evidence_root,
            "resolved_by": actor_ref,
            "at": _now(),
        }
        event = self._ledger.append(
            chain_id=entity_ref,
            event_type=RESOLUTION_EVENT_TYPE,
            entity_ref=entity_ref,
            payload=record,
            device_id=actor_ref,
        )
        record["ledger_hash"] = event.hash
        record["discrepancy"] = self.get(entity_ref, discrepancy_id)
        return record