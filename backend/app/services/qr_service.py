"""QR package identity and suspicious reuse detection.

A printed package code is the thing a consumer actually holds, so it needs its
own identity in the system rather than being inferred from a batch code. That
identity is what makes a duplicated print detectable.

Every signal here is computed from rows that already exist in `packages` and
`qr_scans`. Nothing is guessed, and a clean first scan is reported as clean —
the detector never manufactures a suspicion to look busy.

Signals, in the order they are checked:

  UNKNOWN_CODE      the code was never issued by this platform
  DUPLICATE_PRINT   the code resolves to a package that another scan already
                    consumed, i.e. two physical labels claim one identity
  REUSE_BY_OTHER_ORG  a later scan comes from a different organization than the
                    one that scanned it first — the classic cloned-label case
  EXCESSIVE_SCANS   the same code has been scanned more times than the
                    single-issue expectation for one physical package
  RECALLED          the package was explicitly recalled

A scan is SUSPICIOUS when it carries any signal, and the signals are persisted
with the scan so an auditor can always answer "why was this flagged?".
"""
from __future__ import annotations

import secrets
from datetime import datetime, timezone
from typing import Any

from ..db.supabase import Repository

# A single physical label has one legitimate first scan (the retailer's). Further
# scans are only suspicious in combination with the org / issue signals above,
# but the raw count is still surfaced so a burst of scans is visible.
_SUSPICIOUS_SCAN_THRESHOLD = 3


class QrService:
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

    # --------------------------------------------------------------- issuing
    def issue_package(
        self, *, data: dict[str, Any], user: Any
    ) -> dict[str, Any]:
        """Print identity for one package of an existing batch."""
        batch_id = str(data.get("batch_id") or "")
        batch = self._repo.get_batch(batch_id)
        if batch is None:
            raise ValueError("batch not found")
        org_id = str(batch.get("organization_id") or "")
        # The issuer is the owning organization, never a browser-supplied value.
        if user.role not in ("admin", "institution") and user.org_id != org_id:
            raise PermissionError("only the owning organization may issue a package")
        quantity = float(data.get("quantity_kg") or 0)
        if quantity <= 0:
            raise ValueError("quantity_kg must be greater than zero")
        if quantity - float(batch.get("quantity_kg", 0) or 0) > 1e-6:
            raise ValueError("package quantity exceeds the batch quantity")

        client_id = str(data.get("client_id") or "")
        if client_id:
            existing = self._repo.find_by_client_id("packages", client_id)
            if existing:
                return existing

        # A code is only unique per issued row. This check is deliberately NOT a
        # lookup against the generator — a duplicate print is exactly the case
        # the caller must be able to detect by scanning, so auto-generated codes
        # would hide it. An explicitly supplied code that already exists resolves
        # to the package that already owns that identity, which is what makes a
        # re-printed label visible as DUPLICATE_PRINT rather than as two
        # indistinguishable packages.
        code = str(data.get("package_code") or "").strip() or self._mint_code()
        already_issued = self._repo.get_package_by_code(code)
        if already_issued is not None:
            return already_issued
        package = self._repo.create_package(
            {
                "package_code": code,
                "batch_id": batch_id,
                "organization_id": org_id,
                "quantity_kg": quantity,
                "status": "ACTIVE",
                "scan_count": 0,
                "issued_at": datetime.now(timezone.utc),
                "client_id": client_id,
            }
        )
        return package

    @staticmethod
    def _mint_code() -> str:
        """Human-scannable code. Uniqueness is enforced by the unique index."""
        return f"HC-{secrets.token_hex(6).upper()}"

    def list_packages(self, *, user: Any, batch_id: str = "") -> list[dict[str, Any]]:
        if user.role in ("admin", "institution"):
            rows = self._repo.list_packages(batch_id=batch_id)
        else:
            rows = [
                p
                for p in self._repo.list_packages(batch_id=batch_id)
                if str(p.get("organization_id") or "") == str(user.org_id or "")
            ]
        return rows

    def recall_package(self, code: str, *, user: Any) -> dict[str, Any] | None:
        """Recall an issued package so later scans are flagged."""
        package = self._repo.get_package_by_code(code)
        if package is None:
            return None
        if user.role not in ("admin", "institution") and user.org_id != str(
            package.get("organization_id") or ""
        ):
            raise PermissionError("only the issuing organization may recall a package")
        return self._repo.update_package(code, {"status": "RECALLED"})
    def scan(self, code: str, *, user: Any) -> dict[str, Any]:
        """Scan a printed code and return what the platform actually knows.

        The scan is always persisted — including an unknown-code scan, because
        "someone presented a label this platform never issued" is itself the
        most important signal a duplicate-print investigation needs.
        """
        code = str(code or "").strip()
        package = self._repo.get_package_by_code(code)
        now = datetime.now(timezone.utc)
        signals: list[dict[str, Any]] = []
        prior_scans = self._repo.list_qr_scans(package_code=code)

        if package is None:
            signals.append(
                {
                    "code": "UNKNOWN_CODE",
                    "detail": "No package with this code has been issued.",
                }
            )
            scan_row = self._repo.add_qr_scan(
                {
                    "package_code": code,
                    "batch_id": None,
                    "scanner_user_id": str(user.user_id),
                    "scanner_role": str(getattr(user, "role", "") or ""),
                    "organization_id": str(getattr(user, "org_id", "") or ""),
                    "result": "SUSPICIOUS",
                    "signals": signals,
                    "scanned_at": now,
                }
            )
            self._raise_alert(code, signals, batch_id="", user=user)
            return {
                "package": None,
                "result": "SUSPICIOUS",
                "signals": signals,
                "scan": scan_row,
                "prior_scan_count": len(prior_scans),
            }

        org_id = str(getattr(user, "org_id", "") or "")
        first_scan_org = str(package.get("first_scan_org") or "")
        if package.get("status") == "RECALLED":
            signals.append(
                {
                    "code": "RECALLED",
                    "detail": "This package was recalled by its issuer.",
                }
            )
        if first_scan_org:
            if org_id and org_id != first_scan_org:
                signals.append(
                    {
                        "code": "REUSE_BY_OTHER_ORG",
                        "detail": (
                            f"Already scanned by organization {first_scan_org}; "
                            f"this scan came from {org_id}."
                        ),
                    }
                )
            else:
                # Same org scanning its own label again is a duplicate print,
                # not a new sale.
                signals.append(
                    {
                        "code": "DUPLICATE_PRINT",
                        "detail": (
                            "This code was already scanned by the same "
                            "organization; two labels appear to share one identity."
                        ),
                    }
                )
        if len(prior_scans) + 1 > _SUSPICIOUS_SCAN_THRESHOLD:
            signals.append(
                {
                    "code": "EXCESSIVE_SCANS",
                    "detail": (
                        f"{len(prior_scans) + 1} scans recorded for this code, "
                        f"above the expected {_SUSPICIOUS_SCAN_THRESHOLD}."
                    ),
                }
            )
        result = "SUSPICIOUS" if signals else "CLEAR"
        scan_row = self._repo.add_qr_scan(
            {
                "package_code": code,
                "batch_id": package.get("batch_id"),
                "scanner_user_id": str(user.user_id),
                "scanner_role": str(getattr(user, "role", "") or ""),
                "organization_id": org_id,
                "result": result,
                "signals": signals,
                "scanned_at": now,
            }
        )
        updates: dict[str, Any] = {
            "scan_count": int(package.get("scan_count", 0) or 0) + 1
        }
        if not package.get("first_scan_at"):
            updates["first_scan_at"] = now
            updates["first_scan_org"] = org_id
            # Only the first legitimate scan marks the package consumed; a
            # suspicious first scan must not burn the identity.
            if not signals:
                updates["status"] = "SCANNED"
        self._repo.update_package(code, updates)

        if signals:
            self._raise_alert(
                code, signals, batch_id=str(package.get("batch_id") or ""), user=user
            )
        return {
            "package": self._repo.get_package_by_code(code),
            "result": result,
            "signals": signals,
            "scan": scan_row,
            "prior_scan_count": len(prior_scans),
        }

    def _raise_alert(
        self,
        code: str,
        signals: list[dict[str, Any]],
        *,
        batch_id: str,
        user: Any,
    ) -> None:
        """Alert the issuing organization, from the same write as the scan."""
        codes = ", ".join(str(s.get("code")) for s in signals)
        package = self._repo.get_package_by_code(code) or {}
        # Routed to the package's issuing organization, since they own the
        # response to a duplicated label.
        target_org = str(package.get("organization_id") or "")
        self._emit(
            event="QR_SUSPICIOUS",
            title="Suspicious package scan",
            body=(
                f"Package {code} was scanned with signals: {codes}."
                if target_org
                else f"Unissued code {code} was presented for scanning."
            ),
            organization_id=target_org,
            batch_id=batch_id or None,
            severity="critical",
            recommended_action=(
                "Investigate a possible duplicated label and confirm the package "
                "is genuine before releasing honey."
            ),
        )

    def scan_history(self, code: str, *, user: Any) -> list[dict[str, Any]]:
        package = self._repo.get_package_by_code(str(code or ""))
        if package is None:
            return []
        if user.role not in ("admin", "institution") and user.org_id != str(
            package.get("organization_id") or ""
        ):
            raise PermissionError("scan history is not in your scope")
        return self._repo.list_qr_scans(package_code=str(code))

    def suspicious_scans(self, *, user: Any, limit: int = 50) -> list[dict[str, Any]]:
        """Flagged scans across the caller's packages, newest first."""
        rows: list[dict[str, Any]] = []
        for package in self.list_packages(user=user):
            code = str(package.get("package_code"))
            rows.extend(
                s
                for s in self._repo.list_qr_scans(package_code=code, limit=limit)
                if s.get("result") == "SUSPICIOUS"
            )
        rows.sort(key=lambda r: str(r.get("scanned_at", "")), reverse=True)
        return rows[:limit]