# Feature Status

Status key: ✅ done+tested · ⚠️ partial (runs but has known limits) · 🚧 boundary only (code exists, real external call blocked) · ⬜ not started.

## P0 — Core provenance (the non-negotiable layer)

| Feature | Status | Notes |
|---|---|---|
| Canonical serialization + SHA-256 hashing | ✅ | `backend/app/core/crypto.py`; tests in `test_crypto.py` |
| ECDSA P-256 actor signatures | ✅ | generate/serialize/sign/verify; tests |
| Merkle bundle root + proofs | ✅ | `backend/app/services/merkle.py`; tests incl. tamper |
| Harvest Evidence Bundle | ✅ | create/verify/proof via `HarvestEvidenceService`; API + tests |
| Offline event ledger (hash-chained) | ✅ | append/verify/tamper-detect; forks preserved → tests |
| BlockchainGateway + tx state machine | ✅ | PENDING/SUBMITTED/CONFIRMED/FAILED/RETRYING/UNKNOWN; tests |
| Local dev ledger | ✅ | `ledger_name == "local"`, honest confirmations |
| EVM adapter boundary | 🚧 | not configured → `BLOCKCHAIN_NOT_CONFIGURED`; tests |
| Fabric adapter boundary | 🚧 | not configured → `FABRIC_NOT_CONFIGURED`; tests |
| Batch lineage + state machine | ✅ | transitions, custody holder, genealogy; tests |
| Lab certificate issue/verify/revoke | ✅ | content-hash anchor + revocation; tests |
| Honey Passport (public, PII-free) | ✅ | pre-existing `passport_service`; existing tests |
| DEMO_MODE tamper gate | ✅ | `/admin/tamper/*` 403 in production; tests |
| RBAC permission matrix | ✅ | `backend/app/core/rbac.py`; matrix + tests |
| Health live/ready | ✅ | `/health/live`, `/health/ready` |

## P1 — Platform correctness

| Feature | Status | Notes |
|---|---|---|
| Offline-first idempotent sync | ✅ | pre-existing `SyncService` (client_id upsert) |
| Supabase schema incl. new tables | ✅ | migrations 001–006 **applied to live project** |
| Backend repository abstraction | ✅ | InMemory + Supabase repositories |
| JWT auth (PBKDF2, HS256) | ✅ | pre-existing; demo identities |
| Trust tiers (weakest-tier merge) | ✅ | pre-existing `batch_service` |
| Rate-limited public passport | ✅ | pre-existing |

## P2 — Smart beekeeping / ML

| Feature | Status | Notes |
|---|---|---|
| Hive Intelligence risk engine | ⚠️ | **rule-based**, not a trained neural net |
| ML artifacts (`ml/`) | ⚠️ | `model.pkl`/metrics are **demo artifacts**; verified we will not claim trained accuracy |
| Disease screening from photos | ⚠️ | demo/simulated path only; honest "unable to assess" |

## Blocked / not done (explicitly)

| Item | Blocker |
|---|---|
| Live writes to hosted Supabase | no `SUPABASE_SERVICE_ROLE_KEY` provided |
| EVM anchoring on a real network | no RPC+wallet+deployed contract |
| Fabric anchoring on a real network | no Fabric network running |
| Docker-built images | Docker daemon not running |
| Real-device camera/QR | no device access in this environment |

## Test inventory (this session — both suites green)

- Backend `pytest`: **110 passed** (was 54 before this session).
- Flutter `flutter test`: **64 passed** (unchanged; no regression).

New coverage added this session:
`test_crypto`, `test_merkle`, `test_event_ledger`, `test_evidence`,
`test_certificates`, `test_lineage`, `test_gateway`, `test_rbac_matrix`,
`test_new_routes`.