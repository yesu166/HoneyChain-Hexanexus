"""Surgical demo-data cleanup for the live Supabase project.

Default mode is DRY-RUN (prints exactly what would be deleted). Pass --apply to
execute. Deletes ONLY confirmed automation artifacts and duplicate seed shells:

  * duplicate "Nilgiris Honey FPO" seed orgs (keeps ORG-000001, the tenant that
    actually owns the demo accounts and the HC-2026-DEMO-001 batch)
  * the empty ORG-000010 shell
  * "HoneyChain E2E Fabric Proof <ts>" orgs left by local E2E runs
  * pattern-matched automation users/batches (e2e-*, devbee*, askbee_e2e_*,
    sprint-*, audit-*, ci.probe*, bk-test*, fpo-e2e-*, *@honeychain-test.com,
    *@honeychain.dev, *@example.in, *@example.com, E2E-B-*, HC-E2E-*)

Real demo accounts (admin@/demo@/fpo@/lab@/processor@/buyer@honeychain.in) and
human-looking accounts are never touched.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

APPLY = "--apply" in sys.argv

ROOT = Path(__file__).resolve().parent
while not (ROOT / ".env").exists() and ROOT.parent != ROOT:
    ROOT = ROOT.parent

env: dict[str, str] = {}
for raw in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    env[k.strip()] = v.strip().strip('"').strip("'")

from supabase import create_client  # noqa: E402

client = create_client(env["SUPABASE_URL"], env["SUPABASE_SERVICE_ROLE_KEY"])

KEEP_ORG_KEY = "ORG-000001"

KEEP_EMAILS = {
    "admin@honeychain.in",
    "demo@honeychain.in",
    "fpo@honeychain.in",
    "lab@honeychain.in",
    "processor@honeychain.in",
    "buyer@honeychain.in",
}

USER_PATTERNS = [
    re.compile(r"^e2e", re.I),
    re.compile(r"e2e[-_.]", re.I),
    re.compile(r"^devbee", re.I),
    re.compile(r"^askbee_e2e", re.I),
    re.compile(r"^sprint[-_]", re.I),
    re.compile(r"^audit-", re.I),
    re.compile(r"^ci\.probe", re.I),
    re.compile(r"^bk-test", re.I),
    re.compile(r"^fpo-e2e", re.I),
    re.compile(r"^testbeekeeper", re.I),
    re.compile(r"^testuser", re.I),
    re.compile(r"^newbeek", re.I),
    re.compile(r"@test\.com$", re.I),
    re.compile(r"@honeychain-test\.com$", re.I),
    re.compile(r"@honeychain\.dev$", re.I),
    re.compile(r"@example\.(in|com)$", re.I),
]

BATCH_PATTERNS = [
    re.compile(r"^E2E[-_]", re.I),
    re.compile(r"^HC-E2E", re.I),
    re.compile(r"^SPRINT[-_]", re.I),
]


def is_test_email(email: str | None) -> bool:
    if not email:
        return False
    if email.lower() in KEEP_EMAILS:
        return False
    return any(p.search(email) for p in USER_PATTERNS)


def is_test_batch(code: str | None) -> bool:
    if not code:
        return False
    return any(p.search(code) for p in BATCH_PATTERNS)


def rows(table: str, select: str = "*") -> list[dict]:
    return client.table(table).select(select).limit(5000).execute().data


# ---------------------------------------------------------------- organise
orgs = rows("organizations")
dup_keys = {f"ORG-0000{n:02d}" for n in range(2, 11)}
doomed_orgs = [
    o
    for o in orgs
    if o.get("organization_key") in dup_keys
    or (o.get("name") or "").startswith("HoneyChain E2E Fabric Proof")
]
doomed_org_ids = {o["id"] for o in doomed_orgs}

users = rows("users", "id,email,role,org_id")
doomed_users = [u for u in users if is_test_email(u.get("email"))]
doomed_user_ids = {u["id"] for u in doomed_users}

# batches FIRST — beekeeper/hive deletion must not orphan a batch we keep.
batches = rows("batches", "id,batch_code,organization_id,beekeeper_id")
doomed_batches = [
    b
    for b in batches
    if is_test_batch(b.get("batch_code"))
    or b.get("organization_id") in doomed_org_ids
]
doomed_batch_ids = {b["id"] for b in doomed_batches}

# any beekeeper still referenced by a batch we KEEP must survive, otherwise the
# demo batch would be left pointing at a deleted row.
kept_batch_bk_ids = {
    b["beekeeper_id"]
    for b in batches
    if b["id"] not in doomed_batch_ids and b.get("beekeeper_id")
}

beekeepers = rows("beekeepers", "id,name,organization_id")
doomed_bks = [
    b
    for b in beekeepers
    if b.get("organization_id") in doomed_org_ids and b["id"] not in kept_batch_bk_ids
]
doomed_bk_ids = {b["id"] for b in doomed_bks}
pinned = [
    b
    for b in beekeepers
    if b.get("organization_id") in doomed_org_ids and b["id"] in kept_batch_bk_ids
]

hives = rows("hives", "id,hive_code,beekeeper_id")
doomed_hives = [h for h in hives if h.get("beekeeper_id") in doomed_bk_ids]
doomed_hive_ids = {h["id"] for h in doomed_hives}

# ---------------------------------------------------------------- report
print(f"KEEP org: {KEEP_ORG_KEY} (the tenant that owns the demo accounts)")
print(f"\nORGS to delete ({len(doomed_orgs)}):")
for o in sorted(doomed_orgs, key=lambda x: x.get("organization_key") or ""):
    print(f"  {o.get('organization_key')}  {o.get('name')}")
print(f"\nUSERS to delete ({len(doomed_users)}):")
for u in sorted(doomed_users, key=lambda x: x.get("email") or "")[:200]:
    print(f"  {u.get('email'):48s} {u.get('role')}")
print(f"\nBEEKEEPERS to delete ({len(doomed_bks)}):")
for b in sorted(doomed_bks, key=lambda x: x.get("name") or ""):
    print(f"  {b.get('name')}")
if pinned:
    print(f"\nPINNED beekeepers kept in a doomed org ({len(pinned)}) — will be")
    print("re-homed to ORG-000001 so the kept batch stays valid:")
    for b in pinned:
        print(f"  {b.get('name')}  id={b['id']}")
print(f"\nHIVES to delete ({len(doomed_hives)}): {len(doomed_hive_ids)}")
print(f"BATCHES to delete ({len(doomed_batches)}):")
for b in sorted(doomed_batches, key=lambda x: x.get("batch_code") or ""):
    print(f"  {b.get('batch_code'):28s} org={b.get('organization_id')}")

kept = [u for u in users if not is_test_email(u.get("email"))]
print(f"\nUSERS kept: {len(kept)}")
for u in sorted(kept, key=lambda x: x.get("email") or ""):
    print(f"  {u.get('email'):48s} {u.get('role'):10s} org={u.get('org_id')}")

if not APPLY:
    print("\nDRY RUN — nothing was deleted. Re-run with --apply to execute.")
    sys.exit(0)

print("\n=== APPLYING ===")


def del_where(table: str, column: str, values: set[str]) -> int:
    """Delete rows whose `column` is in `values`. Returns rows removed."""
    if not values:
        return 0
    vals = list(values)
    removed = 0
    for i in range(0, len(vals), 50):
        chunk = vals[i : i + 50]
        try:
            res = (
                client.table(table)
                .delete()
                .in_(column, chunk)
                .execute()
            )
            removed += len(res.data or [])
        except Exception as exc:  # noqa: BLE001
            print(f"  ! {table}.{column}: {type(exc).__name__}: {str(exc)[:110]}")
    print(f"  {table:24s} <-{column:20s} {removed:>5d} rows")
    return removed


doomed_codes = {b["batch_code"] for b in doomed_batches if b.get("batch_code")}
doomed_batch_refs = doomed_batch_ids | doomed_codes

# --- children of doomed batches -------------------------------------------
del_where("qr_codes", "batch_id", doomed_batch_ids)
del_where("custody_events", "batch_id", doomed_batch_ids)
del_where("lab_tests", "batch_id", doomed_batch_ids)
del_where("certificates", "batch_id", doomed_batch_ids)
del_where("blockchain_anchors", "batch_id", doomed_batch_ids)
del_where("batch_harvest_links", "batch_id", doomed_batch_ids)
del_where("batch_genealogy", "parent_batch_id", doomed_batch_ids)
del_where("batch_genealogy", "child_batch_id", doomed_batch_ids)
del_where("passports", "subject_code", doomed_batch_refs)
del_where("evidence_bundles", "entity_ref", doomed_batch_refs)
del_where("ledger_events", "entity_ref", doomed_batch_refs)

# --- children of doomed hives --------------------------------------------
del_where("hive_readings", "hive_id", doomed_hive_ids)
del_where("health_scores", "hive_id", doomed_hive_ids)
del_where("telemetry_events", "hive_id", doomed_hive_ids)
del_where("harvest_events", "hive_id", doomed_hive_ids)

# --- children of doomed beekeepers ---------------------------------------
del_where("harvest_events", "beekeeper_id", doomed_bk_ids)

# --- devices / orgs / invites --------------------------------------------
del_where("iot_devices", "organization_id", doomed_org_ids)
del_where("notifications", "organization_id", doomed_org_ids)

doomed_org_keys = {
    o["organization_key"] for o in doomed_orgs if o.get("organization_key")
}
del_where("organization_invites", "organization_key", doomed_org_keys)

# Re-home any beekeeper a KEPT batch depends on, so deleting the duplicate org
# does not orphan that batch.
keep_org_id = next(
    o["id"] for o in orgs if o.get("organization_key") == KEEP_ORG_KEY
)
for b in pinned:
    client.table("beekeepers").update({"organization_id": keep_org_id}).eq(
        "id", b["id"]
    ).execute()
    print(f"  re-homed {b.get('name')} -> {KEEP_ORG_KEY}")

# --- integrity repair -----------------------------------------------------
# users.org_id must hold an organization UUID. Some accounts (notably
# lab@honeychain.in) were written with a *key* like "LAB-TN-001", which matches
# no organization row and leaves that workspace unable to resolve its tenant.
valid_org_ids = {o["id"] for o in orgs if o["id"] not in doomed_org_ids}
for u in users:
    oid = u.get("org_id")
    if oid and oid not in valid_org_ids and u["id"] not in doomed_user_ids:
        client.table("users").update({"org_id": keep_org_id}).eq(
            "id", u["id"]
        ).execute()
        print(f"  repaired dangling org_id on {u.get('email')} ({oid}) -> {KEEP_ORG_KEY}")

# --- the entities themselves ---------------------------------------------
del_where("batches", "id", doomed_batch_ids)
del_where("hives", "id", doomed_hive_ids)
del_where("beekeepers", "id", doomed_bk_ids)
del_where("profiles", "organization_id", doomed_org_ids)
del_where("users", "id", doomed_user_ids)
del_where("organizations", "id", doomed_org_ids)

print("\n=== POST-STATE ===")
for t in (
    "organizations",
    "users",
    "beekeepers",
    "hives",
    "batches",
    "harvest_events",
    "lab_tests",
    "passports",
    "qr_codes",
):
    n = client.table(t).select("*", count="exact", head=True).execute().count
    print(f"{t:20s} {n}")