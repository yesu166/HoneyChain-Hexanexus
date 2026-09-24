from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository
from .batch_service import VALID_CUSTODY_ACTIONS


class CustodyService:
    def __init__(self, repo: Repository) -> None:
        self._repo = repo

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
        return self._repo.add_custody_event(event)

    def list(self, batch_id: str) -> list[dict[str, Any]]:
        return self._repo.list_custody_events(batch_id)