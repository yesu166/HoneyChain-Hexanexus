"""Authentication and authorization helpers.

Passwords are hashed with PBKDF2-HMAC-SHA256 (stdlib — no binary deps).
JWTs are signed HS256 with the configured secret. Role information is resolved
from the database on each authenticated request; the client must never be
trusted to declare its own role.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import get_settings

_bearer = HTTPBearer(auto_error=False)

_ITERATIONS = 480_000
_SALT_BYTES = 16


# ---------------------------------------------------------------------------
# Passwords
# ---------------------------------------------------------------------------

def hash_password(password: str, salt: bytes | None = None) -> str:
    salt = salt or os.urandom(_SALT_BYTES)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, _ITERATIONS
    )
    return f"pbkdf2${_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _algo, _iters, salt_hex, digest_hex = stored.split("$")
        salt = bytes.fromhex(salt_hex)
        candidate = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), salt, int(_iters)
        )
        return hmac.compare_digest(candidate.hex(), digest_hex)
    except (ValueError, TypeError):
        return False


# ---------------------------------------------------------------------------
# JWT
# ---------------------------------------------------------------------------

def create_access_token(
    subject: str,
    role: str,
    org_id: str = "",
    expires_delta: timedelta | None = None,
) -> str:
    settings = get_settings()
    now = datetime.now(timezone.utc)
    delta = expires_delta or timedelta(
        minutes=settings.access_token_expire_minutes
    )
    payload: dict[str, Any] = {
        "sub": subject,
        "role": role,
        "iat": now,
        "exp": now + delta,
    }
    if org_id:
        payload["org_id"] = org_id
    return jwt.encode(payload, settings.require_jwt_secret(), algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict[str, Any]:
    settings = get_settings()
    try:
        return jwt.decode(
            token,
            settings.require_jwt_secret(),
            algorithms=[settings.jwt_algorithm],
        )
    except jwt.ExpiredSignatureError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
        ) from exc
    except jwt.InvalidTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        ) from exc


# ---------------------------------------------------------------------------
# Current-user resolution
# ---------------------------------------------------------------------------

class CurrentUser:
    """Authenticated caller, resolved from the JWT subject."""

    def __init__(self, *, user_id: str, role: str, org_id: str = "") -> None:
        self.user_id = user_id
        self.role = role
        self.org_id = org_id

    def bare_dict(self) -> dict[str, Any]:
        return {"id": self.user_id, "role": self.role, "org_id": self.org_id}


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    request: Request = None,
) -> CurrentUser:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
        )
    payload = decode_token(credentials.credentials)
    subject = payload.get("sub")
    if not subject:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token subject",
        )
    # Resolve the caller's identity from the repository (the system of record).
    # The JWT subject is trusted as a pointer to a user; its role/org claims are
    # only a fallback for pre-provisioned tokens (e.g. the local test client) and
    # are never authoritative when the user exists in the database.
    role = str(payload.get("role", ""))
    org_id = str(payload.get("org_id", ""))
    # Only subjects that look like real record ids can be looked up in the
    # repository (users.id is uuid in Supabase). Non-uuid subjects are
    # pre-provisioned/claim-role tokens (e.g. a signed service token) whose
    # role/org claims must be used as-is; querying a uuid column with them
    # would be a 22P02 error rather than a clean fallback.
    valid_uuid = True
    try:
        uuid.UUID(str(subject))
    except (ValueError, AttributeError, TypeError):
        valid_uuid = False
    repo = getattr(request.app.state, "repository", None) if request is not None else None
    if repo is not None and valid_uuid:
        row = repo.get_user(str(subject))
        if row is not None:
            role = str(row.get("role") or role)
            org_id = str(row.get("org_id") or org_id)
            if str(row.get("status") or "ACTIVE") == "SUSPENDED":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="account is suspended",
                )
    return CurrentUser(
        user_id=str(subject),
        role=role,
        org_id=org_id,
    )


def require_roles(*roles: str):
    """Dependency factory: allow only users whose role is in [roles].

    RBAC must happen server-side; hiding buttons in the UI is not security.
    """

    def _check(user: CurrentUser = Depends(get_current_user)) -> CurrentUser:
        if user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient role for this operation",
            )
        return user

    return _check


async def ensure_resource_owner(
    user: CurrentUser,
    owner_scope: dict[str, str],
    get_scope: Any,
) -> None:
    """Resource-level check: a beekeeper may only touch rows in owner_scope.

    [get_scope] is a callable returning the owner scope of the target row; if
    the row does not belong to the caller the request is denied 403.
    """
    scope = await get_scope()
    if scope.get("beekeeper_id") and scope.get("beekeeper_id") == user.user_id:
        return
    if scope.get("org_id") and scope.get("org_id") == user.org_id:
        return
    if user.role in ("admin", "institution"):
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="This resource is not in your scope",
    )