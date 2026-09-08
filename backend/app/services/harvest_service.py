from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository


class HarvestService:
    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    def create(
        self, *, beekeeper_id: str, data: dict[str, Any]
    ) -> dict[str, Any]:
        client_id = data.get("client_id") or ""
        if client_id:
            existing = self._repo.find_by_client_id("harvests", client_id)
            if existing:
                return existing
        harvest = {
            "hive_id": data["hive_id"],
            "beekeeper_id": data.get("beekeeper_id") or beekeeper_id,
            "harvested_at": data.get("harvested_at")
            or datetime.now(timezone.utc),
            "quantity_kg": data["quantity_kg"],
            "honey_type": data.get("honey_type", "Not specified"),
            "collected": False,
        }
        return self._repo.create_harvest(harvest, client_id=client_id)

    def get_for_user(self, harvest_id: str, *, user: Any) -> dict[str, Any] | None:
        harvest = self._repo.get_harvest(harvest_id)
        if harvest is None:
            return None
        if user.role in ("admin", "institution"):
            return harvest
        if harvest.get("beekeeper_id") == user.user_id:
            return harvest
        beekeeper = self._repo.get_beekeeper(harvest.get("beekeeper_id", ""))
        if beekeeper and beekeeper.get("org_id") == user.org_id:
            return harvest
        return None

    def list_for_user(self, *, user: Any) -> list[dict[str, Any]]:
        if user.role in ("admin", "institution"):
            return self._repo.list_harvests(None)
        if user.role == "beekeeper":
            return self._repo.list_harvests(user.user_id)
        return self._repo.list_harvests(None, org_id=user.org_id)