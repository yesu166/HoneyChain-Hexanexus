from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository
from .batch_service import VALID_CUSTODY_ACTIONS


class CustodyService:
    def __init__(self, repo: Repository, gateway: Any = None) -> None:
        self._repo = repo
        # BlockchainGateway facade; optional for tests. When present, an
        # accepted custody event is anchored to the ledger AFTER the DB write.
        self._gateway = gateway

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
        if quantity_kg is not None:
            batch = self._repo.get_batch(batch_id)
            if batch is None:
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
        return row

    def list(self, batch_id: str) -> list[dict[str, Any]]:
        return self._repo.list_custody_events(batch_id)