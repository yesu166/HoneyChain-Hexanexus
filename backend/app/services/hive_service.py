from __future__ import annotations

from typing import Any

from ..db.supabase import Repository, new_id


class HiveService:
    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    def create(self, *, beekeeper_id: str, data: dict[str, Any]) -> dict[str, Any]:
        client_id = data.get("client_id") or ""
        if client_id:
            existing = self._repo.find_by_client_id("hives", client_id)
            if existing:
                return existing
        hive = {
            "beekeeper_id": data.get("beekeeper_id") or beekeeper_id,
            "hive_code": data["hive_code"],
            "status": data.get("status") or "active",
            "location": data.get("location"),
        }
        return self._repo.create_hive(hive, client_id=client_id)

    def get_for_user(
        self, hive_id: str, *, user: Any
    ) -> dict[str, Any] | None:
        hive = self._repo.get_hive(hive_id)
        if hive is None:
            return None
        if user.role in ("admin", "institution"):
            return hive
        if hive.get("beekeeper_id") == user.user_id:
            return hive
        beekeeper = self._repo.get_beekeeper(hive.get("beekeeper_id", ""))
        if beekeeper and beekeeper.get("org_id") and beekeeper.get("org_id") == user.org_id:
            return hive
        return None

    def list_for_user(self, *, user: Any) -> list[dict[str, Any]]:
        if user.role in ("admin", "institution"):
            return self._repo.list_hives(None)
        if user.role == "beekeeper":
            return self._repo.list_hives(user.user_id)
        org_beekeepers = self._repo.list_beekeepers(user.org_id)
        hives = []
        for beekeeper in org_beekeepers:
            hives.extend(self._repo.list_hives(beekeeper.get("id")))
        return hives

    def update(
        self, hive_id: str, updates: dict[str, Any]
    ) -> dict[str, Any] | None:
        return self._repo.update_hive(hive_id, updates)

    def add_reading(self, hive_id: str, data: dict[str, Any]) -> dict[str, Any]:
        from datetime import datetime, timezone

        reading = {
            "hive_id": hive_id,
            "temperature_c": data.get("temperature_c"),
            "humidity_percent": data.get("humidity_percent"),
            "weight_kg": data.get("weight_kg"),
            "recorded_at": data.get("recorded_at") or datetime.now(timezone.utc),
            "source": data.get("source", "manual"),
        }
        return self._repo.add_reading(reading)

    def readings(self, hive_id: str, limit: int = 100) -> list[dict[str, Any]]:
        return self._repo.list_readings(hive_id, limit)