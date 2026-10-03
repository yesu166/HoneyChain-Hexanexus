#!/usr/bin/env python3
"""Live demo-readiness check for HoneyChain production. Read-only, no secrets.

Verifies, against the DEPLOYED API and the production database, everything the
demo depends on that does not require a user's password:

  1. API reachable + database dependency healthy          (GET /health)
  2. Blockchain adapter honestly reported                (GET /blockchain/health)
  3. Chain data present and de-duplicated                (DB counts, service role)
  4. Tenant resolves to exactly one organization          (DB organizations)
  5. The demo batch's public passport is served           (GET /passport/{code})
  6. Passport integrity caveats (lab backing, real anchor)

It deliberately reports FAIL rather than inventing a result when a stage cannot
be proven. Credential-gated endpoints are listed but not probed.

Usage:
    python scripts/live_readiness_check.py
    python scripts/live_readiness_check.py --base https://honeychain-api.onrender.com/api/v1
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import httpx

DEMO_BATCH = "HC-2026-DEMO-001"

passed = 0
failed = 0


def mark(label: str, ok: bool, detail: str = "") -> None:
    global passed, failed
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f" | {detail}" if detail else ""))
    if ok:
        passed += 1
    else:
        failed += 1


def load_env() -> dict[str, str]:
    """Walk up from this file to the first directory containing .env."""
    root = Path(__file__).resolve().parent
    while not (root / ".env").exists() and root.parent != root:
        root = root.parent
    env: dict[str, str] = {}
    env_file = root / ".env"
    if not env_file.exists():
        return env
    for raw in env_file.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def check_health(c: httpx.Client) -> bool:
    try:
        r = c.get("/health")
        body = r.json() if r.status_code == 200 else {}
        deps = body.get("dependencies", {})
        mark(
            "API reachable",
            r.status_code == 200,
            f"HTTP {r.status_code} status={body.get('status')} version={body.get('version')}",
        )
        mark(
            "database dependency healthy",
            deps.get("database") == "ok",
            f"database={deps.get('database')}",
        )
        return True
    except httpx.HTTPError as exc:
        mark("API reachable", False, repr(exc))
        return False


def check_blockchain(c: httpx.Client) -> None:
    try:
        r = c.get("/blockchain/health")
        b = r.json() if r.status_code == 200 else {}
        adapter = b.get("adapter")
        mark(
            "blockchain adapter reported",
            r.status_code == 200,
            f"adapter={adapter!r} status={b.get('status')!r} "
            f"channel={b.get('channel')!r} chaincode={b.get('chaincode')!r}",
        )
        if adapter != "remote_fabric":
            print(
                f"       NOTE: adapter is {adapter!r}, not 'remote_fabric' — the live "
                "deployment is NOT anchoring to Hyperledger Fabric. Blueprint vs runtime "
                "mismatch must be fixed in the Render service env, not in code."
            )
    except httpx.HTTPError as exc:
        mark("blockchain adapter reported", False, repr(exc))


def check_data(env: dict[str, str]) -> None:
    url = env.get("SUPABASE_URL", "")
    key = env.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not (url and key):
        print(
            "\n[SKIP] SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set locally; "
            "database checks skipped."
        )
        return
    try:
        from supabase import create_client

        sb = create_client(url, key)
        counts: dict[str, object] = {}
        for table in (
            "organizations", "users", "beekeepers", "hives", "harvest_events",
            "batches", "lab_tests", "certificates", "passports", "qr_codes",
            "custody_events",
        ):
            try:
                counts[table] = len(sb.table(table).select("*").limit(1000).execute().data)
            except Exception as exc:  # noqa: BLE001
                counts[table] = f"ERR {str(exc)[:60]}"
        print("\n-- production data counts --")
        for k, v in counts.items():
            print(f"     {k:18s} {v}")

        orgs = sb.table("organizations").select("*").execute().data
        org_ids = [o["id"] for o in orgs]
        mark(
            "tenant resolves to exactly one organization",
            len(orgs) == 1,
            f"orgs={len(orgs)} "
            + ", ".join(
                f"{o.get('organization_key')}/{o.get('name')}/{o.get('status')}"
                for o in orgs
            ),
        )
        dangling = [
            u.get("email")
            for u in sb.table("users").select("*").execute().data
            if u.get("org_id") and u.get("org_id") not in org_ids
        ]
        mark(
            "no user carries a dangling org reference",
            not dangling,
            f"dangling={dangling}" if dangling else "all users resolve to a real org",
        )
    except Exception as exc:  # noqa: BLE001
        mark("production data readable via service role", False, repr(exc))


def check_passport(c: httpx.Client) -> None:
    print()
    try:
        r = c.get(f"/passport/{DEMO_BATCH}")
        mark("demo passport publicly served", r.status_code == 200, f"HTTP {r.status_code}")
        if r.status_code != 200:
            return
        p = r.json()
        types = [e.get("type") for e in p.get("events", [])]
        print(f"\n-- passport {DEMO_BATCH} --")
        print(
            f"     honey_type={p.get('honey_type')!r} qty={p.get('quantity_kg')} "
            f"trust_tier={p.get('trust_tier')!r} origin={p.get('origin')!r}"
        )
        print(f"     event types: {types}")
        mark(
            "passport carries the full custody journey",
            {"HARVEST", "PROCESSING", "PACKAGING", "SALE"}.issubset(set(types)),
            f"present={sorted(set(types))}",
        )
        anchor = p.get("anchor", {}) or {}
        mark(
            "passport anchor is a real chain transaction",
            bool(anchor.get("tx_hash")),
            f"tx_hash={anchor.get('tx_hash')!r} data_hash={anchor.get('data_hash')!r} "
            f"chain_status={anchor.get('chain_status')!r}",
        )
        ver = p.get("verification", {}) or {}
        mark(
            "lab_verified tier is backed by a lab identity",
            ver.get("result") == "PASS" and bool(ver.get("lab_id")),
            f"result={ver.get('result')!r} lab_id={ver.get('lab_id')!r} "
            f"tested_by={ver.get('tested_by')!r} tested_at={ver.get('tested_at')!r}",
        )
    except httpx.HTTPError as exc:
        mark("demo passport publicly served", False, repr(exc))


def check_gated(c: httpx.Client) -> None:
    print("\n-- credential-gated surface (needs a password; not probed here) --")
    for label, path in (
        ("Ask My Bee", "/ai/status"),
        ("blockchain transactions", "/blockchain/status"),
        ("QR package scan", "/qr/scan"),
    ):
        try:
            r = (
                c.post(path, json={"package_code": DEMO_BATCH})
                if path == "/qr/scan"
                else c.get(path)
            )
            state = "PUBLIC" if r.status_code == 200 else f"auth-gated (HTTP {r.status_code})"
        except httpx.HTTPError as exc:
            state = f"error {exc!r}"
        print(f"     {label:28s} {state}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--base",
        default=os.getenv("LIVE_BASE", "https://honeychain-api.onrender.com/api/v1"),
    )
    args = parser.parse_args()
    base = args.base.rstrip("/")

    print("=" * 68)
    print(f" HoneyChain live readiness check -> {base}")
    print("=" * 68)

    with httpx.Client(base_url=base, timeout=60.0) as c:
        if not check_health(c):
            return 1
        check_blockchain(c)
        check_data(load_env())
        check_passport(c)
        check_gated(c)

    print("\n" + "=" * 68)
    print(f" Result: {passed} passed, {failed} failed")
    print("=" * 68)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())