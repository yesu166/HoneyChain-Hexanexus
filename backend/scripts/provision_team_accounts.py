"""Provision the six HoneyChain team accounts on the DEPLOYED backend.

Mechanism (same architecture as existing auth): login-first with the team
password; if the account does not exist yet, register it as a beekeeper via the
public /auth/register endpoint — exactly how the demo account and the E2E
scripts create real production identities. The Supabase service-role key stays
server-side (inside the deployed backend); nothing here touches Supabase or any
secret directly.

Idempotent: rerunning never creates duplicates. A 409 from register means the
email already exists — we then verify it can log in with the team password. If
it exists but the password does not match, that is reported as a CONFLICT (it
must be fixed manually via a service-role/admin flow; this runner never resets
it silently).

Password comes from HONEYCHAIN_TEAM_DEFAULT_PASSWORD env (never printed).
Verification per account: login -> JWT -> /auth/me (beekeeper, producer id) ->
one real beekeeper API call (GET /hives). The demo account is re-verified at
the end and must remain intact.

Usage:
    $env:HONEYCHAIN_TEAM_DEFAULT_PASSWORD="your-team-password-8plus-chars"
    python scripts/provision_team_accounts.py
    python scripts/provision_team_accounts.py --base https://honeychain-api.onrender.com/api/v1
"""
from __future__ import annotations

import argparse
import os
import sys
import time
import uuid

import httpx

TEAM_ACCOUNTS = [
    "madihamubarak1124@gmail.com",
    "adni71845@gmail.com",
    "rakshanthimal@gmail.com",
    "yesuraja166@gmail.com",
    "amirdavarshinid28@gmail.com",
    "srvijayaragavan2008@gmail.com",
]

DEMO_EMAIL = "devbee1790208537x@example.com"
DEMO_PASSWORD = "DevBee2026"

PASSWORD_ENV = "HONEYCHAIN_TEAM_DEFAULT_PASSWORD"

passed = 0


def mark(label: str, ok: bool, detail: str = "") -> None:
    global passed
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {label}" + (f" | {detail}" if detail else ""))
    if ok:
        passed += 1


def login(client: httpx.Client, email: str, password: str) -> str | None:
    """Return a JWT for a working login, or None on 401."""
    r = client.post(
        "/auth/login",
        json={"identifier": email, "password": password},
    )
    if r.status_code != 200:
        return None
    return r.json()["access_token"]


def provision_one(
    client: httpx.Client, email: str, password: str
) -> tuple[bool, str]:
    """Ensure the account exists with the team password and can sign in.

    Returns (ok, created_or_conflict_flag).
    """
    token = login(client, email, password)
    if token:
        return True, "existing"

    r = client.post(
        "/auth/register",
        json={
            "email": email,
            "name": email.split("@")[0],
            "phone": "",
            "password": password,
            "role": "beekeeper",
        },
    )
    if r.status_code == 201:
        token = login(client, email, password)
        return token is not None, "created"
    if r.status_code == 409:
        # Email already exists but the team password did not work.
        return False, "conflict"
    return False, f"register http {r.status_code}"


def verify_me_and_beekeeper(client: httpx.Client, token: str, email: str) -> bool:
    """/auth/me returns this beekeeper + a producer id; beekeeper API works."""
    headers = {"Authorization": f"Bearer {token}"}
    try:
        me = client.get("/auth/me", headers=headers)
        if me.status_code != 200:
            return False
        body = me.json()
        if body.get("email") != email:
            return False
        if body.get("role") != "beekeeper":
            return False
        # Independent team beekeepers have no org; producer id is assigned.
        if not body.get("producer_id", ""):
            return False
        hives = client.get("/hives", headers=headers)
        return hives.status_code == 200
    except httpx.HTTPError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--base",
        default=os.getenv("LIVE_BASE"),
        help="Default: backend URL from LIVE_BASE env.",
    )
    args = parser.parse_args()
    base = args.base
    if not base:
        base = input("Base API URL (e.g. https://honeychain-api.onrender.com/api/v1): ").strip()
    base = base.rstrip("/")

    password = os.getenv(PASSWORD_ENV, "")
    if not password:
        print(f"[FAIL] {PASSWORD_ENV} env var is required and not set (never pass it on argv).")
        return 1

    errors: list[str] = []
    with httpx.Client(base_url=base, timeout=90.0) as client:
        for email in TEAM_ACCOUNTS:
            ok, detail = provision_one(client, email, password)
            mark(f"provision {email}", ok, detail)
            if not ok:
                if detail == "conflict":
                    errors.append(f"{email}: exists but team password rejected (needs manual fix)")
                else:
                    errors.append(f"{email}: {detail}")
                continue
            token = login(client, email, password)
            if not token:
                mark(f"login {email}", False, "no token after provision")
                errors.append(f"{email}: no token")
                continue
            if not verify_me_and_beekeeper(client, token, email):
                mark(f"verify {email}", False, "me/producer/beekeeper API failed")
                errors.append(f"{email}: verification failed")
            else:
                mark(f"verify {email}", True, "me+producer_id+hives OK")

        demo_token = login(client, DEMO_EMAIL, DEMO_PASSWORD)
        demo_ok = demo_token is not None and verify_me_and_beekeeper(
            client, demo_token, DEMO_EMAIL
        )
        mark("demo account intact", demo_ok, DEMO_EMAIL)

    total = 1 + 2 * len(TEAM_ACCOUNTS)
    print(f"\nResult: {passed}/{total} provisioning checks passed.")
    for err in errors:
        print(f"  CONFLICT {err}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())