"""Repository boundaries for the HoneyChain backend.

The system of record is Supabase PostgreSQL; [SupabaseRepository] talks to it
with the server-side service-role key. [InMemoryRepository] is the local/
development/test implementation used when no credentials are configured — it
keeps every pytest green without a live cloud project.

All repository methods exchange plain dicts; schemas/services convert.
"""
from __future__ import annotations

import secrets
import uuid
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from typing import Any

from ..core.config import get_settings
from ..core.logging import get_logger

log = get_logger(__name__)


def new_id() -> str:
    return str(uuid.uuid4())


class Repository(ABC):
    """Persistence boundary used by the services layer."""

    # ---- users -----------------------------------------------------------
    @abstractmethod
    def create_user(
        self,
        *,
        email: str,
        name: str,
        phone: str,
        role: str,
        org_id: str,
        password_hash: str,
    ) -> dict[str, Any]: ...

    @abstractmethod
    def get_user_by_email(self, email: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def get_user_by_phone(self, phone: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def get_user(self, user_id: str) -> dict[str, Any] | None: ...

    # ---- organizations ----------------------------------------------------
    @abstractmethod
    def ensure_organization(self, org: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def get_organization(self, org_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_organizations(self) -> list[dict[str, Any]]: ...

    @abstractmethod
    def create_organization(self, org: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def update_organization_status(self, org_key: str, status: str) -> dict[str, Any] | None: ...

    # ---- organization onboarding invites -----------------------------------
    @abstractmethod
    def create_organization_invite(
        self,
        *,
        organization_key: str,
        email: str,
        role: str = "fpo",
        invited_by: str = "",
    ) -> dict[str, Any]: ...

    @abstractmethod
    def get_organization_invite(self, token: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def mark_organization_invite_used(self, token: str, user_id: str) -> None: ...

    @abstractmethod
    def revoke_organization_invite(self, invite_id: str) -> dict[str, Any] | None: ...

    # ---- membership / account governance -----------------------------------
    @abstractmethod
    def set_user_org(self, user_id: str, org_id: str) -> None: ...

    @abstractmethod
    def set_user_status(self, user_id: str, status: str) -> None: ...

    @abstractmethod
    def set_beekeeper_org(self, beekeeper_id: str, organization_id: str | None) -> None: ...

    @abstractmethod
    def list_users(self, *, role: str | None = None, org_id: str | None = None) -> list[dict[str, Any]]: ...

    # ---- user roles (multi-role membership) ---------------------------------
    @abstractmethod
    def get_user_roles(self, user_id: str) -> list[str]: ...

    @abstractmethod
    def set_user_roles(self, user_id: str, roles: list[str]) -> None: ...

    @abstractmethod
    def add_user_role(self, user_id: str, role: str) -> None: ...

    @abstractmethod
    def remove_user_role(self, user_id: str, role: str) -> None: ...

    # ---- governance audit ----------------------------------------------------
    @abstractmethod
    def append_audit_event(
        self,
        *,
        action: str,
        actor_user_id: str,
        actor_role: str,
        target_type: str,
        target_key: str,
        detail: dict[str, Any] | None = None,
    ) -> None: ...

    @abstractmethod
    def list_audit_events(self, limit: int = 100) -> list[dict[str, Any]]: ...

    # ---- beekeepers -------------------------------------------------------
    @abstractmethod
    def ensure_beekeeper(self, beekeeper: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def get_beekeeper(self, beekeeper_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_beekeepers(self, org_id: str | None = None) -> list[dict[str, Any]]: ...

    # ---- hives ------------------------------------------------------------
    @abstractmethod
    def create_hive(
        self, hive: dict[str, Any], *, client_id: str = ""
    ) -> dict[str, Any]: ...

    @abstractmethod
    def get_hive(self, hive_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_hives(self, beekeeper_id: str | None) -> list[dict[str, Any]]: ...

    @abstractmethod
    def update_hive(self, hive_id: str, updates: dict[str, Any]) -> dict[str, Any] | None: ...

    # ---- readings ---------------------------------------------------------
    @abstractmethod
    def add_reading(self, reading: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def list_readings(self, hive_id: str, limit: int = 100) -> list[dict[str, Any]]: ...

    # ---- harvests ---------------------------------------------------------
    @abstractmethod
    def create_harvest(
        self, harvest: dict[str, Any], *, client_id: str = ""
    ) -> dict[str, Any]: ...

    @abstractmethod
    def get_harvest(self, harvest_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_harvests(
        self, beekeeper_id: str | None, org_id: str = ""
    ) -> list[dict[str, Any]]: ...

    # ---- inspections & treatments (Ask My Bee) --------------------------------
    @abstractmethod
    def create_inspection(
        self, inspection: dict[str, Any], *, client_id: str = ""
    ) -> dict[str, Any]: ...

    @abstractmethod
    def get_inspection(self, inspection_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_inspections(
        self,
        beekeeper_id: str | None,
        hive_id: str = "",
        org_id: str = "",
    ) -> list[dict[str, Any]]: ...

    @abstractmethod
    def create_treatment(
        self, treatment: dict[str, Any], *, client_id: str = ""
    ) -> dict[str, Any]: ...

    @abstractmethod
    def get_treatment(self, treatment_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_treatments(
        self,
        beekeeper_id: str | None,
        hive_id: str = "",
        org_id: str = "",
    ) -> list[dict[str, Any]]: ...

    # ---- batches ------------------------------------------------------------
    @abstractmethod
    def create_batch(
        self, batch: dict[str, Any], *, client_id: str = ""
    ) -> dict[str, Any]: ...

    @abstractmethod
    def get_batch(self, batch_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def get_batch_by_code(self, code: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_batches(
        self, org_id: str, beekeeper_id: str = ""
    ) -> list[dict[str, Any]]: ...

    @abstractmethod
    def update_batch(
        self, batch_id: str, updates: dict[str, Any]
    ) -> dict[str, Any] | None: ...

    @abstractmethod
    def link_batch_harvest(
        self, batch_id: str, harvest_id: str, quantity_kg: float
    ) -> None: ...

    @abstractmethod
    def list_batch_harvests(self, batch_id: str) -> list[dict[str, Any]]: ...

    @abstractmethod
    def list_batch_harvests_by_harvest(self, harvest_id: str) -> list[dict[str, Any]]: ...

    # ---- genealogy ----------------------------------------------------------
    @abstractmethod
    def add_batch_relation(self, relation: dict[str, Any]) -> None: ...

    @abstractmethod
    def list_batch_relations(
        self, batch_id: str, direction: str = "both"
    ) -> list[dict[str, Any]]: ...

    # ---- lab ----------------------------------------------------------------
    @abstractmethod
    def create_lab_test(self, test: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def get_lab_test(self, test_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def update_lab_test(
        self, test_id: str, updates: dict[str, Any]
    ) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_lab_tests(self, batch_id: str) -> list[dict[str, Any]]: ...

    @abstractmethod
    def list_lab_tests_for_batches(self, batch_ids: list[str]) -> list[dict[str, Any]]: ...

    @abstractmethod
    def list_lab_queue(self, lab_id: str) -> list[dict[str, Any]]: ...

    # ---- custody -------------------------------------------------------------
    @abstractmethod
    def add_custody_event(self, event: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def list_custody_events(self, batch_id: str) -> list[dict[str, Any]]: ...

    # ---- blockchain anchors ----------------------------------------------------
    @abstractmethod
    def add_anchor(self, anchor: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def get_anchor(self, batch_id: str) -> dict[str, Any] | None: ...

    # ---- passports ---------------------------------------------------------------
    @abstractmethod
    def save_passport(self, passport: dict[str, Any]) -> None: ...

    @abstractmethod
    def get_passport(self, subject_code: str) -> dict[str, Any] | None: ...

    # ---- idempotency -------------------------------------------------------------
    @abstractmethod
    def find_by_client_id(self, table: str, client_id: str) -> dict[str, Any] | None: ...

    # ---- evidence bundles ----------------------------------------------------------
    @abstractmethod
    def add_evidence_bundle(self, bundle: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def get_evidence_bundle(self, bundle_id: str) -> dict[str, Any] | None: ...

    # ---- ledger events ----------------------------------------------------------------
    @abstractmethod
    def add_ledger_event(self, event: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def list_ledger_events(self, chain_id: str) -> list[dict[str, Any]]: ...

    # ---- lab certificates ---------------------------------------------------------------
    @abstractmethod
    def add_certificate(self, certificate: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def get_certificate(self, certificate_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_certificates(self, batch_id: str) -> list[dict[str, Any]]: ...

    @abstractmethod
    def list_certificates_for_batches(self, batch_ids: list[str]) -> list[dict[str, Any]]: ...

    @abstractmethod
    def revoke_certificate(
        self, certificate_id: str, *, revoked_at: str, reason: str
    ) -> dict[str, Any] | None: ...

    # ---- IoT devices ---------------------------------------------------------
    @abstractmethod
    def create_iot_device(self, device: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def get_iot_device(self, device_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_iot_devices(self, organization_id: str = "") -> list[dict[str, Any]]: ...

    @abstractmethod
    def update_iot_device(
        self, device_id: str, updates: dict[str, Any]
    ) -> dict[str, Any] | None: ...

    # ---- telemetry -------------------------------------------------------------
    @abstractmethod
    def add_telemetry_event(self, event: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def get_telemetry_event(self, event_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_telemetry_events(
        self, device_id: str, limit: int = 20, since: str = ""
    ) -> list[dict[str, Any]]: ...

    @abstractmethod
    def list_telemetry_events_for_devices(self, device_ids: list[str], limit: int = 10000) -> list[dict[str, Any]]: ...

    @abstractmethod
    def telemetry_events_for_hive(
        self, hive_id: str, limit: int = 50
    ) -> list[dict[str, Any]]: ...

    # ---- notifications ---------------------------------------------------------
    @abstractmethod
    def add_notification(self, notification: dict[str, Any]) -> dict[str, Any]: ...

    @abstractmethod
    def get_notification(self, notification_id: str) -> dict[str, Any] | None: ...

    @abstractmethod
    def list_notifications(self, org_id: str = "", hive_id: str = "") -> list[dict[str, Any]]: ...

    @abstractmethod
    def mark_notification_read(
        self, notification_id: str
    ) -> dict[str, Any] | None: ...


class InMemoryRepository(Repository):
    """Local dict-backed repository for development and tests.

    Deterministic and dependency-free; intentionally small.
    """

    def __init__(self, seed: dict[str, list[dict[str, Any]]] | None = None) -> None:
        data: dict[str, list[dict[str, Any]]] = {
            "users": [],
            "organizations": [],
            "organization_invites": [],
            "audit_events": [],
            "beekeepers": [],
            "hives": [],
            "readings": [],
            "harvests": [],
            "inspections": [],
            "treatments": [],
            "batch_harvests": [],
            "batches": [],
            "relations": [],
            "lab_tests": [],
            "custody": [],
            "anchors": [],
            "passports": [],
            "evidence_bundles": [],
            "ledger_events": [],
            "certificates": [],
            "iot_devices": [],
            "telemetry_events": [],
            "notifications": [],
        }
        if seed:
            for key, rows in seed.items():
                data.setdefault(key, []).extend(rows)
        self._data = data

    # -- users --
    def create_user(self, *, email, name, phone, role, org_id, password_hash):
        user = {
            "id": new_id(),
            "email": email,
            "name": name,
            "phone": phone,
            "role": role,
            "org_id": org_id,
            "password_hash": password_hash,
            "status": "ACTIVE",
        }
        self._data["users"].append(user)
        return user

    def get_user_by_email(self, email):
        return next((u for u in self._data["users"] if u["email"] == email), None)

    def get_user_by_phone(self, phone):
        return next((u for u in self._data["users"] if u["phone"] == phone), None)

    def get_user(self, user_id):
        return next((u for u in self._data["users"] if u["id"] == user_id), None)

    # -- organizations --
    def _next_organization_key(self) -> str:
        used: set[int] = set()
        for org in self._data["organizations"]:
            key = org.get("organization_key") or org.get("id") or ""
            if key.startswith("ORG-") and key[4:].isdigit():
                used.add(int(key[4:]))
        n = 1
        while n in used:
            n += 1
        return f"ORG-{n:06d}"

    def ensure_organization(self, org):
        existing = next(
            (o for o in self._data["organizations"] if o["id"] == org.get("id")), None
        )
        if existing:
            existing.update({k: v for k, v in org.items() if v is not None})
            return existing
        row = {"id": org.get("id") or new_id(), **org}
        if not row.get("organization_key"):
            row["organization_key"] = (
                row["id"] if row["id"].startswith("ORG-") else self._next_organization_key()
            )
        self._data["organizations"].append(row)
        return row

    def get_organization(self, org_id):
        match = next(
            (o for o in self._data["organizations"] if o["id"] == org_id), None
        )
        if match is None:
            match = next(
                (o for o in self._data["organizations"] if o.get("organization_key") == org_id),
                None,
            )
        return match

    def list_organizations(self):
        return list(self._data["organizations"])

    def create_organization(self, org):
        org = dict(org)
        rid = org.get("id")
        if rid:
            existing = self.get_organization(rid)
            if existing is not None:
                existing.update({k: v for k, v in org.items() if v is not None})
                return existing
        if not org.get("organization_key"):
            org["organization_key"] = self._next_organization_key()
        if not org.get("id"):
            org["id"] = new_id()
        self._data["organizations"].append(org)
        return dict(org)

    def update_organization_status(self, org_key, status):
        org = self.get_organization(org_key)
        if org is None:
            return None
        org["status"] = status
        return dict(org)

    # -- organization invites --
    def create_organization_invite(self, *, organization_key, email, role="fpo", invited_by=""):
        invite = {
            "id": new_id(),
            "organization_key": organization_key,
            "email": email,
            "role": role,
            "token": secrets.token_urlsafe(24),
            "status": "PENDING",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "invited_by": invited_by or None,
            "invitee_user_id": None,
            "used_at": None,
        }
        self._data["organization_invites"].append(invite)
        return dict(invite)

    def get_organization_invite(self, token):
        return next(
            (i for i in self._data["organization_invites"] if i["token"] == token),
            None,
        )

    def mark_organization_invite_used(self, token, user_id):
        invite = self.get_organization_invite(token)
        if invite is None:
            return
        invite["status"] = "USED"
        invite["invitee_user_id"] = user_id
        invite["used_at"] = datetime.now(timezone.utc).isoformat()

    def revoke_organization_invite(self, invite_id):
        invite = next(
            (i for i in self._data["organization_invites"] if i["id"] == invite_id),
            None,
        )
        if invite is None:
            return None
        invite["status"] = "REVOKED"
        return dict(invite)

    # -- membership / account governance --
    def set_user_org(self, user_id, org_id):
        user = self.get_user(user_id)
        if user is not None:
            user["org_id"] = org_id

    def set_user_status(self, user_id, status):
        user = self.get_user(user_id)
        if user is not None:
            user["status"] = status

    def set_beekeeper_org(self, beekeeper_id, organization_id):
        beekeeper = self.get_beekeeper(beekeeper_id)
        if beekeeper is not None:
            beekeeper["organization_id"] = organization_id

    def list_users(self, *, role=None, org_id=None):
        rows = self._data["users"]
        if role:
            rows = [u for u in rows if u.get("role") == role]
        if org_id:
            rows = [u for u in rows if u.get("org_id") == org_id]
        return [dict(u) for u in rows]

    # -- user roles (multi-role membership) --
    def get_user_roles(self, user_id):
        roles = [r["role"] for r in self._data.get("user_roles", []) if r["user_id"] == user_id]
        # Fallback to primary role from users table for backward compatibility
        user = self.get_user(user_id)
        if user and user.get("role") and user["role"] not in roles:
            roles.insert(0, user["role"])
        return roles

    def set_user_roles(self, user_id, roles):
        self._data.setdefault("user_roles", [])
        # Remove existing roles for this user
        self._data["user_roles"] = [r for r in self._data["user_roles"] if r["user_id"] != user_id]
        # Add new roles
        for role in roles:
            self._data["user_roles"].append({"user_id": user_id, "role": role})

    def add_user_role(self, user_id, role):
        self._data.setdefault("user_roles", [])
        if not any(r["user_id"] == user_id and r["role"] == role for r in self._data["user_roles"]):
            self._data["user_roles"].append({"user_id": user_id, "role": role})

    def remove_user_role(self, user_id, role):
        if "user_roles" in self._data:
            self._data["user_roles"] = [r for r in self._data["user_roles"] if not (r["user_id"] == user_id and r["role"] == role)]

    # -- governance audit --
    def append_audit_event(self, *, action, actor_user_id, actor_role, target_type, target_key, detail=None):
        self._data["audit_events"].append(
            {
                "id": new_id(),
                "actor_user_id": actor_user_id,
                "actor_role": actor_role,
                "action": action,
                "target_type": target_type,
                "target_key": target_key,
                "detail": detail or {},
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
        )

    def list_audit_events(self, limit=100):
        rows = self._data["audit_events"][-limit:]
        return [dict(r) for r in rows]

    # -- beekeepers --
    def ensure_beekeeper(self, beekeeper):
        existing = next(
            (b for b in self._data["beekeepers"] if b["id"] == beekeeper.get("id")), None
        )
        if existing:
            existing.update({k: v for k, v in beekeeper.items() if v is not None})
            return existing
        row = {"id": beekeeper.get("id") or new_id(), **beekeeper}
        self._data["beekeepers"].append(row)
        return row

    def get_beekeeper(self, beekeeper_id):
        return next(
            (b for b in self._data["beekeepers"] if b["id"] == beekeeper_id), None
        )

    def list_beekeepers(self, org_id=None):
        if org_id:
            return [
                b
                for b in self._data["beekeepers"]
                if b.get("organization_id") == org_id or b.get("org_id") == org_id
            ]
        return list(self._data["beekeepers"])

    # -- hives --
    def create_hive(self, hive, *, client_id=""):
        row = {
            "id": new_id(),
            "client_id": client_id,
            **hive,
        }
        self._data["hives"].append(row)
        return row

    def get_hive(self, hive_id):
        return next((h for h in self._data["hives"] if h["id"] == hive_id), None)

    def list_hives(self, beekeeper_id):
        if beekeeper_id is None:
            return list(self._data["hives"])
        return [h for h in self._data["hives"] if h.get("beekeeper_id") == beekeeper_id]

    def update_hive(self, hive_id, updates):
        hive = self.get_hive(hive_id)
        if hive is None:
            return None
        hive.update(updates)
        return hive

    # -- readings --
    def add_reading(self, reading):
        row = {"id": new_id(), **reading}
        self._data["readings"].append(row)
        return row

    def list_readings(self, hive_id, limit=100):
        rows = [r for r in self._data["readings"] if r.get("hive_id") == hive_id]
        rows.sort(key=lambda r: str(r.get("recorded_at", "")), reverse=True)
        return rows[:limit]

    # -- harvests --
    def create_harvest(self, harvest, *, client_id=""):
        row = {"id": new_id(), "client_id": client_id, **harvest}
        self._data["harvests"].append(row)
        return row

    def get_harvest(self, harvest_id):
        return next(
            (h for h in self._data["harvests"] if h["id"] == harvest_id), None
        )

    def list_harvests(self, beekeeper_id, org_id=""):
        if beekeeper_id is None:
            rows = list(self._data["harvests"])
        else:
            rows = [h for h in self._data["harvests"] if h.get("beekeeper_id") == beekeeper_id]
        if org_id:
            scope = {b["id"] for b in self._data["beekeepers"] if b.get("org_id") == org_id}
            rows = [h for h in rows if h.get("beekeeper_id") in scope]
        return sorted(rows, key=lambda r: str(r.get("harvested_at", "")), reverse=True)

    # -- inspections & treatments (Ask My Bee) --
    def create_inspection(self, inspection, *, client_id=""):
        row = {"id": new_id(), "client_id": client_id, **inspection}
        self._data["inspections"].append(row)
        return row

    def get_inspection(self, inspection_id):
        return next(
            (r for r in self._data["inspections"] if r["id"] == inspection_id), None
        )

    def list_inspections(self, beekeeper_id, hive_id="", org_id=""):
        rows = list(self._data["inspections"])
        if beekeeper_id is not None:
            rows = [r for r in rows if r.get("beekeeper_id") == beekeeper_id]
        if hive_id:
            rows = [r for r in rows if r.get("hive_id") == hive_id]
        if org_id:
            scope = {b["id"] for b in self._data["beekeepers"] if b.get("org_id") == org_id}
            rows = [r for r in rows if r.get("beekeeper_id") in scope]
        return sorted(rows, key=lambda r: str(r.get("inspected_at", "")), reverse=True)

    def create_treatment(self, treatment, *, client_id=""):
        row = {"id": new_id(), "client_id": client_id, **treatment}
        self._data["treatments"].append(row)
        return row

    def get_treatment(self, treatment_id):
        return next(
            (r for r in self._data["treatments"] if r["id"] == treatment_id), None
        )

    def list_treatments(self, beekeeper_id, hive_id="", org_id=""):
        rows = list(self._data["treatments"])
        if beekeeper_id is not None:
            rows = [r for r in rows if r.get("beekeeper_id") == beekeeper_id]
        if hive_id:
            rows = [r for r in rows if r.get("hive_id") == hive_id]
        if org_id:
            scope = {b["id"] for b in self._data["beekeepers"] if b.get("org_id") == org_id}
            rows = [r for r in rows if r.get("beekeeper_id") in scope]
        return sorted(rows, key=lambda r: str(r.get("treated_at", "")), reverse=True)

    # -- batches --
    def create_batch(self, batch, *, client_id=""):
        row = {"id": new_id(), "client_id": client_id, **batch}
        self._data["batches"].append(row)
        return row

    def get_batch(self, batch_id):
        return next((b for b in self._data["batches"] if b["id"] == batch_id), None)

    def get_batch_by_code(self, code):
        return next(
            (b for b in self._data["batches"] if b.get("batch_code") == code), None
        )

    def list_batches(self, org_id, beekeeper_id=""):
        def in_scope(b):
            if b.get("organization_id") == org_id:
                return True
            if beekeeper_id and b.get("beekeeper_id") == beekeeper_id:
                return True
            return False

        rows = [b for b in self._data["batches"] if in_scope(b)]
        return sorted(rows, key=lambda r: str(r.get("created_at", "")), reverse=True)

    def update_batch(self, batch_id, updates):
        batch = self.get_batch(batch_id)
        if batch is None:
            return None
        batch.update(updates)
        return batch

    def link_batch_harvest(self, batch_id, harvest_id, quantity_kg):
        self._data["batch_harvests"].append(
            {
                "batch_id": batch_id,
                "harvest_id": harvest_id,
                "quantity_kg": quantity_kg,
            }
        )

    def list_batch_harvests(self, batch_id):
        return [
            l for l in self._data["batch_harvests"] if l["batch_id"] == batch_id
        ]

    def list_batch_harvests_by_harvest(self, harvest_id):
        return [
            l for l in self._data["batch_harvests"] if l["harvest_id"] == harvest_id
        ]

    # -- genealogy --
    def add_batch_relation(self, relation):
        self._data["relations"].append(relation)

    def list_batch_relations(self, batch_id, direction="both"):
        rows = []
        for r in self._data["relations"]:
            if direction in ("parents", "both") and r.get("child_batch_id") == batch_id:
                rows.append(r)
            if direction in ("children", "both") and r.get("parent_batch_id") == batch_id:
                rows.append(r)
        return rows

    # -- lab --
    def create_lab_test(self, test):
        row = {"id": new_id(), **test}
        self._data["lab_tests"].append(row)
        return row

    def get_lab_test(self, test_id):
        return next(
            (t for t in self._data["lab_tests"] if t["id"] == test_id), None
        )

    def update_lab_test(self, test_id, updates):
        test = self.get_lab_test(test_id)
        if test is None:
            return None
        test.update(updates)
        return test

    def list_lab_tests(self, batch_id):
        return [t for t in self._data["lab_tests"] if t["batch_id"] == batch_id]

    def list_lab_tests_for_batches(self, batch_ids: list[str]):
        if not batch_ids:
            return []
        batch_id_set = set(batch_ids)
        return [t for t in self._data["lab_tests"] if t["batch_id"] in batch_id_set]

    def list_lab_queue(self, lab_id):
        return [
            t
            for t in self._data["lab_tests"]
            if t.get("lab_id") == lab_id and t.get("status") == "requested"
        ]

    # -- custody --
    def add_custody_event(self, event):
        row = {"id": new_id(), **event}
        self._data["custody"].append(row)
        return row

    def list_custody_events(self, batch_id):
        rows = [c for c in self._data["custody"] if c["batch_id"] == batch_id]
        return sorted(rows, key=lambda r: str(r.get("event_at", "")))

    # -- anchors --
    def add_anchor(self, anchor):
        row = {"id": new_id(), **anchor}
        self._data["anchors"].append(row)
        return row

    def get_anchor(self, batch_id):
        return next(
            (a for a in self._data["anchors"] if a["batch_id"] == batch_id), None
        )

    # -- passports --
    def save_passport(self, passport):
        self._data["passports"].append(passport)

    def get_passport(self, subject_code):
        return next(
            (p for p in self._data["passports"] if p["subject_code"] == subject_code),
            None,
        )

    # -- idempotency --
    def find_by_client_id(self, table, client_id):
        column = "client_id"
        rows = self._data.get(table, [])
        return next(
            (r for r in rows if r.get(column) == client_id), None
        )

    # -- evidence bundles --
    def add_evidence_bundle(self, bundle):
        row = {"id": bundle.get("bundle_id") or new_id(), "bundle_id": bundle.get("bundle_id"), **bundle}
        self._data["evidence_bundles"].append(row)
        return row

    def get_evidence_bundle(self, bundle_id):
        return next(
            (b for b in self._data["evidence_bundles"] if b.get("bundle_id") == bundle_id),
            None,
        )

    # -- ledger events --
    def add_ledger_event(self, event):
        row = {"id": new_id(), **event}
        self._data["ledger_events"].append(row)
        return row

    def list_ledger_events(self, chain_id):
        return [
            e for e in self._data["ledger_events"] if e.get("chain_id") == chain_id
        ]

    # -- certificates --
    def add_certificate(self, certificate):
        row = {"id": new_id(), **certificate}
        self._data["certificates"].append(row)
        return row

    def get_certificate(self, certificate_id):
        return next(
            (c for c in self._data["certificates"] if c.get("certificate_id") == certificate_id),
            None,
        )

    def list_certificates(self, batch_id):
        return [
            c for c in self._data["certificates"] if c.get("batch_id") == batch_id
        ]

    def list_certificates_for_batches(self, batch_ids: list[str]):
        if not batch_ids:
            return []
        batch_id_set = set(batch_ids)
        return [c for c in self._data["certificates"] if c.get("batch_id") in batch_id_set]

    def revoke_certificate(self, certificate_id, *, revoked_at, reason):
        cert = self.get_certificate(certificate_id)
        if cert is None:
            return None
        cert.update(
            {"status": "revoked", "revoked_at": revoked_at, "revocation_reason": reason}
        )
        return cert

    # -- IoT devices --
    def create_iot_device(self, device):
        row = {"id": new_id(), "device_id": device.get("device_id") or new_id(), **device}
        self._data["iot_devices"].append(row)
        return row

    def get_iot_device(self, device_id):
        return next(
            (d for d in self._data["iot_devices"] if d.get("device_id") == device_id),
            None,
        )

    def list_iot_devices(self, organization_id=""):
        if organization_id:
            return [
                d
                for d in self._data["iot_devices"]
                if d.get("organization_id") == organization_id
            ]
        return list(self._data["iot_devices"])

    def update_iot_device(self, device_id, updates):
        device = self.get_iot_device(device_id)
        if device is None:
            return None
        device.update(updates)
        return device

    # -- telemetry --
    def add_telemetry_event(self, event):
        row = {"id": new_id(), **event}
        self._data["telemetry_events"].append(row)
        return row

    def get_telemetry_event(self, event_id):
        return next(
            (t for t in self._data["telemetry_events"] if t.get("event_id") == event_id),
            None,
        )

    def list_telemetry_events(self, device_id, limit=20, since=""):
        rows = [
            t for t in self._data["telemetry_events"] if t.get("device_id") == device_id
        ]
        if since:
            rows = [t for t in rows if str(t.get("timestamp", "")) >= since]
        rows.sort(key=lambda r: str(r.get("timestamp", "")), reverse=True)
        return rows[:limit]

    def list_telemetry_events_for_devices(self, device_ids: list[str], limit: int = 10000):
        if not device_ids:
            return []
        device_id_set = set(device_ids)
        rows = [
            t for t in self._data["telemetry_events"] if t.get("device_id") in device_id_set
        ]
        rows.sort(key=lambda r: str(r.get("timestamp", "")), reverse=True)
        return rows[:limit]

    def telemetry_events_for_hive(self, hive_id, limit=50):
        rows = [
            t for t in self._data["telemetry_events"] if t.get("hive_id") == hive_id
        ]
        rows.sort(key=lambda r: str(r.get("timestamp", "")), reverse=True)
        return rows[:limit]

    # -- notifications --
    def add_notification(self, notification):
        row = {**notification, "id": new_id()}
        if not row.get("notification_id"):
            row["notification_id"] = new_id()
        self._data["notifications"].append(row)
        return row

    def list_notifications(self, org_id="", hive_id=""):
        if org_id:
            return [
                n
                for n in self._data["notifications"]
                if n.get("organization_id") == org_id
            ]
        if hive_id:
            return [n for n in self._data["notifications"] if n.get("hive_id") == hive_id]
        return list(self._data["notifications"])

    def mark_notification_read(self, notification_id):
        note = next(
            (
                n
                for n in self._data["notifications"]
                if n.get("notification_id") == notification_id
            ),
            None,
        )
        if note is None:
            return None
        note["read"] = True
        return note

    def get_notification(self, notification_id):
        return next(
            (
                n
                for n in self._data["notifications"]
                if n.get("notification_id") == notification_id
            ),
            None,
        )


class SupabaseRepository(Repository):
    """PostgreSQL via Supabase's service-role client.

    The supabase client is imported lazily so the backend still boots (and its
    tests run) where the SDK is not installed. All writes are upserts keyed by
    the stable `client_id` where the schema provides one, keeping retries
    idempotent.

    The backend's domain rows and the cloud columns differ in a few places
    (custody actions/actors, batch-harvest links, genealogy relation types,
    certificate timestamps, beekeeper org keys, datetime serialization). This
    class translates on the write and read paths only; services keep their
    existing dict shapes.
    """

    TABLE_MAP = {
        "users": "users",
        "organizations": "organizations",
        "organization_invites": "organization_invites",
        "platform_audit": "platform_audit",
        "beekeepers": "beekeepers",
        "hives": "hives",
        "readings": "hive_readings",
        "harvests": "harvest_events",
        "inspections": "hive_inspections",
        "treatments": "hive_treatments",
        "batch_harvests": "batch_harvest_links",
        "batches": "batches",
        "relations": "batch_genealogy",
        "lab_tests": "lab_tests",
        "custody": "custody_events",
        "anchors": "blockchain_anchors",
        "passports": "passports",
        "evidence_bundles": "evidence_bundles",
        "ledger_events": "ledger_events",
        "certificates": "certificates",
        "iot_devices": "iot_devices",
        "telemetry_events": "telemetry_events",
        "notifications": "notifications",
    }

    # Allowed write columns per table (drop anything the domain adds that the
    # cloud schema does not carry).
    _ORGANIZATION_COLS = (
        "id", "name", "type", "location", "cluster_id", "client_id",
        "organization_key", "status", "country", "state", "district",
        "address", "postal_code", "contact_email", "contact_phone",
        "registration_no",
    )
    _ORGANIZATION_INVITE_COLS = (
        "id", "organization_key", "email", "role", "token", "status",
        "created_at", "used_at", "invited_by", "invitee_user_id",
    )
    _BEEKEEPER_COLS = (
        "id", "profile_id", "organization_id", "name", "phone", "location",
        "madhukranti_id", "is_independent", "producer_id", "client_id",
    )
    _HIVE_COLS = (
        "id", "beekeeper_id", "hive_code", "hive_type", "latitude", "longitude",
        "install_date", "status", "location", "client_id",
    )
    _HARVEST_COLS = (
        "id", "hive_id", "beekeeper_id", "harvested_at", "quantity_kg",
        "honey_type", "location", "notes", "collected", "client_id",
    )
    _INSPECTION_COLS = (
        "id", "hive_id", "beekeeper_id", "inspected_at", "activity_level",
        "queen_seen", "brood_seen", "food_stores", "pests_seen",
        "dead_bees_seen", "hive_condition", "observations", "client_id",
    )
    _TREATMENT_COLS = (
        "id", "hive_id", "beekeeper_id", "treated_at", "treatment_name",
        "active_ingredient", "dosage", "observation", "status", "client_id",
    )
    _BATCH_COLS = (
        "id", "batch_code", "status", "honey_type", "quantity_kg", "beekeeper_id",
        "organization_id", "trust_tier", "origin", "created_at", "client_id",
    )
    _LAB_TEST_COLS = ("batch_id", "lab_id", "status", "requested_note", "requested_at")
    _LEDGER_COLS = (
        "chain_id", "index", "event_type", "entity_ref", "payload", "prev_hash",
        "hash", "ts", "device_id", "fork_of",
    )
    _CERT_COLS = (
        "certificate_id", "batch_id", "lab_id", "certificate_type", "issued_at",
        "valid_until", "content_hash", "issuer_name", "status", "revoked_at",
        "revocation_reason", "anchor",
    )
    _IOT_DEVICE_COLS = (
        "device_id", "device_name", "device_type", "firmware_version",
        "device_status", "assigned_hive_id", "assigned_apiary_id",
        "organization_id", "device_public_key_pem", "device_private_key_pem",
        "created_at", "sequence", "event_count", "battery_percent",
        "signal_strength", "mode", "is_simulated", "interval_seconds",
        "configuration",
    )
    _IOT_DEVICE_UPDATE_COLS = (
        "device_status", "device_name", "firmware_version", "assigned_hive_id",
        "assigned_apiary_id", "organization_id", "mode", "is_simulated",
        "interval_seconds", "configuration", "sequence", "event_count",
        "battery_percent", "signal_strength",
    )
    _TELEMETRY_COLS = (
        "event_id", "device_id", "sequence", "timestamp", "payload",
        "payload_hash", "previous_event_hash", "signature", "hive_id",
        "organization_id", "is_simulated", "created_at",
    )
    _NOTIFICATION_COLS = (
        "notification_id", "title", "body", "category", "severity", "reason",
        "recommended_action", "source", "hive_id", "batch_id", "device_id",
        "organization_id", "is_simulated", "read", "created_at",
    )

    def __init__(self, url: str, service_role_key: str) -> None:
        self._url = url
        self._service_role_key = service_role_key
        self._client = None

    def _supabase(self):
        if self._client is None:
            from supabase import create_client  # lazy server-side only

            self._client = create_client(self._url, self._service_role_key)
        return self._client

    def _table(self, name: str):
        return self._supabase().table(self.TABLE_MAP[name])

    # -- users --
    def create_user(self, *, email, name, phone, role, org_id, password_hash):
        row = {
            "email": email,
            "name": name,
            "phone": phone,
            "role": role,
            "org_id": org_id,
            "password_hash": password_hash,
        }
        data = self._table("users").insert(row).execute().data
        user = data[0]
        self._provision_beekeeper(user)
        return user

    def get_user_by_email(self, email):
        user = self._get_by("users", "email", email)
        self._provision_beekeeper(user)
        return user

    def get_user_by_phone(self, phone):
        user = self._get_by("users", "phone", phone)
        self._provision_beekeeper(user)
        return user

    def get_user(self, user_id):
        user = self._get_by("users", "id", user_id)
        self._provision_beekeeper(user)
        return user

    def _provision_beekeeper(self, user):
        """Mirror a beekeeper-rôle user into `beekeepers` so the cloud's FK
        graph (hives/harvests/batches.beekeeper_id -> beekeepers.id) resolves.
        The backend's identity is the `users` row; the mirror row reuses its
        uuid so entity writes stay valid. Independent by nature (the backend
        authors the org model in its service layer)."""
        if not user or user.get("role") != "beekeeper":
            return
        existing = (
            self._table("beekeepers").select("id").eq("id", user["id"])
            .limit(1).execute().data
        )
        if existing:
            return
        self._table("beekeepers").insert(
            {
                "id": user["id"],
                "profile_id": None,
                "organization_id": None,
                "name": user.get("name", ""),
                "phone": user.get("phone", ""),
                "location": None,
                "madhukranti_id": "",
                "is_independent": True,
                "producer_id": user.get("producer_id") or "",
            }
        ).execute()

    # -- organizations / beekeepers --
    def _next_organization_key(self) -> str:
        data = self._supabase().rpc("next_organization_key").execute().data
        if isinstance(data, str):
            return data
        if not data:
            return ""
        first = data[0]
        if isinstance(first, dict):
            return str(
                first.get("next_organization_key")
                or first.get("value")
                or next(
                    (v for k, v in first.items() if not k.startswith("@")),
                    "",
                )
            )
        return str(first)

    def ensure_organization(self, org):
        row = self._clip(org, self._ORGANIZATION_COLS, iso=())
        if row.get("id") and not self._is_uuid(row["id"]):
            row.pop("id")
        return self._upsert("organizations", row, key="client_id")

    @staticmethod
    def _normalize_row(row):
        if not row:
            return row
        return {k: ("" if v is None else v) for k, v in row.items()}

    def get_organization(self, org_id):
        if org_id is None or str(org_id) == "":
            return None
        key = str(org_id)
        if self._is_uuid(key):
            row = self._get_by("organizations", "id", key)
            if row is None:
                row = self._get_by("organizations", "organization_key", key)
            return self._normalize_row(row)
        return self._normalize_row(self._get_by("organizations", "organization_key", key))

    def list_organizations(self):
        return [self._normalize_row(r) for r in self._table("organizations").select("*").execute().data]

    def create_organization(self, org):
        row = self._clip(org, self._ORGANIZATION_COLS, iso=())
        if row.get("id") and not self._is_uuid(row["id"]):
            row.pop("id")
        if not row.get("organization_key"):
            row["organization_key"] = self._next_organization_key()
        # client_id is the app-side idempotency key (partial unique index on
        # NON-NULL values). Platform-created orgs often have none: store NULL
        # — never "" — so the second/third organization can be created
        # without colliding on the same empty-string "unique" value.
        if row.get("client_id") in (None, ""):
            row.pop("client_id", None)
        return self._upsert("organizations", row, key="client_id")

    def update_organization_status(self, org_key, status):
        target = "id" if self._is_uuid(org_key) else "organization_key"
        data = (
            self._table("organizations")
            .update({"status": status})
            .eq(target, org_key)
            .execute()
            .data
        )
        if data:
            return data[0]
        return self.get_organization(org_key)

    # -- organization invites --
    def create_organization_invite(self, *, organization_key, email, role="fpo", invited_by=""):
        row = {
            "organization_key": organization_key,
            "email": email,
            "role": role,
            "token": secrets.token_urlsafe(24),
            "status": "PENDING",
        }
        if invited_by and self._is_uuid(str(invited_by)):
            row["invited_by"] = invited_by
        data = self._table("organization_invites").insert(row).execute().data
        return data[0] if data else row

    def get_organization_invite(self, token):
        return self._get_by("organization_invites", "token", token)

    def mark_organization_invite_used(self, token, user_id):
        self._table("organization_invites").update(
            {
                "status": "USED",
                "invitee_user_id": user_id,
                "used_at": self._iso(datetime.now(timezone.utc)),
            }
        ).eq("token", token).execute()

    def revoke_organization_invite(self, invite_id):
        self._table("organization_invites").update(
            {"status": "REVOKED"}
        ).eq("id", invite_id).execute()
        return self._get_by("organization_invites", "id", invite_id)

    # -- membership / account governance --
    def set_user_org(self, user_id, org_id):
        self._table("users").update({"org_id": org_id}).eq("id", user_id).execute()

    def set_user_status(self, user_id, status):
        self._table("users").update({"status": status}).eq("id", user_id).execute()

    def set_beekeeper_org(self, beekeeper_id, organization_id):
        self._table("beekeepers").update(
            # uuid FK: translate the public org code, or NULL when revoked/unknown
            {"organization_id": self._org_uuid(organization_id)}
        ).eq("id", beekeeper_id).execute()

    def list_users(self, *, role=None, org_id=None):
        q = self._table("users").select("*")
        if role:
            q = q.eq("role", role)
        if org_id:
            q = q.eq("org_id", org_id)
        return q.execute().data

    # -- user roles (multi-role membership) --
    def get_user_roles(self, user_id: str) -> list[str]:
        """Fetch all roles for a user from the user_roles table, with primary role fallback."""
        roles = []
        try:
            roles_data = self._table("user_roles").select("role").eq("user_id", user_id).execute().data
            roles = [r["role"] for r in roles_data] if roles_data else []
        except Exception:
            # Table may not exist in production (migration pending); fall back to primary role
            pass
        # Fallback to primary role from users table for backward compatibility
        user = self.get_user(user_id)
        if user and user.get("role") and user["role"] not in roles:
            roles.insert(0, user["role"])
        return roles

    def set_user_roles(self, user_id: str, roles: list[str]) -> None:
        """Replace all roles for a user."""
        # Delete existing roles
        self._table("user_roles").delete().eq("user_id", user_id).execute()
        # Insert new roles
        if roles:
            rows = [{"user_id": user_id, "role": role} for role in roles]
            self._table("user_roles").insert(rows).execute()

    def add_user_role(self, user_id: str, role: str) -> None:
        """Add a single role to a user (idempotent)."""
        existing = self._table("user_roles").select("role").eq("user_id", user_id).eq("role", role).execute().data
        if not existing:
            self._table("user_roles").insert({"user_id": user_id, "role": role}).execute()

    def remove_user_role(self, user_id: str, role: str) -> None:
        """Remove a single role from a user."""
        self._table("user_roles").delete().eq("user_id", user_id).eq("role", role).execute()

    # -- governance audit --
    def append_audit_event(self, *, action, actor_user_id, actor_role, target_type, target_key, detail=None):
        self._table("platform_audit").insert(
            {
                "actor_user_id": actor_user_id,
                "actor_role": actor_role,
                "action": action,
                "target_type": target_type,
                "target_key": target_key,
                "detail": detail or {},
            }
        ).execute()

    def list_audit_events(self, limit=100):
        return (
            self._table("platform_audit")
            .select("*")
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
            .data
        )

    def ensure_beekeeper(self, beekeeper):
        row = self._clip(beekeeper, self._BEEKEEPER_COLS, iso=())
        # beekeepers.organization_id is a uuid FK. Accept either the public
        # org code (org_id, what users/org membership carry) or an existing
        # uuid, and always store the canonical UUID (None when unknown).
        raw_org = row.get("organization_id") or beekeeper.get("org_id")
        row["organization_id"] = self._org_uuid(raw_org)
        return self._upsert("beekeepers", row, key="id")

    def get_beekeeper(self, beekeeper_id):
        return self._beekeeper(self._get_by("beekeepers", "id", beekeeper_id))

    def list_beekeepers(self, org_id=None):
        q = self._table("beekeepers").select("*")
        if org_id:
            ouuid = self._org_filter_value(org_id)
            if not ouuid:
                return []
            q = q.eq("organization_id", ouuid)
        return [self._beekeeper(r) for r in q.execute().data]

    @staticmethod
    def _beekeeper(row):
        if row is None:
            return None
        out = {k: ("" if v is None else v) for k, v in row.items()}
        out.setdefault("org_id", out.get("organization_id") or "")
        return out

    @staticmethod
    def _with_client_id(row):
        """Translate a NULL `client_id` to the empty string the application
        contract expects.

        `client_id` is nullable in PostgreSQL by design: the partial unique
        indexes are declared `where client_id is not null`, so NULL is the
        canonical representation of "no client-supplied id" and several rows may
        share it. The domain schemas, however, type `client_id` as `str`
        (`HiveRead`, `HarvestRead`) because `InMemoryRepository` always stores a
        string. Normalizing on read keeps both repositories shaped identically
        without writing '' to a uniquely-indexed column.
        """
        if row is None:
            return None
        if row.get("client_id") is None:
            return {**row, "client_id": ""}
        return row

    @classmethod
    def _with_client_id_list(cls, rows):
        return [cls._with_client_id(r) for r in rows]

    # -- hives --
    def create_hive(self, hive, *, client_id=""):
        if client_id:
            hive["client_id"] = client_id
        row = self._clip(hive, self._HIVE_COLS, iso=())
        return self._with_client_id(self._upsert("hives", row, key="client_id"))

    def get_hive(self, hive_id):
        return self._with_client_id(self._get_by("hives", "id", hive_id))

    def list_hives(self, beekeeper_id):
        q = self._table("hives").select("*")
        if beekeeper_id:
            q = q.eq("beekeeper_id", beekeeper_id)
        return self._with_client_id_list(q.execute().data)

    def update_hive(self, hive_id, updates):
        row = self._clip(updates, self._HIVE_COLS, iso=())
        if row:
            self._table("hives").update(row).eq("id", hive_id).execute()
        return self.get_hive(hive_id)

    # -- readings --
    def add_reading(self, reading):
        row = {
            "hive_id": reading.get("hive_id"),
            "recorded_at": self._iso(reading.get("recorded_at")),
            "temperature": reading.get("temperature_c"),
            "humidity": reading.get("humidity_percent"),
            "weight_kg": reading.get("weight_kg"),
            "source": reading.get("source", "manual"),
        }
        data = self._table("readings").insert(row).execute().data
        return self._reading(data[0])

    def list_readings(self, hive_id, limit=100):
        rows = (
            self._table("readings")
            .select("*")
            .eq("hive_id", hive_id)
            .order("recorded_at", desc=True)
            .limit(limit)
            .execute()
            .data
        )
        return [self._reading(r) for r in rows]

    @staticmethod
    def _reading(row):
        return {
            "id": row.get("id"),
            "hive_id": row.get("hive_id"),
            "temperature_c": row.get("temperature"),
            "humidity_percent": row.get("humidity"),
            "weight_kg": row.get("weight_kg"),
            "recorded_at": row.get("recorded_at"),
            "source": row.get("source"),
        }

    # -- harvests --
    def create_harvest(self, harvest, *, client_id=""):
        if client_id:
            harvest["client_id"] = client_id
        row = self._clip(harvest, self._HARVEST_COLS, iso=("harvested_at",))
        return self._with_client_id(self._upsert("harvests", row, key="client_id"))

    def get_harvest(self, harvest_id):
        return self._with_client_id(self._get_by("harvests", "id", harvest_id))

    def list_harvests(self, beekeeper_id, org_id=""):
        if beekeeper_id:
            rows = (
                self._table("harvests")
                .select("*")
                .eq("beekeeper_id", beekeeper_id)
                .order("harvested_at", desc=True)
                .execute().data
            )
            return self._with_client_id_list(rows)
        q = self._table("harvests").select("*")
        if org_id:
            ouuid = self._org_filter_value(org_id)
            if not ouuid:
                return []
            ids = [
                r["id"]
                for r in self._table("beekeepers").select("id")
                .eq("organization_id", ouuid).execute().data
            ]
            if not ids:
                return []
            q = q.in_("beekeeper_id", ids)
        return self._with_client_id_list(
            q.order("harvested_at", desc=True).execute().data
        )

    # -- inspections & treatments (Ask My Bee) --
    def _scope_beekeepers(self, org_id, rows):
        if not org_id:
            return rows
        ouuid = self._org_filter_value(org_id)
        if not ouuid:
            return []
        ids = [
            r["id"]
            for r in self._table("beekeepers").select("id")
            .eq("organization_id", ouuid).execute().data
        ]
        if not ids:
            return []
        return [r for r in rows if r.get("beekeeper_id") in ids]

    def create_inspection(self, inspection, *, client_id=""):
        if client_id:
            inspection["client_id"] = client_id
        row = self._clip(inspection, self._INSPECTION_COLS, iso=("inspected_at",))
        return self._with_client_id(self._upsert("inspections", row, key="client_id"))

    def get_inspection(self, inspection_id):
        return self._with_client_id(self._get_by("inspections", "id", inspection_id))

    def list_inspections(self, beekeeper_id, hive_id="", org_id=""):
        rows = []
        q = self._table("inspections").select("*")
        if beekeeper_id:
            q = q.eq("beekeeper_id", beekeeper_id)
        if hive_id:
            q = q.eq("hive_id", hive_id)
        rows = q.order("inspected_at", desc=True).execute().data
        rows = self._scope_beekeepers(org_id, rows)
        return self._with_client_id_list(rows)

    def create_treatment(self, treatment, *, client_id=""):
        if client_id:
            treatment["client_id"] = client_id
        row = self._clip(treatment, self._TREATMENT_COLS, iso=("treated_at",))
        return self._with_client_id(self._upsert("treatments", row, key="client_id"))

    def get_treatment(self, treatment_id):
        return self._with_client_id(self._get_by("treatments", "id", treatment_id))

    def list_treatments(self, beekeeper_id, hive_id="", org_id=""):
        q = self._table("treatments").select("*")
        if beekeeper_id:
            q = q.eq("beekeeper_id", beekeeper_id)
        if hive_id:
            q = q.eq("hive_id", hive_id)
        rows = q.order("treated_at", desc=True).execute().data
        rows = self._scope_beekeepers(org_id, rows)
        return self._with_client_id_list(rows)

    # -- batches --
    def create_batch(self, batch, *, client_id=""):
        if client_id:
            batch["client_id"] = client_id
        row = self._clip(batch, self._BATCH_COLS, iso=("created_at",))
        # batches.organization_id is a uuid FK: translate the public org code
        # (ORG-0000NN) users carry around to organizations.id. Unknown/blank
        # orgs store NULL — never a text code (22P02).
        row["organization_id"] = self._org_uuid(row.get("organization_id"))
        return self._upsert("batches", row, key="client_id")

    def get_batch(self, batch_id):
        return self._get_by("batches", "id", batch_id)

    def get_batch_by_code(self, code):
        return self._get_by("batches", "batch_code", code)

    def list_batches(self, org_id, beekeeper_id=""):
        if beekeeper_id:
            return (
                self._table("batches")
                .select("*")
                .eq("beekeeper_id", beekeeper_id)
                .order("created_at", desc=True)
                .execute().data
            )
        q = self._table("batches").select("*")
        if org_id:
            ouuid = self._org_filter_value(org_id)
            if not ouuid:
                return []
            q = q.eq("organization_id", ouuid)
        return q.order("created_at", desc=True).execute().data

    def update_batch(self, batch_id, updates):
        row = self._clip(updates, self._BATCH_COLS, iso=("created_at",))
        if row:
            self._table("batches").update(row).eq("id", batch_id).execute()
        return self.get_batch(batch_id)

    def link_batch_harvest(self, batch_id, harvest_id, quantity_kg):
        exists = (
            self._table("batch_harvests")
            .select("batch_id")
            .eq("batch_id", batch_id)
            .eq("harvest_event_id", harvest_id)
            .limit(1)
            .execute()
            .data
        )
        if exists:
            return
        self._table("batch_harvests").insert(
            {
                "batch_id": batch_id,
                "harvest_event_id": harvest_id,
                "quantity_kg": quantity_kg,
            }
        ).execute()

    def list_batch_harvests(self, batch_id):
        rows = (
            self._table("batch_harvests")
            .select("*")
            .eq("batch_id", batch_id)
            .execute().data
        )
        return [self._harvest_link(r) for r in rows]

    def list_batch_harvests_by_harvest(self, harvest_id):
        rows = (
            self._table("batch_harvests")
            .select("*")
            .eq("harvest_event_id", harvest_id)
            .execute().data
        )
        return [self._harvest_link(r) for r in rows]

    @staticmethod
    def _harvest_link(row):
        return {
            "batch_id": row.get("batch_id"),
            "harvest_id": row.get("harvest_event_id"),
            "quantity_kg": row.get("quantity_kg"),
        }

    # -- genealogy --
    def add_batch_relation(self, relation):
        self._table("relations").insert(
            {
                "parent_batch_id": relation.get("parent_batch_id"),
                "child_batch_id": relation.get("child_batch_id"),
                "relationship_type": relation.get("relation_type")
                or relation.get("relationship_type"),
                "quantity_kg": relation.get("quantity_kg"),
            }
        ).execute()

    def list_batch_relations(self, batch_id, direction="both"):
        rows = []
        if direction in ("parents", "both"):
            rows.extend(
                self._table("relations")
                .select("*")
                .eq("child_batch_id", batch_id)
                .execute().data
            )
        if direction in ("children", "both"):
            rows.extend(
                self._table("relations")
                .select("*")
                .eq("parent_batch_id", batch_id)
                .execute().data
            )
        for row in rows:
            row["relation_type"] = row.pop("relationship_type", "")
        return rows

    # -- lab --
    def create_lab_test(self, test):
        row = self._clip(test, self._LAB_TEST_COLS, iso=("requested_at",))
        data = self._table("lab_tests").insert(row).execute().data
        return data[0]

    def get_lab_test(self, test_id):
        return self._get_by("lab_tests", "id", test_id)

    def update_lab_test(self, test_id, updates):
        row = self._clip(
            updates,
            self._LAB_TEST_COLS + ("result", "tested_by", "notes", "tested_at"),
            iso=("tested_at", "requested_at"),
        )
        if row:
            self._table("lab_tests").update(row).eq("id", test_id).execute()
        return self.get_lab_test(test_id)

    def list_lab_tests(self, batch_id):
        return (
            self._table("lab_tests")
            .select("*")
            .eq("batch_id", batch_id)
            .order("requested_at", desc=False)
            .execute().data
        )

    def list_lab_tests_for_batches(self, batch_ids: list[str]):
        if not batch_ids:
            return []
        return (
            self._table("lab_tests")
            .select("*")
            .in_("batch_id", batch_ids)
            .order("requested_at", desc=False)
            .execute().data
        )

    def list_lab_queue(self, lab_id):
        return (
            self._table("lab_tests")
            .select("*")
            .eq("lab_id", lab_id)
            .eq("status", "requested")
            .order("requested_at", desc=False)
            .execute().data
        )

    # -- custody --
    def add_custody_event(self, event):
        notes = event.get("notes") or ""
        metadata: dict = {"notes": notes} if notes else {}
        if event.get("to_actor"):
            metadata["to_actor"] = event["to_actor"]
        if event.get("to_org"):
            metadata["to_org"] = event["to_org"]
        if event.get("client_id"):
            metadata["client_id"] = event["client_id"]
        row = {
            "batch_id": event.get("batch_id"),
            "actor_id": None,
            "actor_role": event.get("actor") or "",
            "event_type": event.get("action"),
            "timestamp": self._iso(event.get("event_at")),
            "location": None,
            "quantity_kg": event.get("quantity_kg"),
            "metadata": metadata,
        }
        data = self._table("custody").insert(row).execute().data
        return self._custody(data[0])

    def list_custody_events(self, batch_id):
        rows = (
            self._table("custody")
            .select("*")
            .eq("batch_id", batch_id)
            .order("timestamp", desc=False)
            .execute().data
        )
        return [self._custody(r) for r in rows]

    @classmethod
    def _custody(cls, row):
        meta = row.get("metadata") or {}
        return {
            "id": row.get("id"),
            "batch_id": row.get("batch_id"),
            "action": row.get("event_type"),
            "actor": row.get("actor_role") or row.get("actor_id") or "",
            "notes": meta.get("notes", "") if isinstance(meta, dict) else "",
            "event_at": row.get("timestamp"),
            "to_actor": meta.get("to_actor", "") if isinstance(meta, dict) else "",
            "to_org": meta.get("to_org", "") if isinstance(meta, dict) else "",
            "quantity_kg": row.get("quantity_kg"),
            "client_id": meta.get("client_id", "") if isinstance(meta, dict) else "",
        }

    # -- anchors --
    def add_anchor(self, anchor):
        chain_status = anchor.get("chain_status", "pending")
        row = {
            "batch_id": anchor.get("batch_id"),
            "event_id": anchor.get("event_id"),
            "data_hash": anchor.get("data_hash", ""),
            "transaction_hash": anchor.get("tx_hash") or anchor.get("transaction_hash"),
            "network": anchor.get("network"),
            "status": "confirmed" if chain_status == "anchored" else "pending",
            "anchored_at": self._iso(
                anchor.get("anchored_at") or anchor.get("confirmed_at")
            ),
        }
        data = self._table("anchors").insert(row).execute().data
        return self._anchor(data[0])

    def get_anchor(self, batch_id):
        data = (
            self._table("anchors")
            .select("*")
            .eq("batch_id", batch_id)
            .order("anchored_at", desc=True, nullsfirst=False)
            .limit(1)
            .execute().data
        )
        if not data:
            return None
        return self._anchor(data[0])

    @staticmethod
    def _anchor(row):
        status = (row.get("status") or "pending").lower()
        return {
            "batch_id": row.get("batch_id"),
            "data_hash": row.get("data_hash", ""),
            "tx_hash": row.get("transaction_hash", ""),
            "network": row.get("network", ""),
            "chain_status": "anchored" if status == "confirmed" else "pending",
            "anchored_at": row.get("anchored_at"),
        }

    # -- passports --
    def save_passport(self, passport):
        row = {
            "subject_code": passport["subject_code"],
            "subject_type": passport.get("subject_type", "batch"),
            "payload": passport.get("payload", {}),
        }
        self._table("passports").upsert(row, on_conflict="subject_code").execute()

    def get_passport(self, subject_code):
        return self._get_by("passports", "subject_code", subject_code)

    def find_by_client_id(self, table, client_id):
        return self._get_by(table, "client_id", client_id)

    # -- evidence bundles --
    def add_evidence_bundle(self, bundle):
        row = self._clip(bundle, self._evidence_cols, iso=("created_at",))
        data = self._table("evidence_bundles").insert(row).execute().data
        return data[0]

    def get_evidence_bundle(self, bundle_id):
        return self._get_by("evidence_bundles", "bundle_id", bundle_id)

    # -- ledger --
    def add_ledger_event(self, event):
        row = self._clip(event, self._LEDGER_COLS, iso=("ts",))
        data = self._table("ledger_events").insert(row).execute().data
        return data[0]

    def list_ledger_events(self, chain_id):
        rows = (
            self._table("ledger_events")
            .select("*")
            .eq("chain_id", chain_id)
            .order("index", desc=False)
            .execute().data
        )
        return [{k: r[k] for k in self._LEDGER_COLS if k in r} for r in rows]

    # -- certificates --
    def add_certificate(self, certificate):
        row = self._clip(certificate, self._CERT_COLS, iso=("issued_at",))
        if not row.get("valid_until"):
            row["valid_until"] = None
        if not row.get("revoked_at"):
            row["revoked_at"] = None
        data = self._table("certificates").insert(row).execute().data
        return data[0]

    def get_certificate(self, certificate_id):
        return self._get_by("certificates", "certificate_id", certificate_id)

    def list_certificates(self, batch_id):
        return (
            self._table("certificates")
            .select("*")
            .eq("batch_id", batch_id)
            .execute().data
        )

    def list_certificates_for_batches(self, batch_ids: list[str]):
        if not batch_ids:
            return []
        return (
            self._table("certificates")
            .select("*")
            .in_("batch_id", batch_ids)
            .execute().data
        )

    def revoke_certificate(self, certificate_id, *, revoked_at, reason):
        self._table("certificates").update(
            {"status": "revoked", "revoked_at": revoked_at, "revocation_reason": reason}
        ).eq("certificate_id", certificate_id).execute()
        return self.get_certificate(certificate_id)

    # -- IoT devices --
    def create_iot_device(self, device):
        row = self._clip(device, self._IOT_DEVICE_COLS, iso=())
        if not row.get("device_id"):
            row["device_id"] = new_id()
        return self._table("iot_devices").insert(row).execute().data[0]

    def get_iot_device(self, device_id):
        return self._get_by("iot_devices", "device_id", device_id)

    def list_iot_devices(self, organization_id=""):
        q = self._table("iot_devices").select("*")
        if organization_id:
            q = q.eq("organization_id", organization_id)
        return q.execute().data

    def update_iot_device(self, device_id, updates):
        row = self._clip(updates, self._IOT_DEVICE_UPDATE_COLS, iso=())
        if row:
            self._table("iot_devices").update(row).eq("device_id", device_id).execute()
        return self.get_iot_device(device_id)

    # -- telemetry --
    def add_telemetry_event(self, event):
        row = self._clip(event, self._TELEMETRY_COLS, iso=("timestamp",))
        return self._table("telemetry_events").insert(row).execute().data[0]

    def get_telemetry_event(self, event_id):
        return self._get_by("telemetry_events", "event_id", event_id)

    def list_telemetry_events(self, device_id, limit=20, since=""):
        q = self._table("telemetry_events").select("*").eq("device_id", device_id)
        if since:
            q = q.gte("timestamp", since)
        return q.order("timestamp", desc=True).limit(limit).execute().data

    def list_telemetry_events_for_devices(self, device_ids: list[str], limit: int = 10000):
        if not device_ids:
            return []
        return (
            self._table("telemetry_events")
            .select("*")
            .in_("device_id", device_ids)
            .order("timestamp", desc=True)
            .limit(limit)
            .execute().data
        )

    def telemetry_events_for_hive(self, hive_id, limit=50):
        return (
            self._table("telemetry_events")
            .select("*")
            .eq("hive_id", hive_id)
            .order("timestamp", desc=True)
            .limit(limit)
            .execute().data
        )

    # -- notifications --
    def add_notification(self, notification):
        row = self._clip(notification, self._NOTIFICATION_COLS, iso=("created_at",))
        if not row.get("notification_id"):
            row["notification_id"] = new_id()
        return self._table("notifications").insert(row).execute().data[0]

    def list_notifications(self, org_id="", hive_id=""):
        q = self._table("notifications").select("*")
        if org_id:
            q = q.eq("organization_id", org_id)
        if hive_id:
            q = q.eq("hive_id", hive_id)
        return q.order("created_at", desc=True).execute().data

    def mark_notification_read(self, notification_id):
        self._table("notifications").update({"read": True}).eq(
            "notification_id", notification_id
        ).execute()
        return self.get_notification(notification_id)

    def get_notification(self, notification_id):
        return self._get_by("notifications", "notification_id", notification_id)

    # -- helpers --
    @property
    def _evidence_cols(self):
        return (
            "bundle_id", "entity_type", "entity_ref", "operator", "device_id",
            "created_at", "leaf_count", "root_hash", "evidence", "anchor",
        )

    @staticmethod
    def _iso(value):
        from datetime import datetime, timezone

        if isinstance(value, datetime):
            return value.isoformat()
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return datetime.fromtimestamp(value, tz=timezone.utc).isoformat()
        return value

    def _clip(self, raw, columns, *, iso):
        out = {k: raw[k] for k in columns if k in raw and raw[k] is not None}
        for k in iso:
            if k in out:
                out[k] = self._iso(out[k])
        if not out:
            return {}
        return out

    @staticmethod
    def _is_uuid(value: str) -> bool:
        return isinstance(value, str) and len(value) == 36

    def _org_uuid(self, org_ref):
        """Canonical UUID for UUID FK columns (batches, beekeepers).

        `users.org_id` and invite `organization_key` hold the PUBLIC business
        code (e.g. ORG-000016); uuid FK columns must hold `organizations.id`.
        Passing the code into a uuid column raises Postgres 22P02, which is
        exactly the batch-creation failure this resolves. Unknown codes map to
        None so inserts stay valid and queries can scope to zero rows instead
        of leaking the whole table.
        """
        ref = str(org_ref or "").strip()
        if not ref:
            return None
        if self._is_uuid(ref):
            return ref
        row = self._get_by("organizations", "organization_key", ref)
        return str(row["id"]) if row else None

    def _org_filter_value(self, org_ref):
        """Resolve an org ref for a .eq(organization_id=...) query.

        Returns None when the ref identifies no organization; callers must
        then return an empty result (the org exists nowhere => owns nothing).
        """
        ref = str(org_ref or "").strip()
        if not ref:
            return None
        if self._is_uuid(ref):
            return ref
        return self._org_uuid(ref)

    def _get_by(self, table, column, value):
        data = (
            self._table(table).select("*").eq(column, value).limit(1).execute().data
        )
        return data[0] if data else None

    def _upsert(self, table, row, key):
        if not row:
            return {}
        if key not in row or row.get(key) in (None, ""):
            # No stable dedup key (e.g. a local-only create) and the partial
            # unique index cannot act as an ON CONFLICT arbiter — plain insert.
            data = self._table(table).insert(row).execute().data
            return data[0] if data else row
        try:
            data = (
                self._table(table).upsert(row, on_conflict=key).execute().data
            )
            return data[0] if data else row
        except Exception as exc:  # noqa: BLE001 — narrowed below by code probe
            msg = str(getattr(exc, "args", [""])[0])
            if "42P10" not in msg:
                raise
            # The table has no unique constraint on [key] (Postgres 42P10), so
            # ON CONFLICT is impossible. Fall back to select-then-insert dedup:
            # the same client_id returns the stored row instead of 500-ing, and
            # a new one inserts. Idempotency is preserved at application level.
            existing = (
                self._table(table).select("*").eq(key, row[key]).limit(1).execute().data
            )
            if existing:
                return existing[0]
            data = self._table(table).insert(row).execute().data
            return data[0] if data else row




class DemoSeededRepository(InMemoryRepository):
    """InMemoryRepository pre-populated with demo identities so a local run and
    the test-suite share the same determinism as the Flutter demo app."""

    def __init__(self) -> None:
        from ..core.security import hash_password

        super().__init__()
        beekeeper = self.create_user(
            email="demo@honeychain.in",
            name="Ravi Kumar",
            phone="+919000000000",
            role="beekeeper",
            org_id="ORG-000001",
            password_hash=hash_password("HoneyChainDemo!1"),
        )
        self._seed_beekeeper = beekeeper
        org = self.ensure_organization(
            {
                "id": "ORG-000001",
                "organization_key": "ORG-000001",
                "name": "HoneyChain Demo FPO",
                "type": "FPO",
                "status": "ACTIVE",
            }
        )
        self._seed_org = org
        return None


def build_repository() -> Repository:
    settings = get_settings()
    if settings.supabase_url and settings.supabase_service_role_key:
        log.info("Using SupabaseRepository (service-role, server-side only).")
        return SupabaseRepository(
            settings.supabase_url, settings.supabase_service_role_key
        )
    log.warning(
        "No SUPABASE_SERVICE_ROLE_KEY configured — using in-memory repository "
        "(safe for local dev/tests; switch to SupabaseRepository for production)."
    )
    return DemoSeededRepository()