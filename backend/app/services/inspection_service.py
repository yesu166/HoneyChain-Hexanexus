from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository


class InspectionService:
    """Observations a beekeeper records on a hive check."""

    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    def create(
        self, *, beekeeper_id: str, data: dict[str, Any]
    ) -> dict[str, Any]:
        client_id = data.get("client_id") or ""
        data = {key: value for key, value in data.items() if value not in (None, "")}
        if client_id:
            existing = self._repo.find_by_client_id("inspections", client_id)
            if existing:
                return existing
        inspection = {
            "hive_id": data["hive_id"],
            "beekeeper_id": data.get("beekeeper_id") or beekeeper_id,
            "inspected_at": data.get("inspected_at")
            or datetime.now(timezone.utc),
            "activity_level": data.get("activity_level"),
            "queen_seen": data.get("queen_seen"),
            "brood_seen": data.get("brood_seen"),
            "food_stores": data.get("food_stores"),
            "pests_seen": data.get("pests_seen"),
            "dead_bees_seen": data.get("dead_bees_seen"),
            "hive_condition": data.get("hive_condition"),
            "observations": data.get("observations"),
        }
        return self._repo.create_inspection(inspection, client_id=client_id)

    def get_for_user(self, inspection_id: str, *, user: Any) -> dict[str, Any] | None:
        inspection = self._repo.get_inspection(inspection_id)
        if inspection is None:
            return None
        if self._owner_ok(inspection, fpo_allowed=False, user=user):
            return inspection
        return None

    def list_for_user(
        self,
        *,
        user: Any,
        hive_id: str = "",
        limit: int = 50,
    ) -> list[dict[str, Any]]:
        if user.role in ("admin", "institution"):
            rows = self._repo.list_inspections(None, hive_id=hive_id)
        elif user.role == "beekeeper":
            rows = self._repo.list_inspections(user.user_id, hive_id=hive_id)
        else:
            rows = self._repo.list_inspections(None, hive_id=hive_id, org_id=user.org_id)
        return rows[:limit]

    def latest_for_user(self, *, user: Any, hive_id: str) -> dict[str, Any] | None:
        rows = self.list_for_user(user=user, hive_id=hive_id, limit=1)
        return rows[0] if rows else None

    def _owner_ok(self, row: dict[str, Any], *, fpo_allowed: bool, user: Any) -> bool:
        if user.role in ("admin", "institution"):
            return True
        if row.get("beekeeper_id") == user.user_id:
            return True
        if fpo_allowed:
            beekeeper = self._repo.get_beekeeper(row.get("beekeeper_id", ""))
            if beekeeper and beekeeper.get("org_id") == user.org_id:
                return True
        return False