from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository

# Organization types / names that identify a laboratory in the directory. The
# selector is driven by real organization rows — never a hardcoded list.
_LAB_TYPE_TOKENS = ("lab", "laboratory")
_LAB_NAME_TOKENS = ("lab", "laboratory")


class LabService:
    def __init__(self, repo: Repository, notifications: Any = None) -> None:
        self._repo = repo
        # Optional workflow notification sink. When present, requesting,
        # starting, and completing a test each emit a persisted workflow event
        # so FPO / processor / KVIC inboxes reflect the real lab state.
        self._notifications = notifications

    # --------------------------------------------------------------- helpers
    def _emit(self, **kwargs: Any) -> None:
        if self._notifications is None:
            return
        try:
            self._notifications.notify(**kwargs)
        except Exception:  # pragma: no cover - notification must never break a write
            pass

    def _batch_org(self, batch_id: str) -> str:
        batch = self._repo.get_batch(batch_id) or {}
        return str(batch.get("organization_id") or "")

    # ---------------------------------------------------------------- writes
    def request_test(self, *, batch_id: str, lab_id: str, note: str = "") -> dict[str, Any]:
        test = {
            "batch_id": batch_id,
            "lab_id": lab_id,
            "status": "requested",
            "requested_note": note,
            "requested_at": datetime.now(timezone.utc),
        }
        created = self._repo.create_lab_test(test)
        self._emit(
            event="LAB_REQUESTED",
            title="Laboratory test requested",
            body=f"A laboratory test was requested for batch {batch_id}.",
            organization_id=self._batch_org(batch_id),
            batch_id=batch_id,
            recommended_action="The laboratory should start the test.",
        )
        return created

    def start_test(self, test_id: str, *, actor_ref: str = "") -> dict[str, Any] | None:
        """Move a requested test into explicit IN TESTING state.

        The backend previously jumped from `requested` straight to a final
        result; this makes the intermediate state real and persisted.
        """
        test = self._repo.get_lab_test(test_id)
        if test is None:
            return None
        if test.get("status") in ("passed", "failed"):
            # A finished test is terminal; do not silently reopen it.
            return test
        updated = self._repo.update_lab_test(
            test_id,
            {
                "status": "in_progress",
                "tested_by": actor_ref or test.get("tested_by") or "",
            },
        )
        self._emit(
            event="LAB_STARTED",
            title="Laboratory test started",
            body=f"Testing has started for batch {test.get('batch_id', '')}.",
            organization_id=self._batch_org(str(test.get("batch_id") or "")),
            batch_id=str(test.get("batch_id") or ""),
            recommended_action="The result will be recorded when testing completes.",
        )
        return updated

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
        batch_id = str(test.get("batch_id") or "")
        if status == "passed":
            self._emit(
                event="LAB_PASS",
                title="Laboratory test passed",
                body=f"Batch {batch_id} passed laboratory testing.",
                organization_id=self._batch_org(batch_id),
                batch_id=batch_id,
                recommended_action="A certificate can be issued and the batch processed.",
            )
        else:
            self._emit(
                event="LAB_FAIL",
                title="Laboratory test failed",
                body=(
                    f"Batch {batch_id} failed laboratory testing and is blocked "
                    "from packaging."
                ),
                organization_id=self._batch_org(batch_id),
                severity="critical",
                batch_id=batch_id,
                recommended_action="Review the batch; downstream packaging is blocked.",
            )
        return updated

    # ----------------------------------------------------------------- reads
    def list_labs(self) -> list[dict[str, Any]]:
        """Real laboratory directory for the FPO test-request selector."""
        rows: list[dict[str, Any]] = []
        for org in self._repo.list_organizations():
            org_type = str(org.get("type") or "").lower()
            name = str(org.get("name") or "")
            name_lower = name.lower()
            if any(token in org_type for token in _LAB_TYPE_TOKENS) or any(
                token in name_lower for token in _LAB_NAME_TOKENS
            ):
                rows.append(
                    {
                        "id": str(org.get("id") or ""),
                        "organization_key": str(org.get("organization_key") or ""),
                        "name": name,
                        "type": str(org.get("type") or ""),
                        "state": str(org.get("state") or ""),
                        "district": str(org.get("district") or ""),
                        "status": str(org.get("status") or ""),
                    }
                )
        return rows

    def update_batch_trust_from_tests(self, batch_id: str) -> None:
        tests = self._repo.list_lab_tests(batch_id)
        latest = tests[-1] if tests else None
        if not latest:
            return
        if latest.get("status") == "passed":
            self._repo.update_batch(batch_id, {"trust_tier": "lab_verified"})
        elif latest.get("status") == "failed":
            # A later failed test supersedes an earlier pass. Keep the test and
            # custody history, but never leave the batch advertising stale lab
            # verification. If it has already moved downstream, reject the
            # canonical batch while genealogy/history remain intact.
            pending: list[str] = [batch_id]
            visited: set[str] = set()
            while pending:
                current = pending.pop()
                if current in visited:
                    continue
                visited.add(current)
                current_batch = self._repo.get_batch(current) or {}
                current_updates: dict[str, Any] = {"trust_tier": "self_declared"}
                if current_batch.get("status") in {
                    "processing", "packaged", "in_qa", "distribution", "retail"
                }:
                    current_updates["status"] = "rejected"
                self._repo.update_batch(current, current_updates)
                pending.extend(
                    str(rel.get("child_batch_id") or "")
                    for rel in self._repo.list_batch_relations(
                        current, direction="children"
                    )
                    if rel.get("child_batch_id")
                )

    def for_batch(self, batch_id: str) -> list[dict[str, Any]]:
        return self._repo.list_lab_tests(batch_id)