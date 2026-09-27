# Demo Guide

Run the demo end-to-end with the local dev ledger and in-memory repository.

## Start

```bash
cd backend
..\.venv_backend\Scripts\uvicorn app.main:app --port 8000
```

Open `http://localhost:8000/docs`. Demo identity:
`demo@honeychain.in` / `<DEMO_PASSWORD>` (beekeeper, ORG-TN-001). Set the password only in the local backend environment and, when using the optional Flutter demo helper, pass the same value with `--dart-define=DEMO_PASSWORD=...`.

## Scripted walkthrough

1. **Login** → get a JWT (beekeeper). Or use test tokens:
   - fpo: role `fpo`, org `ORG-TN-001`
   - lab: role `lab`, org `LAB-TN-001`
   - admin: role `admin`
2. **Evidence bundle**: `POST /evidence/bundles` with
   `{entity_type:"harvest", entity_ref:"HARV-1", evidence:[{kind:"gps",...}]}`.
   Note `anchor.state == "CONFIRMED"` (local ledger).
3. **Verify**: `POST /evidence/bundles/{id}/verify` → `evidence_intact: true`.
4. **Tamper demo** (admin + non-prod): `POST /admin/tamper/ledger/HARV-1/0`
   then re-run the matching ledger verify → `integrity_ok: false`; or corrupt
   bundle rows directly → `verify` reports `evidence_intact: false`.
5. **Certificate**: as lab `POST /certificates/issue` →
   `GET /certificates/verify/{id}` = `verified:true`; then revoke and re-verify
   → `verified:false, reasons:["certificate is revoked"]`.
6. **State machine**: `POST /batches/transition` fpo moves
   `created → processing` (ok) and `retail → created` (400 illegal).
7. **Lineage + ledger integrity**: `GET /batches/{id}/lineage` shows genealogy
   plus `ledger.integrity_ok`.
8. **RBAC**: a `beekeeper` calling `/certificates/issue` or
   `/batches/transition` gets 403.
9. **Blockchain status**: `GET /blockchain/status` reports
   `ledger: "local"` — never confused with a real chain.

## What the demo intentionally does NOT show

- Fabric/EVM "success" (there is no network) — status codes are honest.
- Claims of "AI-trained" disease detection beyond the rule-based risk engine.
- Passwords/keys except the documented demo one.