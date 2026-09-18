"""Evidence-linked supply-chain assertions + derived verification state.

An assertion is a first-class, append-only statement about the physical chain:

    WHO (actor + organization + role authority)
      -> asserts WHAT (action + subject)
      -> about WHICH entity (harvest | batch)
      -> HOW MUCH (asserted quantity — never silently zero)
      -> at WHAT time (captured_at + server-recorded ledger ts)
      -> supported by WHICH evidence (evidence-bundle Merkle root)
      -> with WHICH authority (bounded by the caller's real role)
      -> connected to WHICH previous provenance (hash-chained prev_hash)
      -> and WHICH anchor, only when it genuinely benefits from tamper-evidence.

Storage rule (no duplicate systems): an assertion IS an event on the existing
hash-chained ledger (``ledger_events``, ``chain_id = entity_ref``), which already
provides durable persistence (Supabase), append-only ordering, fork preservation
and tamper-evidence. No new table and no new migration is introduced, so nothing
here can drift away from the provenance system of record.

Truth rules enforced in code:
  * A missing quantity is NEVER recorded as zero: an assertion either states a
    positive quantity or declares, explicitly, that it asserts none.
  * A client cannot promote its own authority: the effective authority is
    derived from the authenticated role and can only be clamped DOWN.
  * A verification level is derived from records the platform can actually
    prove (lab tests, certificates, anchors) — never from client claims.
  * Blockchain anchoring is reported as integrity of the digital *record*,
    never as physical/chemical authenticity of honey.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository, new_id
from .batch_service import BatchService
from .event_ledger import EventLedger

ASSERTION_EVENT_TYPE = "assertion"

# Actions describe what physical/operational step the actor asserts about.
ASSERTION_ACTIONS = (
    "HARVEST",
    "COLLECTION",
    "PROCESSING",
    "PACKAGING",
    "TRANSFER",
    "DISTRIBUTION",
    "SALE",
    "QUALITY_TEST",
    "INSPECTION",
    "CORRECTION",
)

# The subject is what the statement is ABOUT. This is what makes two assertions
# comparable across organizations and across different actions (a collector's
# received_quantity vs the processor's received_quantity).
ASSERTION_SUBJECTS = (
    "harvested_quantity",
    "dispatched_quantity",
    "received_quantity",
    "input_quantity",
    "output_quantity",
    "packaged_quantity",
    "batch_quantity",
    "quality_finding",
    "other",
)

# Subjects that MUST carry a quantity. Missing data is never turned into zero.
QUANTITY_SUBJECTS = tuple(
    s for s in ASSERTION_SUBJECTS if s not in ("quality_finding", "other")
)

# supporting = normal claim; adverse = a claim that something is wrong with the
# material (preserved and reviewed, never auto-concluded as fraud).
ASSERTION_NATURES = ("supporting", "adverse")

# Authority levels. These are DIFFERENT concepts:
#   SELF_DECLARED          the owning actor reports it
#   ORGANIZATION_VERIFIED  an organization (FPO/processor) confirms it
#   LAB_VERIFIED           a laboratory establishes a finding
#   AUTHORITY_VERIFIED     an oversight authority asserts it
#   PLATFORM_VERIFIED      platform governance records it
# Blockchain anchoring is deliberately NOT in this ladder: it is a separate
# integrity dimension (see dimensions.blockchain_anchored).
AUTHORITY_LEVELS = (
    "SELF_DECLARED",
    "ORGANIZATION_VERIFIED",
    "LAB_VERIFIED",
    "AUTHORITY_VERIFIED",
    "PLATFORM_VERIFIED",
)

_AUTHORITY_RANK = {level: rank for rank, level in enumerate(AUTHORITY_LEVELS)}

# Server-derived authority: the authenticated role sets the ceiling. The request
# body may ask for less (never more) and is clamped if it asks for more.
_ROLE_AUTHORITY = {
    "beekeeper": "SELF_DECLARED",
    "buyer": "SELF_DECLARED",
    "fpo": "ORGANIZATION_VERIFIED",
    "processor": "ORGANIZATION_VERIFIED",
    "lab": "LAB_VERIFIED",
    "institution": "AUTHORITY_VERIFIED",
    "platform_oversight": "PLATFORM_VERIFIED",
    "admin": "PLATFORM_VERIFIED",
}

_VERIFICATION_ORDER = (
    "SELF_DECLARED",
    "ORGANIZATION_VERIFIED",
    "LAB_VERIFIED",
    "AUTHORITY_VERIFIED",
)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _as_float(value: Any) -> float | None:
    """None for missing values — never 0.0 (missing is not zero)."""
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


class AssertionRejected(ValueError):
    """Raised when an assertion is not admissible."""


class AssertionService:
    """Create and read evidence-linked assertions; derive verification state."""

    def __init__(
        self,
        repo: Repository,
        ledger: EventLedger | None = None,
        gateway: Any = None,
        batch_service: BatchService | None = None,
    ) -> None:
        self._repo = repo
        self._ledger = ledger or EventLedger(repo)
        self._gateway = gateway
        self._batches = batch_service or BatchService(repo)

    # ------------------------------------------------------------------ read
    def _events(self, entity_ref: str) -> list[dict[str, Any]]:
        if self._repo is None:
            return []
        rows = self._repo.list_ledger_events(entity_ref)
        return sorted(rows, key=lambda r: (r.get("index", 0), str(r.get("ts") or "")))

    def _assertion_rows(self, entity_ref: str) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for row in self._events(entity_ref):
            if row.get("event_type") != ASSERTION_EVENT_TYPE:
                continue
            payload = dict(row.get("payload") or {})
            payload["ledger_hash"] = row.get("hash", "")
            payload["ledger_index"] = row.get("index")
            payload["prev_hash"] = row.get("prev_hash", "")
            out.append(payload)
        return out

    def list_for(self, entity_ref: str) -> list[dict[str, Any]]:
        """Every assertion ever made about [entity_ref], oldest first."""
        return self._assertion_rows(entity_ref)

    def latest_per_org(
        self, entity_ref: str, *, subject: str | None = None
    ) -> dict[tuple[str, str], dict[str, Any]]:
        """The CURRENT claim of each organization, keyed by (org_ref, subject).

        Append-only history is preserved: an organization that re-states a
        quantity supersedes its own earlier claim, but the earlier assertion
        stays on the chain and remains readable through [list_for].
        """
        latest: dict[tuple[str, str], dict[str, Any]] = {}
        for row in self._assertion_rows(entity_ref):
            if subject and row.get("subject") != subject:
                continue
            key = (str(row.get("organization_ref") or ""), str(row.get("subject") or ""))
            latest[key] = row  # rows are oldest-first, so the last write wins
        return latest

    def find_by_client_id(self, entity_ref: str, client_id: str) -> dict[str, Any] | None:
        if not client_id:
            return None
        for row in self._assertion_rows(entity_ref):
            if str(row.get("client_id") or "") == client_id:
                return row
        return None

# ---------------------------------------------------------------- create
    def create(
        self,
        *,
        user: Any,
        entity_type: str,
        entity_ref: str,
        action: str,
        subject: str,
        asserted_quantity_kg: float | None = None,
        unit: str = "kg",
        organization_ref: str = "",
        note: str = "",
        nature: str = "supporting",
        captured_at: str = "",
        device_id: str = "",
        evidence_bundle_id: str = "",
        evidence_root: str = "",
        declared_authority: str = "",
        client_id: str = "",
        anchor: bool = False,
    ) -> dict[str, Any]:
        """Append an assertion to the ledger. Raises AssertionRejected on misuse."""
        if entity_type not in ("harvest", "batch"):
            raise AssertionRejected("entity_type must be 'harvest' or 'batch'")
        if action not in ASSERTION_ACTIONS:
            raise AssertionRejected(f"unknown assertion action: {action}")
        if subject not in ASSERTION_SUBJECTS:
            raise AssertionRejected(f"unknown assertion subject: {subject}")
        if nature not in ASSERTION_NATURES:
            raise AssertionRejected(f"unknown assertion nature: {nature}")

        # --- idempotency (offline retry safety) ---------------------------
        existing = self.find_by_client_id(entity_ref, client_id)
        if existing is not None:
            existing["deduplicated"] = True
            return existing

        # --- entity must really exist and belong to the caller ------------
        if entity_type == "batch":
            if self._batches.get_for_user(entity_ref, user=user) is None:
                raise AssertionRejected("batch not in your scope")
        else:
            entity = self._repo.get_harvest(entity_ref)
            if entity is None:
                raise AssertionRejected("harvest not found")
            if str(getattr(user, "role", "") or "") == "beekeeper" and str(
                entity.get("beekeeper_id") or ""
            ) != str(getattr(user, "user_id", "") or ""):
                raise AssertionRejected("harvest not in your scope")

        # --- quantity semantics: missing is never zero --------------------
        quantity = _as_float(asserted_quantity_kg)
        if subject in QUANTITY_SUBJECTS:
            if quantity is None:
                raise AssertionRejected(
                    "asserted_quantity_kg is required for subject "
                    f"'{subject}' — missing quantity is never recorded as zero"
                )
            if quantity <= 0:
                raise AssertionRejected("asserted_quantity_kg must be > 0")
        elif quantity is not None and quantity <= 0:
            raise AssertionRejected("asserted_quantity_kg must be > 0 when supplied")

        # --- authority is server-derived and can only be clamped down -----
        role = str(getattr(user, "role", "") or "")
        ceiling = _ROLE_AUTHORITY.get(role, "SELF_DECLARED")

        # --- the actor cannot sign as another organization ----------------
        # organization_ref is server-clamped to the authenticated org for
        # domain roles; only platform-level roles may attest on behalf of
        # another organization (and the request is recorded either way).
        auth_org = str(getattr(user, "org_id", "") or "")
        requested_org = str(organization_ref or "").strip()
        if role not in ("institution", "platform_oversight", "admin"):
            if requested_org and requested_org != auth_org:
                raise AssertionRejected(
                    "organization_ref does not match the authenticated "
                    "organization — an actor cannot assert as another org"
                )
            organization_ref = auth_org
        else:
            organization_ref = requested_org or auth_org

        effective = ceiling
        clamped = False
        if declared_authority:
            requested = declared_authority.strip().upper()
            if requested not in _AUTHORITY_RANK:
                raise AssertionRejected(f"unknown authority level: {declared_authority}")
            if _AUTHORITY_RANK[requested] > _AUTHORITY_RANK[ceiling]:
                clamped = True
            else:
                effective = requested

        # --- evidence linkage reuses the existing bundle system -----------
        if evidence_bundle_id and not evidence_root:
            bundle = self._repo.get_evidence_bundle(evidence_bundle_id)
            if bundle is None:
                raise AssertionRejected(f"evidence bundle not found: {evidence_bundle_id}")
            evidence_root = str(bundle.get("root_hash") or "")

        anchor_receipt, anchor_state = self._maybe_anchor(
            entity_type=entity_type,
            entity_ref=entity_ref,
            evidence_root=evidence_root,
            organization_ref=organization_ref or str(getattr(user, "org_id", "") or ""),
            anchor=anchor,
        )

        payload: dict[str, Any] = {
            "assertion_id": new_id(),
            "entity_type": entity_type,
            "entity_ref": entity_ref,
            "action": action,
            "subject": subject,
            "nature": nature,
            "asserted_quantity_kg": quantity,
            "quantity_asserted": quantity is not None,
            "unit": unit,
            "organization_ref": organization_ref
            or str(getattr(user, "org_id", "") or ""),
            "actor_ref": str(getattr(user, "user_id", "") or ""),
            "actor_role": role,
            "authority": effective,
            "authority_requested": declared_authority or "",
            "authority_clamped": clamped,
            "captured_at": captured_at or "",
            "recorded_at": _now(),
            "note": note,
            "evidence_bundle_id": evidence_bundle_id,
            "evidence_root": evidence_root,
            "evidence_linked": bool(evidence_root),
            "anchor_requested": bool(anchor),
            "anchor": anchor_receipt,
            "anchor_state": anchor_state,
            "client_id": client_id,
        }

        event = self._ledger.append(
            chain_id=entity_ref,
            event_type=ASSERTION_EVENT_TYPE,
            entity_ref=entity_ref,
            payload=payload,
            device_id=device_id or str(getattr(user, "user_id", "") or ""),
        )
        payload["ledger_hash"] = event.hash
        payload["ledger_index"] = event.index
        payload["prev_hash"] = event.prev_hash
        return payload

    def _maybe_anchor(
        self,
        *,
        entity_type: str,
        entity_ref: str,
        evidence_root: str,
        organization_ref: str,
        anchor: bool,
    ) -> tuple[dict[str, Any] | None, str]:
        """Anchor only on request; report the REAL receipt or an honest skip."""
        if not anchor:
            return None, "not_requested"
        if entity_type != "batch":
            return None, "skipped:no_batch_context"
        if self._gateway is None:
            return None, "skipped:no_gateway"
        receipt = self._gateway.submit_anchor(
            batch_id=entity_ref,
            evidence_root=evidence_root or "",
            anchor_type="assertion",
            organization_ref=organization_ref,
        )
        record = {
            "tx_hash": str(receipt.get("tx_hash") or ""),
            "state": str(receipt.get("state") or ""),
            "network": str(receipt.get("network") or ""),
        }
        return record, (record["state"] or "unknown")

# ------------------------------------------------- verification (derived)
    def verification_state(
        self, entity_ref: str, *, entity_type: str = "batch"
    ) -> dict[str, Any]:
        """Derive the CURRENT verification picture from stored records only.

        History is never rewritten: a historical lab PASS stays a historical
        lab PASS even when later adverse evidence moves the current state to
        UNDER_REVIEW.
        """
        assertions = self._assertion_rows(entity_ref)
        historical: list[dict[str, Any]] = []
        dims = {
            "self_declared": True,
            "organization_verified": False,
            "lab_verified": False,
            "authority_verified": False,
            "blockchain_anchored": False,
        }

        for row in assertions:
            authority = str(row.get("authority") or "SELF_DECLARED")
            role = str(row.get("actor_role") or "")
            if authority == "ORGANIZATION_VERIFIED" or role in ("fpo", "processor"):
                dims["organization_verified"] = True
            if authority == "LAB_VERIFIED":
                dims["lab_verified"] = True
            if authority in ("AUTHORITY_VERIFIED", "PLATFORM_VERIFIED"):
                dims["authority_verified"] = True
            historical.append(
                {
                    "type": "ASSERTION",
                    "assertion_id": row.get("assertion_id"),
                    "action": row.get("action"),
                    "subject": row.get("subject"),
                    "nature": row.get("nature"),
                    "authority": authority,
                    "quantity_kg": row.get("asserted_quantity_kg"),
                    "at": row.get("recorded_at"),
                    "ledger_hash": row.get("ledger_hash"),
                    "blockchain_anchored": bool((row.get("anchor") or {}).get("tx_hash")),
                }
            )

        trust_tier = ""
        if entity_type == "batch":
            batch = self._repo.get_batch(entity_ref)
            if batch is not None:
                trust_tier = str(batch.get("trust_tier") or "")
                for test in self._repo.list_lab_tests(entity_ref):
                    if str(test.get("status") or "") == "passed":
                        dims["lab_verified"] = True
                    historical.append(
                        {
                            "type": "LAB_TEST",
                            "lab_id": test.get("lab_id", ""),
                            "result": test.get("result", ""),
                            "status": test.get("status", ""),
                            "at": test.get("tested_at"),
                        }
                    )
                for cert in self._repo.list_certificates(entity_ref):
                    if str(cert.get("status") or "ACTIVE").upper() != "REVOKED":
                        dims["lab_verified"] = True
                    historical.append(
                        {
                            "type": "CERTIFICATE",
                            "certificate_id": cert.get("certificate_id", ""),
                            "status": cert.get("status", ""),
                            "content_hash": cert.get("content_hash", ""),
                            "at": cert.get("issued_at"),
                        }
                    )
                anchor = self._repo.get_anchor(entity_ref)
                if anchor and str(anchor.get("chain_status") or "") == "anchored":
                    dims["blockchain_anchored"] = True
                    historical.append(
                        {
                            "type": "ANCHOR",
                            "data_hash": anchor.get("data_hash", ""),
                            "tx_hash": anchor.get("tx_hash", ""),
                            "at": anchor.get("anchored_at"),
                            "note": "integrity of the record — not chemical authenticity",
                        }
                    )

        current_level = "SELF_DECLARED"
        for level in _VERIFICATION_ORDER:
            if dims.get(level.lower()):
                current_level = level

        adverse = [r for r in assertions if str(r.get("nature") or "") == "adverse"]
        open_discrepancies = self._open_discrepancy_count(entity_ref)
        active_impacts = self._impact_count(entity_ref)
        return {
            "entity_ref": entity_ref,
            "entity_type": entity_type,
            "current_verification_level": current_level,
            "review_state": (
                "UNDER_REVIEW"
                if (adverse or open_discrepancies or active_impacts)
                else "CLEAR"
            ),
            "dimensions": dims,
            "trust_tier_recorded": trust_tier,
            "open_discrepancies": open_discrepancies,
            "adverse_assertions": len(adverse),
            "active_impacts": active_impacts,
            "historical": historical,
            "assertion_count": len(assertions),
            "note": (
                "blockchain_anchored establishes integrity of the stored record; "
                "it does not establish purity, taste, nutrition or health claims."
            ),
        }

    def _open_discrepancy_count(self, entity_ref: str) -> int:
        """Count discrepancies without a resolving event (delegated fold)."""
        from .reconciliation_service import ReconciliationService

        rows = ReconciliationService(self._repo).ledger(entity_ref)
        return sum(1 for row in rows if row.get("status") in ("OPEN", "UNDER_REVIEW"))

    def _impact_count(self, entity_ref: str) -> int:
        """Impact markers recorded on this entity that are not yet CLEARED."""
        from .impact_service import IMPACT_EVENT_TYPE

        latest: dict[str, str] = {}
        for row in self._events(entity_ref):
            if row.get("event_type") != IMPACT_EVENT_TYPE:
                continue
            payload = row.get("payload") or {}
            latest[str(payload.get("impact_id") or "")] = str(
                payload.get("status") or "REVIEW_REQUIRED"
            )
        return sum(1 for state in latest.values() if state != "CLEARED")

    # ------------------------------------------------------ offline sync aid
    def push_offline_assertion(self, item: dict[str, Any], *, user: Any) -> dict[str, Any]:
        """Accept an assertion created offline (idempotent by client_id).

        The phone's local identity, creation timestamp and idempotency key are
        preserved verbatim; nothing is marked anchored before the server has
        actually anchored it (the anchor receipt is issued here, server-side).
        """
        try:
            row = self.create(
                user=user,
                entity_type=str(item.get("entity_type") or ""),
                entity_ref=str(item.get("entity_ref") or ""),
                action=str(item.get("action") or ""),
                subject=str(item.get("subject") or ""),
                asserted_quantity_kg=item.get("asserted_quantity_kg"),
                unit=str(item.get("unit") or "kg"),
                organization_ref=str(item.get("organization_ref") or ""),
                note=str(item.get("note") or ""),
                nature=str(item.get("nature") or "supporting"),
                captured_at=str(item.get("captured_at") or ""),
                device_id=str(item.get("device_id") or ""),
                evidence_bundle_id=str(item.get("evidence_bundle_id") or ""),
                evidence_root=str(item.get("evidence_root") or ""),
                declared_authority=str(item.get("declared_authority") or ""),
                client_id=str(item.get("client_id") or ""),
                anchor=bool(item.get("anchor")),
            )
        except AssertionRejected as exc:
            return {
                "accepted": False,
                "client_id": str(item.get("client_id") or ""),
                "error": str(exc),
            }
        return {
            "accepted": True,
            "client_id": str(item.get("client_id") or ""),
            "backend_id": row.get("assertion_id"),
            "ledger_hash": row.get("ledger_hash"),
            # True when this client_id was already on the ledger: the replayed
            # offline item is acknowledged, not duplicated.
            "deduplicated": bool(row.get("deduplicated")),
        }