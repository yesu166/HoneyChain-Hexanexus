# Service & Component Status (honest)

Every component below reports exactly what it is in this environment. Nothing
is claimed to be running that is not running, and no credential is invented.

Legend:
- **LIVE** — verified working, real execution verified in this session.
- **SIMULATED/LOCAL** — real code path, but backed by an in-process substitute
  that is explicitly labeled and never presented as production.
- **NOT_CONNECTED** — real integration exists as code but the target service
  has not authenticated/wired up.
- **BLOCKED** — cannot be completed without a credential or infra this
  environment does not have.

## Reality matrix (updated this session)

| Thing | State | Evidence | What that means |
|---|---|---|---|
| Flutter app (offline-first) | **LIVE** | `flutter test` → 64 passed | Demo app + local store works |
| FastAPI backend | **LIVE** | `pytest` → 110 passed | All business logic + API surfaces tested |
| Supabase PostgreSQL | **LIVE database connection + migrations applied** | `npm run apply` → 001–006 all OK vs `db.hhxwhopaazqjdlreqhkf.supabase.co` | Real schema deployed, incl. evidence/ledger/cert table (migration 006) |
| Supabase auth (JWT) | **NOT_CONNECTED for backend writes** | no `SUPABASE_SERVICE_ROLE_KEY` provided | Backend runs on `DemoSeededRepository` (in-memory) by design |
| Blockchain adapter (local) | **SIMULATED/LOCAL** | gateway `ledger_name == "local"` | In-process dev ledger; honest `CONFIRMED` only on local commits |
| EVM adapter | **BLOCKCHAIN_NOT_CONFIGURED** | no RPC w/ credentials | Boundary code only; live submission requires wallet + contract |
| Hyperledger Fabric | **FABRIC_NOT_CONFIGURED** | `FabricBlockchainAdapter` raises honest status | Boundary code only; no Fabric network running |
| Hive Intelligence (risk engine) | **LIVE (rule-based)** | existing `risk_engine_adapter` | Explicitly NOT a trained model; ML artifacts are demo artifacts |
| Docker daemon | **NOT RUNNING** | `docker info` fails | Cannot build/publish containers from this shell |
| `supabase` CLI | **NOT INSTALLED** | — | Use `node supabase/scripts/apply_migrations.js` instead |

## Blockchain status codes used by the gateway

These statuses are returned verbatim by the gateway and surfaced by the API:

| Code | Meaning |
|---|---|
| `PENDING` | transaction accepted by gateway, not yet submitted |
| `SUBMITTED` | handed to ledger adapter, awaiting confirmation |
| `CONFIRMED` | ledger confirmed the commitment (local ledger for dev) |
| `FAILED` | submission failed (e.g. not configured / invalid) |
| `RETRYING` | a retry was requested and is allowed |
| `UNKNOWN` | ledger is unreachable / state cannot be determined |
| `NOT_CONFIGURED` | EVM/Fabric path used without credentials |
| `FABRIC_NOT_CONFIGURED` | Fabric selected but no channel/chaincode/network |
| `FABRIC_UNAVAILABLE` | Fabric selected but not reachable at request time |
| `FABRIC_TRANSACTION_FAILED` | Fabric submit failed (reserved, not currently emitted) |

The gateway never fabricates a `CONFIRMED` result. Confirmation comes from a
ledger the code can actually reach.

## Environments

- `API_ENV=development` (default): `/docs` enabled, demo identities seeded,
  tamper endpoints allowed, in-memory repository unless service-role key set.
- `API_ENV=production`: `/docs` disabled, tamper endpoints 403, refuses to
  boot without `JWT_SECRET`, requires service-role key to use Supabase repo.

## Single source of truth

- Docs: `docs/` (this folder)
- Schema: `supabase/migrations/` (applied to the live project)
- Api: `backend/app/api/routes/*.py` + `docs/API.md`