from __future__ import annotations

from typing import Any

from ..core.config import get_settings
from ..core.security import (
    create_access_token,
    hash_password,
    verify_password,
)
from ..db.supabase import InMemoryRepository, Repository

DEMO_PASSWORD = "HoneyChainDemo!1"

# Roles that require an existing (or platform-issued) organization binding.
_ORG_ROLES = ("fpo", "processor", "lab")

# Organization lifecycle states that still allow their admin to self-register.
_OPEN_ORG_STATUSES = ("ACTIVE", "PENDING")


def _producer_id_for(repo: Repository, *, exclude: str = "") -> str:
    """Deterministic next HoneyChain Producer ID (HC-BK-XXXXXX).

    The ID is a beekeeper identity, distinct from the login user id, FPO id and
    org id. It is purely sequential — it must never be mistaken for a
    government/NBB identifier (see madhukranti_id for that field).
    """
    numbers: list[int] = []
    for row in repo.list_beekeepers():
        pid = str(row.get("producer_id") or "")
        if not pid.startswith("HC-BK-"):
            continue
        try:
            numbers.append(int(pid.split("-")[-1]))
        except ValueError:
            continue
    return f"HC-BK-{max(numbers, default=0) + 1:06d}"


class AuthService:
    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    def login(self, identifier: str, password: str) -> dict[str, Any]:
        user = self._repo.get_user_by_email(identifier) or self._repo.get_user_by_phone(
            identifier
        )
        if user is None or not verify_password(password, user.get("password_hash", "")):
            return {"error": "invalid credentials"}
        if str(user.get("status") or "ACTIVE") == "SUSPENDED":
            return {"error": "account is suspended"}
        # Fetch all roles for the user (multi-role support)
        roles = self._repo.get_user_roles(user["id"])
        primary_role = roles[0] if roles else user.get("role", "")
        token = create_access_token(
            subject=user["id"],
            role=primary_role,
            roles=roles,
            org_id=user.get("org_id", ""),
        )
        return {
            "access_token": token,
            "token_type": "bearer",
            "expires_in_minutes": get_settings().access_token_expire_minutes,
        }

    def me(self, user_id: str) -> dict[str, Any] | None:
        user = self._repo.get_user(user_id)
        if user is None:
            return None
        roles = self._repo.get_user_roles(user_id)
        primary_role = roles[0] if roles else user.get("role", "")
        producer_id = ""
        if primary_role == "beekeeper":
            beekeeper = self._repo.get_beekeeper(user_id)
            producer_id = str((beekeeper or {}).get("producer_id") or "")
        org = self._repo.get_organization(user.get("org_id", "")) or {}
        return {
            "id": user["id"],
            "email": user.get("email", ""),
            "name": user.get("name", ""),
            "phone": user.get("phone", ""),
            "role": primary_role,
            "roles": roles,
            "org_id": user.get("org_id", ""),
            "producer_id": producer_id,
            "org_name": org.get("name", ""),
            "status": user.get("status", "ACTIVE"),
        }

    def register(self, data: dict[str, Any]) -> dict[str, Any]:
        email = data["email"].lower()
        if self._repo.get_user_by_email(email):
            return {"error": "user already exists"}
        # Phone is only an identity when one was actually supplied. A blank
        # phone is not unique: the users table legitimately holds many rows
        # with an empty phone, so querying the phone column with "" collides
        # with an unrelated account and blocks every phone-less registration
        # ("user already exists"). Only look up a non-empty phone.
        phone = str(data.get("phone") or "").strip()
        if phone and self._repo.get_user_by_phone(phone):
            return {"error": "user already exists"}

        role = data["role"]
        org_id = data.get("org_id", "") or ""
        invite_code = (data.get("invite_code") or "").strip()

        if role == "fpo":
            # An FPO cannot self-create an organization. The platform provisions
            # the org row (platform endpoints) and issues a one-time invite, so
            # the register call can only ever bind to a platform-created org.
            if not invite_code:
                return {"error": "an organization invite code is required to register an FPO"}
            invite = self._repo.get_organization_invite(invite_code)
            if invite is None or invite.get("status") != "PENDING":
                return {"error": "invalid or already-used organization invite"}
            invite_email = str(invite.get("email") or "").lower()
            if invite_email and invite_email != email:
                return {"error": "this invite was issued to a different email"}
            org = self._repo.get_organization(invite["organization_key"])
            if org is None:
                return {"error": "the organization for this invite no longer exists"}
            org_status = str(org.get("status") or "ACTIVE")
            if org_status not in _OPEN_ORG_STATUSES:
                return {"error": f"organization is {org_status}; registration is closed"}
            org_id = invite["organization_key"]
        elif role in ("processor", "lab") and org_id:
            org = self._repo.get_organization(org_id)
            if org is None:
                return {"error": f"organization '{org_id}' does not exist"}

        user = self._repo.create_user(
            email=email,
            name=data["name"],
            phone=data.get("phone", ""),
            role=role,
            org_id=org_id,
            password_hash=hash_password(data["password"]),
        )
        if role == "fpo":
            self._repo.mark_organization_invite_used(invite_code, user["id"])
        if role == "beekeeper":
            # Persistent HoneyChain Producer ID, created server-side and never
            # chosen by the client.
            self._repo.ensure_beekeeper(
                {
                    "id": user["id"],
                    "org_id": org_id,
                    "name": data.get("name", ""),
                    "phone": data.get("phone", ""),
                    "producer_id": _producer_id_for(self._repo, exclude=user["id"]),
                }
            )
        return self.me(user["id"])


def bootstrap_identities(repo: Repository) -> None:
    """Seed demo identities for local dev / tests.

    Never runs against production: production identities are created through the
    registration endpoint by operators or an admin provisioning flow.
    """
    if isinstance(repo, InMemoryRepository) is False:
        return
    demo = repo.get_user_by_email("demo@honeychain.in")
    if demo is None:
        demo = repo.create_user(
            email="demo@honeychain.in",
            name="Ravi Kumar",
            phone="+919000000000",
            role="beekeeper",
            org_id="ORG-000001",
            password_hash=hash_password(DEMO_PASSWORD),
        )
    repo.ensure_beekeeper(
        {
            "id": demo["id"],
            "org_id": demo.get("org_id", "ORG-000001"),
            "name": demo.get("name", "Ravi Kumar"),
            "phone": demo.get("phone", "+919000000000"),
            "producer_id": "HC-BK-000001",
        }
    )
    if repo.get_user_by_email("org@honeychain.in") is None:
        repo.create_user(
            email="org@honeychain.in",
            name="HoneyChain Demo FPO",
            phone="+919000000001",
            role="fpo",
            org_id="ORG-000001",
            password_hash=hash_password(DEMO_PASSWORD),
        )
    if repo.get_user_by_email("lab@honeychain.in") is None:
        repo.create_user(
            email="lab@honeychain.in",
            name="HoneyChain Demo Lab",
            phone="+919000000002",
            role="lab",
            org_id="",
            password_hash=hash_password(DEMO_PASSWORD),
        )
    if repo.get_user_by_email("admin@honeychain.in") is None:
        repo.create_user(
            email="admin@honeychain.in",
            name="HoneyChain Admin",
            phone="+919000000009",
            role="admin",
            org_id="",
            password_hash=hash_password(DEMO_PASSWORD),
        )