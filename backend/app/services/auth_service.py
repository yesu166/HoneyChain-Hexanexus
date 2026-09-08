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


class AuthService:
    def __init__(self, repo: Repository) -> None:
        self._repo = repo

    def login(self, identifier: str, password: str) -> dict[str, Any]:
        user = self._repo.get_user_by_email(identifier) or self._repo.get_user_by_phone(
            identifier
        )
        if user is None or not verify_password(password, user.get("password_hash", "")):
            return {"error": "invalid credentials"}
        token = create_access_token(
            subject=user["id"],
            role=user.get("role", ""),
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
        return {
            "id": user["id"],
            "email": user.get("email", ""),
            "name": user.get("name", ""),
            "phone": user.get("phone", ""),
            "role": user.get("role", ""),
            "org_id": user.get("org_id", ""),
        }

    def register(self, data: dict[str, Any]) -> dict[str, Any]:
        email = data["email"].lower()
        if self._repo.get_user_by_email(email) or self._repo.get_user_by_phone(
            data.get("phone", "")
        ):
            return {"error": "user already exists"}
        user = self._repo.create_user(
            email=email,
            name=data["name"],
            phone=data.get("phone", ""),
            role=data["role"],
            org_id=data.get("org_id", ""),
            password_hash=hash_password(data["password"]),
        )
        return self.me(user["id"])


def bootstrap_identities(repo: Repository) -> None:
    """Seed demo identities for local dev / tests.

    Never runs against production: production identities are created through the
    registration endpoint by operators or an admin provisioning flow.
    """
    if isinstance(repo, InMemoryRepository) is False:
        return
    if repo.get_user_by_email("demo@honeychain.in") is None:
        repo.create_user(
            email="demo@honeychain.in",
            name="Ravi Kumar",
            phone="+919000000000",
            role="beekeeper",
            org_id="ORG-TN-001",
            password_hash=hash_password(DEMO_PASSWORD),
        )
    if repo.get_user_by_email("org@honeychain.in") is None:
        repo.create_user(
            email="org@honeychain.in",
            name="Nilgiris Honey FPO",
            phone="+919000000001",
            role="fpo",
            org_id="ORG-TN-001",
            password_hash=hash_password(DEMO_PASSWORD),
        )
    if repo.get_user_by_email("lab@honeychain.in") is None:
        repo.create_user(
            email="lab@honeychain.in",
            name="Nilgiris Regional Lab",
            phone="+919000000002",
            role="lab",
            org_id="LAB-TN-001",
            password_hash=hash_password(DEMO_PASSWORD),
        )