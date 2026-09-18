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
        event = {
            "batch_id": batch_id,
            "action": action,
            "actor": data.get("actor", ""),
            "notes": data.get("notes", ""),
            "event_at": data.get("event_at") or datetime.now(timezone.utc),
            "to_actor": data.get("to_actor", ""),
            "to_org": data.get("to_org", ""),
        }
        return self._repo.add_custody_event(event)

    def list(self, batch_id: str) -> list[dict[str, Any]]:
        return self._repo.list_custody_events(batch_id)