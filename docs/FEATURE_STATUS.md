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
| Fabric adapter boundary | ✅ | real EC2 Fabric proven live (see evidence) — committed tx + read-back |
| Batch lineage + state machine | ✅ | transitions, custody holder, genealogy; tests |
| Lab certificate issue/verify/revoke | ✅ | content-hash anchor + revocation; tests |
| Lab test lifecycle (requested → in progress → result) | ✅ | `lab_service` + `GET /labs`, `POST /labs/tests/{id}/start`; `test_lab_workflow.py` |
| Batch provenance aggregation | ✅ | `GET /batches/{id}/provenance`; `test_batch_provenance.py` |
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
| Production repository guard | ✅ | missing `SUPABASE_URL` / service-role key raises in production instead of silently serving demo data; `test_production_repository_guard.py` |
| Workflow notifications from write paths | ✅ | harvest / batch / custody / lab emit from the SAME write that changed state; `test_workflow_notifications.py` |

## P2 — Smart beekeeping / ML

| Feature | Status | Notes |
|---|---|---|
| Hive Intelligence risk engine | ⚠️ | **rule-based**, not a trained neural net |
| ML artifacts (`ml/`) | ⚠️ | `model.pkl`/metrics are **demo artifacts**; verified we will not claim trained accuracy |
| Disease screening from photos | ⚠️ | demo/simulated path only; honest "unable to assess" |

## P3 — Flutter app (beekeeper portal) — 2026-09-11

| Feature | Status | Notes |
|---|---|---|
| Offline-first local store + durable sync queue | ✅ | `flutter test` covers queue, retries, restart durability, no-duplicate push |
| Backend sign-in (`API_BASE_URL` build flag) | ✅ | queue guard-tested; live E2E from device NOT TESTED |
| Server hives/harvests in My Hives + create hive → backend | ✅ | `honey_api_service` (MockClient tests) |
| Record harvest → push + Fabric-anchored evidence bundle | ✅ | honest "anchor pending" when backend unreachable |
| Live chain status card (Blockchain screen) | ✅ | `/health` + `/status` + on-chain verify |
| Trace QR + Honey Passport (trust tiers, caveats) | ✅ | plain `honeychain://` scheme; **not** crypto-signed |
| Ask HoneyChain (voice + manual fallback) | ✅ | Web Speech on web, honest heuristics; never fakes audio |
| Android debug APK / release APK | ✅ / ⚠️ | built; release is **debug-signed** (not store-ready) |

## Blocked / not done (explicitly)

| Item | Blocker |
|---|---|
| Live writes to hosted Supabase | no `SUPABASE_SERVICE_ROLE_KEY` provided |
| EVM anchoring on a real network | no RPC+wallet+deployed contract |
| Public (non-tunnel) Fabric access | EC2 security group does not open gateway port 9446; no AWS CLI available to change it |
| Docker-built images | Docker daemon not running |
| Real-device camera/QR/voice | no device access in this environment |

Hyperledger Fabric anchoring **is** live: the EC2 network (`mychannel`/`honeychain` v2.0)
was anchored through the full backend stack and verified by read-back this session
(`docs/evidence/live-fabric-backend-proof.md`).

## Test inventory

- Backend `pytest`: **157 passed, 3 LIVE_RUNTIME skipped** by default; with the
  EC2 gateway reachable, all 3 LIVE_RUNTIME tests **pass against real Fabric**.
- Flutter `flutter test`: **64 passed** (no regression).
- `test_fabric_adapter.py`: 25 UNIT (mocked HTTP) + 3 LIVE_RUNTIME (real ledger).

New coverage added this session:
`test_crypto`, `test_merkle`, `test_event_ledger`, `test_evidence`,
`test_certificates`, `test_lineage`, `test_gateway`, `test_rbac_matrix`,
`test_new_routes`.