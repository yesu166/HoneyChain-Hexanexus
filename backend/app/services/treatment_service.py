from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository


class TreatmentService:
    """Treatments a beekeeper applies to a hive (e.g. varroa control)."""

    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    def create(
        self, *, beekeeper_id: str, data: dict[str, Any]
    ) -> dict[str, Any]:
        client_id = data.get("client_id") or ""
        data = {key: value for key, value in data.items() if value not in (None, "")}
        if client_id:
            existing = self._repo.find_by_client_id("treatments", client_id)
            if existing:
                return existing
        treatment = {
            "hive_id": data["hive_id"],
            "beekeeper_id": data.get("beekeeper_id") or beekeeper_id,
            "treated_at": data.get("treated_at") or datetime.now(timezone.utc),
            "treatment_name": data["treatment_name"],
            "active_ingredient": data.get("active_ingredient"),
            "dosage": data.get("dosage"),
            "observation": data.get("observation"),
            "status": data.get("status", "applied"),
        }
        return self._repo.create_treatment(treatment, client_id=client_id)

    def get_for_user(self, treatment_id: str, *, user: Any) -> dict[str, Any] | None:
        treatment = self._repo.get_treatment(treatment_id)
        if treatment is None:
            return None
        return self._resolve(treatment, user)

    def list_for_user(
        self,
        *,
        user: Any,
        hive_id: str = "",
        limit: int = 50,
    ) -> list[dict[str, Any]]:
        if user.role in ("admin", "institution"):
            rows = self._repo.list_treatments(None, hive_id=hive_id)
        elif user.role == "beekeeper":
            rows = self._repo.list_treatments(user.user_id, hive_id=hive_id)
        else:
            rows = self._repo.list_treatments(None, hive_id=hive_id, org_id=user.org_id)
        return rows[:limit]

    def latest_for_user(self, *, user: Any, hive_id: str) -> dict[str, Any] | None:
        rows = self.list_for_user(user=user, hive_id=hive_id, limit=1)
        return rows[0] if rows else None

    def _resolve(self, row: dict[str, Any], user: Any) -> dict[str, Any] | None:
        if user.role in ("admin", "institution"):
            return row
        if row.get("beekeeper_id") == user.user_id:
            return row
        beekeeper = self._repo.get_beekeeper(row.get("beekeeper_id", ""))
        if beekeeper and beekeeper.get("org_id") == user.org_id:
            return row
        return None