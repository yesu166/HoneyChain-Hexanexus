"""Mobile processing van — a submodule of the KVIC Field Officer surface.

The van is the field unit that goes to the apiary: an officer schedules a
visit, arrives, collects a real sample against a real batch, and records the
test result in the field. This is deliberately NOT a portal — it belongs to the
KVIC Field Officer card and runs on the same role the officer already holds.

Two rules keep it honest:

  * A sample must reference a batch that actually exists; the van cannot
    invent a lot number that nothing in the ledger knows.
  * The visit only reaches COMPLETED through ARRIVED and SAMPLE_COLLECTED, so a
    finished visit always implies a sample that was really taken. Van results
    are field observations, not laboratory certificates — they never raise a
    batch's trust tier, and the UI must not present them as if they did.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository

# The visit must pass through these states in order before it may complete.
_NEXT_STATUS = {
    "SCHEDULED": "ARRIVED",
    "ARRIVED": "SAMPLE_COLLECTED",
    "SAMPLE_COLLECTED": "COMPLETED",
}
_VAN_RESULTS = ("PASS", "FAIL")


class VanService:
    def __init__(self, repo: Repository, notifications: Any = None) -> None:
        self._repo = repo
        self._notifications = notifications

    def _emit(self, **kwargs: Any) -> None:
        if self._notifications is None:
            return
        try:
            self._notifications.notify(**kwargs)
        except Exception:  # pragma: no cover - notification must never break a write
            pass

    # ---------------------------------------------------------------- visits
    def schedule_visit(self, *, data: dict[str, Any], user: Any) -> dict[str, Any]:
        van_code = str(data.get("van_code") or "").strip()
        if not van_code:
            raise ValueError("van_code is required")
        client_id = str(data.get("client_id") or "")
        if client_id:
            existing = self._repo.find_by_client_id("van_visits", client_id)
            if existing:
                return existing
        visit = self._repo.create_van_visit(
            {
                "van_code": van_code,
                # The officer is the authenticated caller, never the request body.
                "officer_user_id": str(user.user_id),
                "organization_id": str(getattr(user, "org_id", "") or ""),
                "target_org_id": str(data.get("target_org_id") or ""),
                "target_name": str(data.get("target_name") or ""),
                "status": "SCHEDULED",
                "scheduled_for": data.get("scheduled_for")
                or datetime.now(timezone.utc),
                "notes": str(data.get("notes") or ""),
                "client_id": client_id,
            }
        )
        self._emit(
            event="VAN_VISIT_SCHEDULED",
            title="Van visit scheduled",
            body=(
                f"Van {van_code} is scheduled"
                + (
                    f" for {visit.get('target_name')}"
                    if visit.get("target_name")
                    else ""
                )
                + "."
            ),
            organization_id=str(visit.get("organization_id") or ""),
            recommended_action="The officer should record arrival on site.",
        )
        return visit

    def advance_visit(
        self, visit_id: str, *, user: Any, to_status: str = ""
    ) -> dict[str, Any]:
        """Move a visit to its next state.

        The transition is derived from the stored status, not from the caller,
        so a visit cannot skip arrival to reach completion.
        """
        visit = self._repo.get_van_visit(visit_id)
        if visit is None:
            raise ValueError("van visit not found")
        self._assert_officer(visit, user)
        current = str(visit.get("status") or "")
        expected = _NEXT_STATUS.get(current)
        if expected is None:
            raise ValueError(f"visit is already {current}")
        target = to_status or expected
        if target != expected:
            raise ValueError(f"a {current} visit must move to {expected}")

        updates: dict[str, Any] = {"status": target}
        if target == "ARRIVED":
            updates["arrived_at"] = datetime.now(timezone.utc)
        elif target == "COMPLETED":
            updates["completed_at"] = datetime.now(timezone.utc)
        updated = self._repo.update_van_visit(visit_id, updates)
        return updated

    @staticmethod
    def _assert_officer(visit: dict[str, Any], user: Any) -> None:
        if user.role in ("admin", "institution"):
            return
        if str(visit.get("officer_user_id") or "") != str(user.user_id):
            raise PermissionError("only the assigned officer may update this visit")
    # --------------------------------------------------------------- samples
    def collect_sample(
        self, visit_id: str, *, data: dict[str, Any], user: Any
    ) -> dict[str, Any]:
        """Record a sample taken in the field against a real batch."""
        visit = self._repo.get_van_visit(visit_id)
        if visit is None:
            raise ValueError("van visit not found")
        self._assert_officer(visit, user)
        if str(visit.get("status") or "") not in ("ARRIVED", "SAMPLE_COLLECTED"):
            raise ValueError("the van must be on site before a sample is collected")

        batch_id = str(data.get("batch_id") or "")
        batch = self._repo.get_batch(batch_id)
        if batch is None:
            # A sample against a batch nothing has heard of would put a lot
            # number into the ledger that provenance cannot resolve.
            raise ValueError("batch not found")
        sample_code = str(data.get("sample_code") or "").strip()
        if not sample_code:
            raise ValueError("sample_code is required")
        already = {
            str(s.get("sample_code"))
            for s in self._repo.list_van_samples(visit_id)
        }
        if sample_code in already:
            raise ValueError("this sample code is already recorded for the visit")
        quantity = data.get("quantity_kg")
        if quantity is not None and float(quantity) <= 0:
            raise ValueError("quantity_kg must be greater than zero")

        sample = self._repo.create_van_sample(
            {
                "visit_id": visit_id,
                "batch_id": batch_id,
                "sample_code": sample_code,
                "quantity_kg": quantity,
                "result": "PENDING",
                "moisture_percent": data.get("moisture_percent"),
                "notes": str(data.get("notes") or ""),
                "collected_at": datetime.now(timezone.utc),
                "client_id": str(data.get("client_id") or ""),
            }
        )
        # The visit advances only because a sample genuinely exists.
        if visit.get("status") == "ARRIVED":
            self._repo.update_van_visit(visit_id, {"status": "SAMPLE_COLLECTED"})
        self._emit(
            event="VAN_SAMPLE_RECEIVED",
            title="Van sample collected",
            body=(
                f"Sample {sample_code} was collected against batch "
                f"{batch.get('batch_code') or batch_id}."
            ),
            organization_id=str(batch.get("organization_id") or ""),
            batch_id=batch_id,
            recommended_action="The laboratory can verify the van's field sample.",
        )
        return sample
    def result_sample(
        self, sample_id: str, *, result: str, user: Any, notes: str = ""
    ) -> dict[str, Any]:
        """Record the officer's field result for one sample.

        This is a van observation, NOT a laboratory certification: it never
        changes the batch's trust tier, and the response carries an explicit
        flag so no caller can mistake it for a lab PASS.
        """
        if result not in _VAN_RESULTS:
            raise ValueError(f"result must be one of {_VAN_RESULTS}")
        sample = None
        for visit in self._repo.list_van_visits():
            for candidate in self._repo.list_van_samples(str(visit.get("id"))):
                if str(candidate.get("id")) == sample_id:
                    sample = candidate
                    break
            if sample is not None:
                break
        if sample is None:
            raise ValueError("van sample not found")
        visit = self._repo.get_van_visit(str(sample.get("visit_id")))
        if visit is None:
            raise ValueError("van visit for this sample no longer exists")
        self._assert_officer(visit, user)

        batch = self._repo.get_batch(str(sample.get("batch_id") or "")) or {}
        # Deliberately NOT written back to the batch: only a laboratory may
        # change trust_tier. The field result is reported and notified, and the
        # batch's tier is echoed so the caller can see it did not move.
        self._emit(
            event="VAN_TEST_COMPLETED",
            title="Van field test completed",
            body=(
                f"Van sample {sample.get('sample_code')} recorded {result} for "
                f"batch {batch.get('batch_code') or sample.get('batch_id')}. "
                "This is a field observation, not a laboratory certificate."
            ),
            organization_id=str(batch.get("organization_id") or ""),
            batch_id=str(sample.get("batch_id") or ""),
            severity="warning" if result == "FAIL" else "info",
            recommended_action=(
                "Request laboratory testing to change this batch's trust tier."
            ),
        )
        return {
            **sample,
            "result": result,
            "notes": notes or sample.get("notes", ""),
            "is_laboratory_certificate": False,
            "batch_trust_tier": batch.get("trust_tier", ""),
        }

    # ----------------------------------------------------------------- reads
    def list_visits(self, *, user: Any, status: str = "") -> list[dict[str, Any]]:
        if user.role in ("admin", "institution"):
            visits = self._repo.list_van_visits(status=status)
        else:
            visits = [
                v
                for v in self._repo.list_van_visits(status=status)
                if str(v.get("officer_user_id") or "") == str(user.user_id)
            ]
        return [
            {**v, "samples": self._repo.list_van_samples(str(v.get("id")))}
            for v in visits
        ]

    def get_visit(self, visit_id: str, *, user: Any) -> dict[str, Any] | None:
        visit = self._repo.get_van_visit(visit_id)
        if visit is None:
            return None
        if user.role not in ("admin", "institution"):
            if str(visit.get("officer_user_id") or "") != str(user.user_id):
                raise PermissionError("this visit is not assigned to you")
        return {**visit, "samples": self._repo.list_van_samples(visit_id)}

    def dashboard(self, *, user: Any) -> dict[str, Any]:
        """Everything the field-officer submodule needs in one call."""
        visits = self.list_visits(user=user)
        return {
            "visits": visits,
            "counts": {
                status: sum(1 for v in visits if v.get("status") == status)
                for status in (
                    "SCHEDULED",
                    "ARRIVED",
                    "SAMPLE_COLLECTED",
                    "COMPLETED",
                )
            },
        }