from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository


class LabService:
    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    def request_test(self, *, batch_id: str, lab_id: str, note: str = "") -> dict[str, Any]:
        test = {
            "batch_id": batch_id,
            "lab_id": lab_id,
            "status": "requested",
            "requested_note": note,
            "requested_at": datetime.now(timezone.utc),
        }
        return self._repo.create_lab_test(test)

    def queue(self, lab_id: str, *, user: Any) -> list[dict[str, Any]]:
        rows = self._repo.list_lab_queue(lab_id)
        enriched = []
        for row in rows:
            batch = self._repo.get_batch(row["batch_id"]) or {}
            enriched.append(
                {
                    **row,
                    "batch_code": batch.get("batch_code", ""),
                    "honey_type": batch.get("honey_type", ""),
                }
            )
        return enriched

    def submit_result(
        self, test_id: str, *, result: str, tested_by: str, notes: str = ""
    ) -> dict[str, Any] | None:
        test = self._repo.get_lab_test(test_id)
        if test is None:
            return None
        status = "passed" if result.upper() == "PASS" else "failed"
        updated = self._repo.update_lab_test(
            test_id,
            {
                "status": status,
                "result": result.upper(),
                "tested_by": tested_by,
                "notes": notes,
                "tested_at": datetime.now(timezone.utc),
            },
        )
        self.update_batch_trust_from_tests(test.get("batch_id", ""))
        return updated

    def update_batch_trust_from_tests(self, batch_id: str) -> None:
        tests = self._repo.list_lab_tests(batch_id)
        latest = tests[-1] if tests else None
        if not latest:
            return
        if latest.get("status") == "passed":
            self._repo.update_batch(batch_id, {"trust_tier": "lab_verified"})

    def for_batch(self, batch_id: str) -> list[dict[str, Any]]:
        return self._repo.list_lab_tests(batch_id)