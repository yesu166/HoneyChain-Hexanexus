"""Repository boundaries for the HoneyChain backend.

The system of record is Supabase PostgreSQL; [SupabaseRepository] talks to it
with the server-side service-role key. [InMemoryRepository] is the local/
development/test implementation used when no credentials are configured — it
keeps every pytest green without a live cloud project.

All repository methods exchange plain dicts; schemas/services convert.
"""
from __future__ import annotations

import uuid
from abc import ABC, abstractmethod
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


class InMemoryRepository(Repository):
    """Local dict-backed repository for development and tests.

    Deterministic and dependency-free; intentionally small.
    """

    def __init__(self, seed: dict[str, list[dict[str, Any]]] | None = None) -> None:
        data: dict[str, list[dict[str, Any]]] = {
            "users": [],
            "organizations": [],
            "beekeepers": [],
            "hives": [],
            "readings": [],
            "harvests": [],
            "batch_harvests": [],
            "batches": [],
            "relations": [],
            "lab_tests": [],
            "custody": [],
            "anchors": [],
            "passports": [],
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
    def ensure_organization(self, org):
        existing = next(
            (o for o in self._data["organizations"] if o["id"] == org.get("id")), None
        )
        if existing:
            existing.update({k: v for k, v in org.items() if v is not None})
            return existing
        row = {"id": org.get("id") or new_id(), **org}
        self._data["organizations"].append(row)
        return row

    def get_organization(self, org_id):
        return next((o for o in self._data["organizations"] if o["id"] == org_id), None)

    def list_organizations(self):
        return list(self._data["organizations"])

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
            return [b for b in self._data["beekeepers"] if b.get("org_id") == org_id]
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


class SupabaseRepository(Repository):
    """PostgreSQL via Supabase's service-role client.

    The supabase client is imported lazily so the backend still boots (and its
    tests run) where the SDK is not installed. All writes are upserts keyed by
    the stable `client_id` where the schema provides one, keeping retries
    idempotent.
    """

    TABLE_MAP = {
        "users": "users",
        "organizations": "organizations",
        "beekeepers": "beekeepers",
        "hives": "hives",
        "readings": "hive_readings",
        "harvests": "harvest_events",
        "batch_harvests": "batch_harvest_events",
        "batches": "batches",
        "relations": "batch_relations",
        "lab_tests": "lab_tests",
        "custody": "custody_events",
        "anchors": "blockchain_anchors",
        "passports": "passports",
    }

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
        return data[0]

    def get_user_by_email(self, email):
        data = self._table("users").select("*").eq("email", email).limit(1).execute().data
        return data[0] if data else None

    def get_user_by_phone(self, phone):
        data = self._table("users").select("*").eq("phone", phone).limit(1).execute().data
        return data[0] if data else None

    def get_user(self, user_id):
        data = self._table("users").select("*").eq("id", user_id).limit(1).execute().data
        return data[0] if data else None

    # -- organizations / beekeepers -- (upsert on client_id / id)
    def ensure_organization(self, org):
        return self._upsert("organizations", org, key="client_id")

    def get_organization(self, org_id):
        return self._get_by("organizations", "id", org_id)

    def list_organizations(self):
        return self._table("organizations").select("*").execute().data

    def ensure_beekeeper(self, beekeeper):
        return self._upsert("beekeepers", beekeeper, key="client_id")

    def get_beekeeper(self, beekeeper_id):
        return self._get_by("beekeepers", "id", beekeeper_id)

    def list_beekeepers(self, org_id=None):
        q = self._table("beekeepers").select("*")
        if org_id:
            q = q.eq("org_id", org_id)
        return q.execute().data

    # -- hives --
    def create_hive(self, hive, *, client_id=""):
        if client_id:
            hive["client_id"] = client_id
        return self._upsert("hives", hive, key="client_id")

    def get_hive(self, hive_id):
        return self._get_by("hives", "id", hive_id)

    def list_hives(self, beekeeper_id):
        q = self._table("hives").select("*")
        if beekeeper_id:
            q = q.eq("beekeeper_id", beekeeper_id)
        return q.execute().data

    def update_hive(self, hive_id, updates):
        self._table("hives").update(updates).eq("id", hive_id).execute()
        return self.get_hive(hive_id)

    # -- readings --
    def add_reading(self, reading):
        return self._table("readings").insert(reading).execute().data[0]

    def list_readings(self, hive_id, limit=100):
        return (
            self._table("readings")
            .select("*")
            .eq("hive_id", hive_id)
            .order("recorded_at", desc=True)
            .limit(limit)
            .execute()
            .data
        )

    # -- harvests --
    def create_harvest(self, harvest, *, client_id=""):
        if client_id:
            harvest["client_id"] = client_id
        return self._upsert("harvests", harvest, key="client_id")

    def get_harvest(self, harvest_id):
        return self._get_by("harvests", "id", harvest_id)

    def list_harvests(self, beekeeper_id, org_id=""):
        q = self._table("harvests").select("*")
        if beekeeper_id:
            q = q.eq("beekeeper_id", beekeeper_id)
        return q.execute().data

    # -- batches --
    def create_batch(self, batch, *, client_id=""):
        if client_id:
            batch["client_id"] = client_id
        return self._upsert("batches", batch, key="client_id")

    def get_batch(self, batch_id):
        return self._get_by("batches", "id", batch_id)

    def get_batch_by_code(self, code):
        return self._get_by("batches", "batch_code", code)

    def list_batches(self, org_id, beekeeper_id=""):
        q = self._table("batches").select("*")
        if org_id:
            q = q.eq("organization_id", org_id)
        return q.execute().data

    def update_batch(self, batch_id, updates):
        self._table("batches").update(updates).eq("id", batch_id).execute()
        return self.get_batch(batch_id)

    def link_batch_harvest(self, batch_id, harvest_id, quantity_kg):
        self._table("batch_harvests").insert(
            {"batch_id": batch_id, "harvest_id": harvest_id, "quantity_kg": quantity_kg}
        ).execute()

    def list_batch_harvests(self, batch_id):
        return (
            self._table("batch_harvests").select("*").eq("batch_id", batch_id).execute().data
        )

    def list_batch_harvests_by_harvest(self, harvest_id):
        return (
            self._table("batch_harvests")
            .select("*")
            .eq("harvest_id", harvest_id)
            .execute()
            .data
        )

    # -- genealogy --
    def add_batch_relation(self, relation):
        self._table("relations").insert(relation).execute()

    def list_batch_relations(self, batch_id, direction="both"):
        rows = []
        if direction in ("parents", "both"):
            rows.extend(
                self._table("relations")
                .select("*")
                .eq("child_batch_id", batch_id)
                .execute()
                .data
            )
        if direction in ("children", "both"):
            rows.extend(
                self._table("relations")
                .select("*")
                .eq("parent_batch_id", batch_id)
                .execute()
                .data
            )
        return rows

    # -- lab / custody / anchors / passports --
    def create_lab_test(self, test):
        return self._table("lab_tests").insert(test).execute().data[0]

    def get_lab_test(self, test_id):
        return self._get_by("lab_tests", "id", test_id)

    def update_lab_test(self, test_id, updates):
        self._table("lab_tests").update(updates).eq("id", test_id).execute()
        return self.get_lab_test(test_id)

    def list_lab_tests(self, batch_id):
        return self._table("lab_tests").select("*").eq("batch_id", batch_id).execute().data

    def list_lab_queue(self, lab_id):
        return (
            self._table("lab_tests")
            .select("*")
            .eq("lab_id", lab_id)
            .eq("status", "requested")
            .execute()
            .data
        )

    def add_custody_event(self, event):
        return self._table("custody").insert(event).execute().data[0]

    def list_custody_events(self, batch_id):
        return (
            self._table("custody").select("*").eq("batch_id", batch_id).execute().data
        )

    def add_anchor(self, anchor):
        return self._table("anchors").insert(anchor).execute().data[0]

    def get_anchor(self, batch_id):
        return self._get_by("anchors", "batch_id", batch_id)

    def save_passport(self, passport):
        existing = self.get_passport(passport["subject_code"])
        if existing:
            self._table("passports").update(passport).eq("subject_code", passport["subject_code"]).execute()
        else:
            self._table("passports").insert(passport).execute()

    def get_passport(self, subject_code):
        return self._get_by("passports", "subject_code", subject_code)

    def find_by_client_id(self, table, client_id):
        return self._get_by(table, "client_id", client_id)

    # -- helpers --
    def _get_by(self, table, column, value):
        data = (
            self._table(table).select("*").eq(column, value).limit(1).execute().data
        )
        return data[0] if data else None

    def _upsert(self, table, row, key):
        data = (
            self._table(table).upsert(row, on_conflict=key).execute().data
        )
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
            org_id="ORG-TN-001",
            password_hash=hash_password("HoneyChainDemo!1"),
        )
        self._seed_beekeeper = beekeeper
        org = self.ensure_organization(
            {"id": "ORG-TN-001", "name": "Nilgiris Honey FPO", "type": "FPO"}
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