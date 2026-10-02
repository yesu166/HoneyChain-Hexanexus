from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository
from .batch_service import VALID_CUSTODY_ACTIONS

# Custody action -> the workflow event the NEXT actor must see. Only actions
# that genuinely move the batch to another party or another state are emitted;
# everything else stays a plain provenance row.
_WORKFLOW_BY_ACTION: dict[str, tuple[str, str, str]] = {
    "COLLECTION": (
        "COLLECTION_ACCEPTED",
        "Harvest collected",
        "Arrange pickup or accept this material into your inventory.",
    ),
    "PROCESSING": (
        "PROCESSING_STARTED",
        "Processing started",
        "Track the processing step on this batch.",
    ),
    "PACKAGING": (
        "PACKAGED",
        "Batch packaged",
        "The batch is packed and ready for handover.",
    ),
    "TRANSFER": (
        "CUSTODY_TRANSFER",
        "Custody transferred",
        "Confirm receipt of this batch.",
    ),
}


class CustodyService:
    def __init__(
        self, repo: Repository, gateway: Any = None, notifications: Any = None
    ) -> None:
        self._repo = repo
        # BlockchainGateway facade; optional for tests. When present, an
        # accepted custody event is anchored to the ledger AFTER the DB write.
        self._gateway = gateway
        # Optional workflow sink: the custody row that moved the goods is the
        # same row that notifies both parties.
        self._notifications = notifications

    def _emit(self, **kwargs: Any) -> None:
        if self._notifications is None:
            return
        try:
            self._notifications.notify(**kwargs)
        except Exception:  # pragma: no cover - notification must never break a write
            pass

    def _anchor_transfer(self, *, batch_id: str, data: dict[str, Any], quantity_kg) -> dict[str, Any] | None:
        if self._gateway is None:
            return None
        try:
            return self._gateway.submit_custody_transfer(
                batch_id=batch_id,
                sender_ref=str(data.get("actor") or ""),
                receiver_ref=str(data.get("to_org") or data.get("to_actor") or ""),
                quantity_kg=float(quantity_kg or 0),
            )
        except Exception as exc:  # pragma: no cover - defensive
            # Honest reporting only: never fake success, never fail the DB row.
            return {"state": "UNKNOWN", "error": str(exc)}

    def add(self, *, batch_id: str, data: dict[str, Any]) -> dict[str, Any]:
        action = data["action"]
        if action not in VALID_CUSTODY_ACTIONS:
            raise ValueError(f"unsupported custody action: {action}")
        if action == "TRANSFER" and not (data.get("to_actor") or data.get("to_org")):
            raise ValueError("TRANSFER requires to_actor or to_org")
        quantity_kg = data.get("quantity_kg")
        # Fetched unconditionally: the workflow notification needs the owning
        # organization even when no quantity was supplied.
        batch = self._repo.get_batch(batch_id) or {}
        if quantity_kg is not None:
            if not batch:
                raise ValueError("batch not found")
            if float(quantity_kg) > float(batch.get("quantity_kg", 0) or 0) + 1e-6:
                raise ValueError("custody quantity exceeds batch quantity")
        client_id = str(data.get("client_id") or "")
        if client_id:
            for existing in reversed(self._repo.list_custody_events(batch_id)):
                if existing.get("client_id") == client_id:
                    return existing
        event = {
            "batch_id": batch_id,
            "action": action,
            "actor": data.get("actor", ""),
            "notes": data.get("notes", ""),
            "event_at": data.get("event_at") or datetime.now(timezone.utc),
            "to_actor": data.get("to_actor", ""),
            "to_org": data.get("to_org", ""),
            "quantity_kg": quantity_kg,
            "client_id": client_id,
        }
        row = self._repo.add_custody_event(event)
        # Anchored only after the DB event was accepted. tx_ref is a content
        # hash, so a repeated identical request resolves to the same
        # transaction (tracker short-circuits) — no duplicate provenance.
        tx = self._anchor_transfer(
            batch_id=batch_id, data=data, quantity_kg=quantity_kg
        )
        if tx is not None and isinstance(row, dict):
            row = {**row, "blockchain": tx}
        self._emit_workflow(
            action=action,
            batch_id=batch_id,
            batch=batch,
            data=data,
            row=row,
        )
        return row

    def _emit_workflow(
        self, *, action: str, batch_id: str, batch: dict[str, Any],
        data: dict[str, Any], row: Any,
    ) -> None:
        """Notify both parties from the custody row that was just persisted."""
        rule = _WORKFLOW_BY_ACTION.get(action)
        if rule is None:
            return
        event, title, recommended = rule
        batch_org = str(batch.get("organization_id") or "")
        to_org = str(data.get("to_org") or "")
        targets: list[str] = []
        if batch_org:
            targets.append(batch_org)
        if to_org and to_org not in targets:
            targets.append(to_org)
        qty = data.get("quantity_kg")
        qty_text = f" {qty} kg" if qty is not None else ""
        actor = str(data.get("actor") or "")
        body = (
            f"Batch {batch_id}{qty_text}: {title.lower()} "
            f"({action}){' by ' + actor if actor else ''}."
        )
        for org in targets:
            self._emit(
                event=event,
                title=title,
                body=body,
                organization_id=org,
                batch_id=batch_id,
                severity="info",
                recommended_action=recommended,
            )

    def list(self, batch_id: str) -> list[dict[str, Any]]:
        return self._repo.list_custody_events(batch_id)