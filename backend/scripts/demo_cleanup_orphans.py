"""Round 2: remove orphaned automation beekeepers + their hives.

These rows survived round 1 because they carry organization_id = NULL and so
were not reachable via the duplicate-org sweep. All names matched here are
automation artifacts (E2E / Test / Dev Bee / Sprint / Ask Bee / Audit /
VerifyUser / Iso Tester / RBAC / New Beekeeper).

Real human accounts and the demo's own "Kumar Beekeeper" are preserved.
DRY-RUN by default; pass --apply to execute.
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

c = create_client(env["SUPABASE_URL"], env["SUPABASE_SERVICE_ROLE_KEY"])

AUTO = re.compile(
    r"e2e|test|dev bee|sprint|ask bee|^audit$|verifyuser|iso tester|rbac|new beekeeper",
    re.I,
)


def rows(t: str, sel: str = "*") -> list[dict]:
    return c.table(t).select(sel).limit(5000).execute().data


bks = rows("beekeepers", "id,name,organization_id")
hives = rows("hives", "id,hive_code,beekeeper_id")
batches = rows("batches", "id,batch_code,beekeeper_id")

# never delete a beekeeper a surviving batch points at
protected = {b["beekeeper_id"] for b in batches if b.get("beekeeper_id")}

doomed_bks = [
    b
    for b in bks
    if AUTO.search(b.get("name") or "") and b["id"] not in protected
]
doomed_bk_ids = {b["id"] for b in doomed_bks}
doomed_hives = [h for h in hives if h.get("beekeeper_id") in doomed_bk_ids]
doomed_hive_ids = {h["id"] for h in doomed_hives}

print(f"BEEKEEPERS matched for deletion ({len(doomed_bks)}):")
for b in sorted(doomed_bks, key=lambda x: x.get("name") or ""):
    print(f"  {b.get('name'):28s} org={b.get('organization_id')}")
print(f"\nHIVES to delete: {len(doomed_hive_ids)}")

kept = [b for b in bks if b["id"] not in doomed_bk_ids]
print(f"\nBEEKEEPERS kept ({len(kept)}):")
for b in sorted(kept, key=lambda x: x.get("name") or ""):
    print(f"  {b.get('name'):28s} org={b.get('organization_id')}")

if not APPLY:
    print("\nDRY RUN — re-run with --apply to execute.")
    sys.exit(0)


def del_where(table: str, column: str, values: set[str]) -> None:
    if not values:
        print(f"  {table:22s} <-{column:18s} (none)")
        return
    vals = list(values)
    removed = 0
    for i in range(0, len(vals), 50):
        try:
            res = c.table(table).delete().in_(column, vals[i : i + 50]).execute()
            removed += len(res.data or [])
        except Exception as exc:  # noqa: BLE001
            print(f"  ! {table}.{column}: {type(exc).__name__}: {str(exc)[:120]}")
    print(f"  {table:22s} <-{column:18s} {removed:>5d} rows")


print("\n=== APPLYING ===")
del_where("hive_readings", "hive_id", doomed_hive_ids)
del_where("health_scores", "hive_id", doomed_hive_ids)
del_where("telemetry_events", "hive_id", doomed_hive_ids)
del_where("harvest_events", "hive_id", doomed_hive_ids)
del_where("harvest_events", "beekeeper_id", doomed_bk_ids)
del_where("iot_devices", "assigned_hive_id", doomed_hive_ids)
del_where("hives", "id", doomed_hive_ids)
del_where("beekeepers", "id", doomed_bk_ids)

print("\n=== POST-STATE ===")
for t in ("organizations", "users", "beekeepers", "hives", "batches",
          "harvest_events", "passports", "qr_codes", "iot_devices"):
    n = c.table(t).select("*", count="exact", head=True).execute().count
    print(f"{t:20s} {n}")