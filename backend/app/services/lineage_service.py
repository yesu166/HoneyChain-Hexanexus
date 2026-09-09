"""Batch lifecycle state machine + lineage events.

The batch state is explicit and event-driven. There is no hardcoded supply
chain path: any allowed transition is valid, and the event ledger records each
one. The state machine only rejects impossible transitions (e.g. going back to
``created`` from ``distribution``).

Trust rules live in batch_service (weakest-tier). Here we only guarantee
state-policy consistency.
"""
from __future__ import annotations

from typing import Any

from ..db.supabase import Repository
from .event_ledger import EventLedger

# Canonical batch lifecycle
BATCH_STATES = (
    "created",
    "in_harvest",
    "processing",
    "packaged",
    "in_qa",
    "distribution",
    "retail",
    "recalled",
    "rejected",
)

# Allowed forward transitions (events may also be corrective; corrections are
# recorded but never silently overwrite history).
ALLOWED_TRANSITIONS: dict[str, set[str]] = {
    "created": {"in_harvest", "processing", "rejected"},
    "in_harvest": {"processing", "in_qa", "rejected"},
    "processing": {"packaged", "rejected"},
    "packaged": {"in_qa", "distribution", "retail", "rejected"},
    "in_qa": {"packaged", "distribution", "rejected"},
    "distribution": {"retail", "recalled", "rejected"},
    "retail": {"recalled"},
    "recalled": {"rejected"},
    "rejected": set(),
}


class StateTransitionError(ValueError):
    pass


def validate_transition(from_state: str, to_state: str) -> bool:
    return to_state in ALLOWED_TRANSITIONS.get(from_state, set())


class LineageService:
    """Records state transitions + lineage (split/merge/transfer) events."""

    def __init__(self, repo: Repository, ledger: EventLedger | None = None) -> None:
        self._repo = repo
        self._ledger = ledger

    def transition(
        self,
        *,
        batch_id: str,
        to_state: str,
        actor_ref: str = "",
        note: str = "",
    ) -> dict[str, Any]:
        batch = self._repo.get_batch(batch_id)
        if batch is None:
            raise StateTransitionError(f"batch not found: {batch_id}")
        current = str(batch.get("status") or "created")
        if current == to_state:
            return {"batch_id": batch_id, "status": current, "changed": False}
        if not validate_transition(current, to_state):
            raise StateTransitionError(
                f"illegal batch transition {current} -> {to_state}"
            )

        self._repo.update_batch(batch_id, {"status": to_state})
        if self._ledger is not None:
            self._ledger.append(
                chain_id=batch_id,
                event_type="batch_state_transition",
                entity_ref=batch_id,
                payload={
                    "from_state": current,
                    "to_state": to_state,
                    "note": note,
                    "actor_ref": actor_ref,
                },
                device_id=actor_ref,
            )
        return {
            "batch_id": batch_id,
            "from_state": current,
            "status": to_state,
            "changed": True,
        }

    def custody(
        self,
        *,
        batch_id: str,
        sender_ref: str,
        receiver_ref: str,
        quantity_kg: float,
        action: str,
        actor_ref: str = "",
    ) -> dict[str, Any]:
        """Record a custody/transfer movement with a lineage event."""
        event = {
            "batch_id": batch_id,
            "action": action,
            "from_ref": sender_ref,
            "to_ref": receiver_ref,
            "quantity_kg": quantity_kg,
            "actor_ref": actor_ref or sender_ref,
        }
        row = self._repo.add_custody_event(event)
        if self._ledger is not None:
            self._ledger.append(
                chain_id=batch_id,
                event_type="custody_transfer",
                entity_ref=batch_id,
                payload=event,
                device_id=actor_ref,
            )
        return row

    def current_holder(self, batch_id: str) -> dict[str, Any]:
        events = self._repo.list_custody_events(batch_id)
        if not events:
            return {"batch_id": batch_id, "holder_ref": "origin"}
        last = events[-1]
        return {
            "batch_id": batch_id,
            "holder_ref": last.get("to_ref"),
            "since": last.get("event_at", ""),
            "event": last.get("action", ""),
        }