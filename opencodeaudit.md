# Security hardening follow-up — 2026-09-27

The original audit findings below are historical observations. This follow-up
records source-level fixes applied afterward; it does not mean deployment
secrets were rotated automatically.

## Fixed in source

- Removed the published hardcoded JWT development fallback. Missing
  `JWT_SECRET` now uses a fresh process-local cryptographic secret in
  development and refuses startup in production.
- Unknown `API_ENV` values are rejected.
- Removed the hardcoded demo password from backend/Flutter application source,
  simulator text, and public demo documentation. Demo authentication now
  requires `DEMO_PASSWORD` from local/deployment configuration.
- Moved backend JWT/profile persistence from plaintext SharedPreferences to
  `flutter_secure_storage`, with one-time migration and cleanup of legacy
  SharedPreferences copies.
- Removed the committed 74 MB APK artifact.
- Updated security documentation to classify Gemini, Supabase service-role,
  JWT, Fabric bridge, database, blockchain, and demo credentials as
  server-side/environment-only secrets.

## Still requires operator action

1. Rotate any real `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`,
   `SUPABASE_DB_URL` password, Gemini key, Fabric bridge token, blockchain
   private key, or JWT secret that has existed in a shared/local working
   directory. The earlier audit found real values in gitignored `.env` files;
   source changes cannot rotate those credentials.
2. Set a strong `JWT_SECRET` in the Render `honeychain-api` environment.
3. Set `DEMO_PASSWORD` only for intentionally local/demo identities and never
   reuse it for a real account.
4. Review existing Supabase demo users created by the legacy seed migration and
   rotate/delete them if the hosted project is intended for non-demo use.
5. Never put server secrets into Flutter `--dart-define` or Vite `VITE_*`
   variables.

## Verification status

These changes are on branch `security-hardening-2026-09-27`. Tests/builds
have not been run in this pass.

---

# Follow-up — 2026-09-27

This note records changes made after the original audit. The original findings are kept below as historical audit evidence; they are not treated as current truth without re-verification.

## Confirmed fixes in this follow-up

- Batch repository responses now normalize nullable organization_id and client_id to the API schema's string contract on create/read/list/update paths.
- Batch null-contract regression coverage was added alongside the existing hive/harvest coverage.
- Backend pytest now runs in GitHub Actions in addition to the existing Flutter checks.
- A repeatable Windows PowerShell online Android build/install script was added: scripts/build_android_online.ps1. It injects the existing deployed API_BASE_URL at build time; the Flutter application still does not hardcode the backend URL.

## Findings intentionally not changed from source code alone

- Render's live environment secrets (JWT_SECRET, Supabase credentials, Gemini keys) must be verified/rotated in the deployment environment, not committed to Git.
- The deployed blockchain adapter must not be changed to Fabric blindly without verifying the reachable Fabric gateway and its credentials/network.
- JWT secure-storage migration is a separate security hardening task and was not mixed into the API regression/batch fix because changing authentication storage without device verification could break the current login flow.
- Pagination, multi-writer conflict resolution, load testing, and production APK signing remain separate scale/release tasks rather than being silently claimed complete.

## API build truth

The mobile app intentionally requires the existing build-time flag:

--dart-define=API_BASE_URL=https://honeychain-api.onrender.com

A debug APK built without that flag is intentionally an offline/demo build and will show the honest Backend not configured state. This is a build-configuration issue, not a reason to add a hardcoded backend URL to the Flutter source.

# HONEYCHAIN 3.0 — READ-ONLY AUDIT

**Auditor mode:** READ-ONLY. No source file, migration, test, schema, or config was modified. No commit/push performed. One scratch script written to the OS temp dir (outside the repo) and executed; left in place.

---

## 1. EXECUTIVE SUMMARY

HoneyChain is a coherent **modular monolith** (FastAPI) + offline-first **Flutter client** + **adapter-based blockchain boundary** + Node.js Fabric gateway sidecar. The codebase is unusually honest: every ML/blockchain surface either does real work or reports its own unavailability — there is no fabricated success path. The docs match the code.

However, the audit confirms the **client_id-class production bug is NOT fully fixed**: the NULL→"" normalization added to `SupabaseRepository` covers only **hives and harvests**. **Batches were missed.** A live read against production shows `batches` holds 4/15 rows with `client_id = NULL` and **14/15 rows with `organization_id = NULL`**, and `BatchRead` rejects both with a Pydantic `str_type` error (verified by execution against the installed pydantic 2.13). Every batch create/read/list/update/split/merge path against live Supabase therefore returns **HTTP 500**, while all 232 in-memory tests stay green. This is the same failure class the baseline fix claims to have eliminated.

Secondary critical findings: empty `JWT_SECRET` in the live `.env` makes every token sign with the **public literal dev secret**; live Supabase service-role key and direct-DB password sit in untracked `.env` files on disk; telemetry One-Class SVM has **no model artifacts** so anomaly detection is effectively disabled; voice observation is a **stub on Android/native** (web-only); CI runs **Flutter tests only** — no backend tests, no Supabase integration anywhere.

**FINAL STATUS: AUDIT COMPLETE — CRITICAL ISSUES FOUND**

---

## 2. CURRENT IMPLEMENTATION SCORECARD

| Area | State |
|---|---|
| FastAPI monolith (routes/services/schemas/repo) | IMPLEMENTED |
| SupabaseRepository persistence | IMPLEMENTED (batch NULL contract BROKEN) |
| InMemoryRepository | IMPLEMENTED (test/dev path) |
| Auth (PBKDF2 + HS256 JWT, repo-as-system-of-record) | IMPLEMENTED (dev-secret risk) |
| RBAC permission matrix + scope checks | IMPLEMENTED (with gaps) |
| Evidence (canonical hash → SHA-256 → Merkle) | IMPLEMENTED |
| Blockchain gateway (Local/EVM/Fabric adapters) | IMPLEMENTED (local default; Fabric real-but-external) |
| Fabric network + chaincode + gateway service | IMPLEMENTED (not executing in this environment) |
| Offline store + durable sync queue | IMPLEMENTED |
| Honey Passport + QR | IMPLEMENTED (server-generated proof) |
| Consumer cryptographic verification | PARTIAL (server-reported; no client-side recompute) |
| Beekeeper/hive/harvest offline flows | IMPLEMENTED |
| Batch/genealogy/split/merge | IMPLEMENTED in memory — BROKEN vs production |
| Health screening (decision tree) | PARTIAL (real tree, synthetic 40-row prototype, screening only) |
| Voice observation | PARTIAL (web only; native stub) |
| Productivity prediction | PARTIAL (client contract tested; model/API external) |
| Telemetry anomaly (One-Class SVM) | PARTIAL (code real, artifacts absent → disabled) |
| IoT ingest + device signatures | IMPLEMENTED |
| IoT simulator + tamper demo | IMPLEMENTED (demo-mode gated) |
| Localization | PARTIAL (en/ta/hi real; bn/pa/ml/mr stubs) |
| Marketplace | PARTIAL (local listings, no real trading backend) |
| CI/CD | PARTIAL (Flutter-only; no backend CI, release broken) |
| APK build | IMPLEMENTED (debug-signed, `com.example` id) |

---

## 3. FEATURE MATRIX

| Feature | UI | API | Service | DB | Tests | Real E2E | Status |
|---|---|---|---|---|---|---|---|
| Authentication | ✔ | ✔ | ✔ | ✔ | ✔ | ✔* | IMPLEMENTED |
| RBAC | ✔ | ✔ | ✔ | n/a | ✔ | ✔ | IMPLEMENTED |
| Beekeeper | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | IMPLEMENTED |
| Hive creation | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | IMPLEMENTED (post-fix) |
| Hive listing | ✔ | ✔ | ✔ | ✔ | ✔ | ✗** | IMPLEMENTED (post-fix) |
| Hive update | ✔ | ✔ | ✔ | ✔ | ✔ | ✗** | IMPLEMENTED |
| Health screening | ✔ | ✔(rule-based) | ✔ | n/a | ✔ | ✔(on-device tree) | PARTIAL |
| Voice observation | ✔(web)/✗(Android) | ✗ | ✗ | n/a | ✗ | ✗ | PARTIAL |
| Harvest | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | IMPLEMENTED |
| Productivity prediction | ✔ | ✔(external model) | ✗ repo | n/a | ✔(client) | ✗ | PARTIAL |
| Batch creation | ✔ | ✔ | ✔ | ✔ | ✔ | ✗** | BROKEN vs prod |
| Batch genealogy | ✔ | ✔ | ✔ | ✔ | ✔ | ✗** | PARTIAL |
| Split | ✔ | ✔ | ✔ | ✔ | ✔ | ✗** | PARTIAL |
| Merge | ✔ | ✔ | ✔ | ✔ | ✔ | ✗** | PARTIAL |
| Processing | ✔(org portal) | ✔(custody) | ✔ | ✔ | ✔ | ✗ | PARTIAL |
| Laboratory verification | ✔ | ✔ | ✔ | ✔ | ✔ | ✗ | IMPLEMENTED (local) |
| Evidence | ✔ | ✔ | ✔ | ✔ | ✔ | ✔(backend) | IMPLEMENTED |
| SHA-256 / canonical | n/a | n/a | ✔ | n/a | ✔ | ✔ | IMPLEMENTED |
| Merkle | n/a | ✔ | ✔ | n/a | ✔ | ✔ | IMPLEMENTED |
| Blockchain anchoring | ✔ | ✔ | ✔ | ✔ | ✔(local) | ✗(Fabric live) | PARTIAL |
| Fabric | ✔(status) | ✔ | ✔ | n/a | ✔(3 skipped) | ✔* (EC2, external) | PARTIAL |
| Local ledger | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | IMPLEMENTED |
| EVM adapter | ✗ | ✔(stub) | ✔ | n/a | ✗ | ✗ | ADAPTER ONLY |
| QR | ✔ | n/a | ✔ | n/a | ✔ | ✔ | IMPLEMENTED |
| Honey Passport | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | IMPLEMENTED |
| Consumer verification | ✔ | ✔ | ✔(server) | ✔ | ✔ | ✗ | PARTIAL |
| Marketplace | ✔(listings) | ✗ | ✗ | ✗ | ✗ | ✗ | PARTIAL/MOCKED |
| Offline storage | n/a | n/a | ✔ | n/a | ✔ | ✔ | IMPLEMENTED |
| Outbox/sync | ✔ | ✔ | ✔ | ✔ | ✔ | ✗ | IMPLEMENTED (conflicts UNHANDLED) |
| Telemetry | ✔ | ✔ | ✔ | ✔ | ✔ | ✗ | IMPLEMENTED |
| IoT simulator | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | IMPLEMENTED (demo) |
| ML anomaly detection | ✔ | ✔ | ✔(code) | n/a | ✔(fallback only) | ✗ | DISABLED (no artifacts) |
| Localization | ✔ | n/a | n/a | n/a | ✔ | ✔ | PARTIAL |
| CI/CD | n/a | n/a | n/a | n/a | ✔(Flutter only) | ✗ | PARTIAL |
| APK build | n/a | n/a | n/a | n/a | ✔ | ✔(debug) | IMPLEMENTED |

\* Live-run only against the separately-deployed EC2/Supabase environment, not reproducible from this checkout.
\*\* Fails against live Supabase (missing NULL normalization) — see Critical Finding 1.

---

## 4. DATABASE / REPOSITORY CONTRACT FINDINGS

**CRITICAL 1 — Batch NULL normalization is missing (confirmed live).**
- `backend/app/db/supabase.py:1355-1361` `create_batch` → returns `self._upsert(...)` unwrapped; `:1359-1360` explicitly forces `row["organization_id"] = None` when absent; `:1363-1364` `get_batch`, `:1366-1367` `get_batch_by_code`, `:1369-1381` `list_batches`, `:1383-1387` `update_batch` — none apply `_with_client_id` nor normalize `organization_id`.
- InMemoryRepository (`:616-645`) always stores `client_id: ""` strings and empty org strings → parity tests pass.
- Live DB (read-only, service-role key): `hives` 21/31 NULL client_id, `harvest_events` 12/22 NULL, `batches` **4/15 NULL client_id and 14/15 NULL organization_id** (migration `001_initial_schema.sql:124,126` — `quantity_kg` and `organization_id` nullable; seed `004_seed_demo_data.sql:100` creates batches without org id).
- `BatchRead` (`backend/app/schemas/batch.py:43-53`) types `client_id: str = ""` and `organization_id: str = ""` → pydantic 2.13 rejects `None`. **Reproduced live**: `ValidationError: organization_id … string_type, client_id … string_type`.
- Impact: `POST /api/v1/batches` (no client_id), `GET /api/v1/batches`, `GET/PUT /api/v1/batches/{id}`, `split`, `merge` all return HTTP 500 against the real DB while every in-memory test stays green. Split children and merged lots also create batches without client_id (`batch_service.py:302-313, :360-371`).
- The new regression test (`backend/tests/test_client_id_null_contract.py`) **covers only hives and harvests** — batches are absent from the fix and from the test.

### Additional contract findings

1. `ReadingRead` has no `client_id` field but `ReadingCreate` does. Supabase `add_reading` (`supabase.py:1284-1294`) drops it; InMemory keeps it. API-visible shape matches (no field), so harmless — but round-trip asymmetry exists.
2. `HiveUpdate`.`status` accepts any string; DB has no `hives.status` CHECK (verified: none) — no 500, but status values like `Archived` vs `active` are unconstrained. Same for `BatchUpdate.status` vs the DB CHECK `status in ('created','processing','listed','archived')` (`001:122`) — a status outside that set raises a **23514 check violation 500** in production (in-memory accepts anything). Batch service writes only `created` today, but the Flutter org portal "release/processing" flows drive statuses through the local store, not the API — mismatch is latent.
3. `lab_tests.status` CHECK is `'requested','in_progress','passed','failed'` (migration 008:55 adds default `'requested'`); `LabTestRead.status` literal matches. OK.
4. `certificates.status` CHECK `active|revoked` matches `schemas/certificate.py` — need spot check but appears aligned.
5. `passport_service.resolve` reads raw batch rows (NULL org/client_id never surfaced because the payload builder uses `.get(...)` defaults). Passport endpoint is therefore immune to Finding 1 — but `get_batch_by_code` shares the same un-normalized path.
6. `_upsert` (`supabase.py:1768-1795`) strips a missing/empty `client_id` via plain insert so NULL is canonical — consistent with partial unique indexes (`005_idempotent_sync_support.sql:15-24`). Good — but only effective when the write path omits the key (which it does), making the *read* normalization the mandatory contract.

---

## 5. API FINDINGS

- `POST /api/v1/hives` (201), `POST /harvests` (201), `POST /batches` (201) — create/read asymmetry: hives/harvests now normalized; batches not (see §4).
- `GET /evidence/bundles/{id}/verify` (`evidence.py:61-71`) and `POST /evidence/proof/...` and `POST /evidence/verify-proof` are **unauthenticated** (no `get_current_user`). Verify is a read-compute; acceptable for consumer flows but un-rate-limited and calls `gateway.verify_anchor` live on Fabric — a cheap but useful DoS surface.
- `POST /evidence/bundles` scopes **only** `entity_type=="batch"` (`evidence.py:21-28`). Anchoring a bundle over a **foreign harvest ref** is allowed for any authenticated user — no ownership check for `harvest`, `product`, `jar` entity types. Moderate IDOR/ledge-pollution risk.
- `GET /evidence/bundles/{id}` enforces scope only for batch type; a harvest bundle of another user is visible if you guess the 12-hex bundle id.
- `POST /api/v1/batches/{batch_id}/lab-test` returns `dict` with a `201` but no response model (fine) — however `labs.request_test` does **not** check whether the requesting batch already has an open test → duplicate request rows possible (no idempotency key).
- `sync/push` limit 500 items per request (`sync.py:18`); per-item `SyncItem` schema validation — rejected items produce explicit acks. Well designed.
- `PAGINATION`: `list_harvests`, `list_hives`, `list_batches`, notifications all return unbounded lists (no limit/offset); `list_readings` has `limit=100`. In a growing production DB this will degrade → no pagination on the four main lists.
- Error handling is generally honest: `409` for scope/mass-balance conflicts, `404` for missing rows, `403` for role gaps. The ResponseValidationError class (creating `500` from NULL rows) is the systemic one.

---

## 6. AUTH / RBAC FINDINGS

- `register` (`auth.py:36-43`) is restricted by regex to `beekeeper|fpo|lab|processor|buyer` (`schemas/auth.py:43`) — **admin/institution not self-servable**. FPO requires a platform-issued invite (`auth_service.py:102-120`). Good.
- `get_current_user` (`core/security.py:115-162`) resolves role/org from the **repository as system of record** when the JWT subject is a UUID; `SUSPENDED` → 403. Suspension/role-revocation therefore takes effect on next request. Good.
- **Gap:** non-UUID subjects bypass the repo lookup entirely (`security.py:137-147`) and are trusted as claim-role tokens. Combined with (a) the public dev signing secret (see Security finding) and (b) tokens minted for `sub="demo-beekeeper-id"` etc. in tests, any actor signing with the dev secret can be any role. Only invariant that protects prod is a real `JWT_SECRET`.
- Beekeeper/harvest/batch ownership: `HiveService.get_for_user`/`HarvestService.get_for_user` check `beekeeper_id` or org membership (`hive_service.py:26-39`, `harvest_service.py:32-43`). Batch scope uses org/custody-recipient logic (`batch_service.py:149-190`). Solid.
- `labs.py` enforces lab scoping: lab may only service own org queue (`:15-19`) and own tests (`:46-48`). Good.
- `platform_orgs.py` gates on `membership.*`/`admin.audit` permissions with audit-window clamp `1-500`. Good.
- Role-scope inconsistency: `BATCH_MANAGERS = ("fpo","processor","admin","institution")` — a **buyer** can `PUT /batches/{id}` (any non-status field) because `update_batch` (`batches.py:59-74`) only requires `get_current_user`, barriers only on `status` changes. Buyers can edit `honey_type`/`origin` on any batch they can view. Minor authorization over-reach.

---

## 7. OFFLINE / SYNC FINDINGS

| Scenario | Classification |
|---|---|
| App loses internet during create | IMPLEMENTED — local write first, `SyncStatus.pending`, `SyncEngine` drains when online (`honeychain_store.dart:796-846,1665-1713`) |
| Request succeeds but response lost | PARTIAL — idempotent by `client_id` (partial unique indexes + select-then-insert fallback); retry returns the stored row, but the retry returns "exists" without the backend id in some paths |
| Request retried | IMPLEMENTED — `client_id` dedupe on both gateways; `_knownAccepted` replay set in FastAPI gateway |
| Same event submitted twice | IMPLEMENTED — `_upsert` on-conflict + `find_by_client_id` service short-circuit |
| Device reconnects | IMPLEMENTED — queue drained; attempts/errors persisted across restart; manual `syncPendingNow()` |
| Backend unavailable | IMPLEMENTED — queue retained, attempts counted, `failed` state, no data loss |
| DB write succeeds, blockchain anchoring fails | IMPLEMENTED — `submit_anchor` cannot raise; failure recorded as `pending`/FAILED via `TransactionTracker`; bundle persisted with honest anchor state (`evidence_service.py:118-141`, `gateway.py` `_run`); retry endpoint exists |
| **Conflict: two devices edit same record with different client_ids** | **UNHANDLED** — no last-write-wins/merge policy; documented limitation |
| OS-level background retry when app is closed | NOT IMPLEMENTED (relaunch/manual only) |

Net: idempotent network sync, **not** offline replication with conflict resolution. `sync/push` requires live backend. True offline-first for hives/harvests/batches is local-only and converges by dedupe, not by reconciliation of divergent edits.

---

## 8. ML FINDINGS

**Health screening (DecisionTreeClassifier on-device)** — REAL code, SYNTHETIC PROTOTYPE data.
- `ml/train.py` + `ml/data/honeychain_bee_health_final_demo_dataset.csv` (40 rows, every row `SYNTHETIC_PROTOTYPE`, labels "Claude/Gemini prototype synthesis").
- Artifacts committed: `ml/artifacts/model.pkl` (+ metadata/metrics/inference_checks). Test accuracy 0.667, CV-mean 0.85, macro-F1 0.6, dummy 0.25.
- In-app path: exported to `lib/bee_health/data/generated_bee_health_model.dart` (DEMO/PROTOTYPE header) → `bee_health_prediction_service.dart` + `bee_health_question_engine.dart`.
- Consistently documented as **screening, not diagnosis**; backend never certifies health. Correct posture.
- Security note: committed `model.pkl` is pickle (3.7 KB, trusted repo; no runtime loader in the backend).

**Productivity (ExtraTreesRegressor)** — PARTIAL/EXTERNAL.
- Training included in `ml/train.py`; model artifact `honey_productivity_model.joblib` and the FastAPI `productivity_api.py`/predict endpoint **do not exist in this repo**. Client (`lib/services/productivity_service.dart`) tests the request/response contract against a mock; real path unavailable from checkout.

**Telemetry anomaly (One-Class SVM)** — REAL code, artifacts ABSENT.
- `backend/app/services/honeychain_ml_service.py`: 28 features, warm-up <8, `STRONG_Z=3.0`, `MODERATE_Z=2.0`, status machine (NORMAL/MONITOR/CHECK_HIVE/HIGH_ATTENTION); honest `ml_available=False`, `score=None` when `ml/models_honeychain_event/*.joblib` missing.
- Confirmed `ml/models_honeychain_event/` **does not exist** in the repo (`Test-Path` False). The only real-inference ML test is skipped (`test_honeychain_ml_service.py:46-53`, 1 of the 4 skips).
- **Effective status: DISABLED.** Any telemetry ML claim in the SIH demo is false unless artifacts are onboarded. Fallback: sensor-fault/warm-up only.
- Risk-rule engine `risk_engine_adapter.py` (temp 18–36°C band, humidity 35–80%) is real but is **rules, not AI**.

---

## 9. BLOCKCHAIN / EVIDENCE FINDINGS

Trace: evidence → canonical serialization (`core/crypto.py`) → SHA-256 leaf → `MerkleTree` (`merkle.py`) → `blockchain.py gateway` → adapter → DB anchor — **cryptographically real end-to-end for batch bundles**.

- Adapters: `LocalLedgerAdapter` (dev, labels its own output, `gateway.py:6`), `EVMBlockchainAdapter` (reports `BLOCKCHAIN_NOT_CONFIGURED` until RPC configured), `FabricBlockchainAdapter` (live HTTPS to Node gateway; honest `FABRIC_UNAVAILABLE`).
- **Default in this checkout:** `BLOCKCHAIN_ADAPTER=local` and `AI_ADAPTER=risk_engine` in `backend/.env`. The live Fabric anchor proof (`docs/evidence/live-fabric-backend-proof.md`, block 41→42 on EC2) exists as documentation of a *separate* run, not reproducible here. 3 Fabric `TestLiveFabricRuntime` tests are skipped (`test_fabric_adapter.py`, `skipif not settings.fabric_gateway_url`).
- Anchor persistence → `blockchain_anchors` only for `entity_type=="batch"` (`evidence_service.py:126-137`). **Harvest-level evidence bundles are NOT anchored to the anchor table** (only in the bundle JSON) — a documented gap, and `seed 004` inserts a demo anchor with `network='simulated'` + `status='confirmed'` that a naive DB read would misread as real.
- Read-back verification exists: `verify_bundle` recomputes the Merkle root and, when `ledger_name=="fabric"`, live-verifies against chaincode (`evidence_service.py:230-243`). "Never trust the stored anchor copy alone" is implemented.
- Idempotency: deterministic `tx_ref = hash_payload(...)[:40]`; CONFIRMED reuse; chaincode `AnchorEvidence` returns "already-anchored". State machine (`state.py`) honors PENDING→CONFIRMED only on real confirmation.
- Fabric network (`fabric/`) is a standard 2.5 definition, "NOT EXECUTED in this environment" (`fabric/README.md`). Deployed chaincode on EC2 is `honeychain` v2.0 — **different** from the repo-local `tracer` chaincode.

**Do not claim "live blockchain" in the demo** unless the EC2 gateway is reachable; otherwise it is a local/dev ledger (honestly labeled `LOCAL-...`).

---

## 10. PASSPORT / QR FINDINGS

- QR generation: `qr_flutter`, payload `honeychain://trace/<code>` / `honeychain://jar/<id>` (`trace_qr_service.dart`, `widgets/product_qr.dart`). Real.
- Passport resolution: `GET /api/v1/passport/{code}` (public, rate-limited, PII-free) rebuilds the payload from live records every call (`passport_service.py:29-48`), includes HARVEST events, custody, `QUALITY_TEST` from latest passed test, and ANCHOR only when `chain_status=="anchored"`.
- **What the consumer UI proves:** the backend states `anchor{data_hash, tx_hash, chain_status}` and the app renders verified/pending/none with honest caveats (`passport_verification_service.dart:158-181`). There is **NO client-side recompute** of evidence → Merkle → Fabric comparison in the QR scan path. `canonicalProofJson` exists only to prove app↔server agreement in tests.
- The full chain QR → resolve → recompute canonical evidence → SHA-256 → Merkle → Fabric anchor compare → VERIFIED **exists only on the backend** via `POST /evidence/bundles/{id}/verify`, and it is not wired into the consumer QR scan. Missing step: **consumer-facing cryptographic verification** (client-side or dedicated verify-endpoint chained from QR).

---

## 11. SECURITY FINDINGS  (values NOT displayed)

1. **SECRET FOUND — VALUE NOT DISPLAYED:** `backend/.env` contains a live `SUPABASE_SERVICE_ROLE_KEY` (219-char JWT) and `SUPABASE_ANON_KEY`. Service-role key = full DB control (RLS bypass). It is gitignored but present in the working tree; any folder copy/share leaks it.
2. **SECRET FOUND — VALUE NOT DISPLAYED:** root `.env` `SUPABASE_DB_URL` (direct Postgres password) and `supabase/scripts/.env` (same style). Gitignored.
3. **Empty `JWT_SECRET` in `backend/.env`** → every token in the live config signs with the hardcoded literal `"honeychain-local-dev-secret-do-not-use-in-production"` (`config.py:79`). Guard only triggers when `api_env == "production"` exactly and secret set. A deployment running `development` (or a misspelled env) is forgeable-admin. **HIGH.**
4. Demo password `HoneyChainDemo!1` is hardcoded in `auth_service.py:13`, `conftest.py:30`, and seeded bcrypt in migration `004`. Constraint: demo creds are also real creds for the seeded `auth.users` rows in the live project (via migration). Rotation required before real deployment.
5. JWT/session material persisted in plain SharedPreferences (`honey.apiToken`, `honey.apiIdentity` via `api_token_store.dart`) — no secure storage dependency in `pubspec.yaml`. Device-theft risk.
6. `iot_devices.device_private_key_pem DEFAULT ''` (migration `007`) stores device private keys at rest in Postgres — design trade-off; acceptable for simulator, must be reconsidered for physical devices.
7. Infrastructure disclosure in committed docs: EC2 public IP `13.127.118.165`, instance ID `i-06063debd27c12e51`, Supabase project ref `hhxwhopaazqjdlreqhkf` (in `.env.example`) — reconnaissance value.
8. Committed binary `releases/HoneyChain-v2.0.2.apk` (74 MB) contains the Supabase **anon** key and project ref (expected for any Supabase client) but contributes repo bloat and a distribution surface. The `release` build type is **debug-signed** and package id is `com.example.honeychain` (`android/app/build.gradle.kts`) — not store-distributable.
9. CORS is empty (`CORS_ORIGINS` blank) → middleware simply not added (`main.py:92-99`). Safe for a mobile client; blocks browser cross-origin by default. Fine.
10. `/docs` OpenAPI UI is disabled in production (`main.py:45`). Good.

No SQL-injection risk observed: repo uses supabase-py parameterized helpers throughout; no raw SQL in the backend (migration RPC `_next_organization_key` is the only external-function dependency, and its SQL lives outside this checkout).

---

## 12. TEST QUALITY FINDINGS

- Backend 232 passed / 4 skipped (baseline; consistent with test modules present — 236 `def test_` in 30 files). **Every functional test runs against `InMemoryRepository`** (`conftest.py:7-25` pins SUPABASE vars empty, `BLOCKCHAIN_ADAPTER=simulated`). The batch NULL bug is invisible to this suite by construction.
- 3 Fabric skips = `TestLiveFabricRuntime` (`skipif no fabric_gateway_url`); 1 ML skip = real-model inference (artifacts absent). All 4 skips correctly gated.
- **NO live-Supabase integration test exists in the suite or in CI.** The "232 tests green" do not exercise: RLS, `_next_organization_key` RPC, upsert-on-conflict behavior, uuid `beekeeper_id` writes, or NULL round-trips.
- `test_fabric_adapter.py` imports/behaviour reference the old standalone `fabric_adapter.py`/`simulated_adapter.py` module names that no longer exist (consolidated into `gateway.py`) — stale-test smell; the live-runtime section still works but the module-level expectations are legacy.
- Flutter: 141 passed, analyze clean; ~22 `_test.dart` files, 3 of them (`portal_flow_test`, `iot_simulator_screen_test`, `responsive_smoke_test`) contain **0 `test(` cases**.
- Careful-integrity tests are real and strong: `test_isolation.py` (cross-tenant 404/403/409), `test_mass_balance.py`, `test_client_id_null_contract.py`, `test_trust_architecture.py`.
- **False-confidence areas:** DB contract (this audit), blockchain live path, ML real-model path, API response validation against NULLs, sync under conflict.

---

## 13. CI/CD FINDINGS

- Single workflow: `.github/workflows/dart.yml` (Flutter CI) — checkout → flutter stable → `pub get` → `analyze` → `test` → `build apk --debug`.
- **No backend job.** PyJWT/FastAPI/pytest never run in CI; the 232 backend tests are local-only.
- No release build, no signing, no deployment, no artifact upload, no secrets/env — the workflow proves only "a clean checkout of the Flutter app analyzes/tests/assembles a debug APK."
- No scheduled runs; no live-environment smoke test.

---

## 14. DEMO READINESS

| Item | Status | Note |
|---|---|---|
| Login | GREEN | works locally and against live Supabase users (in-memory or live) |
| Hive creation | GREEN | in-memory/local guaranteed; live post-fix |
| Hive listing | GREEN (local) / YELLOW (live) | fixed for hives/harvests; live read now normalizes |
| Health screening | GREEN | on-device tree + caveats; works offline; prototype data |
| Harvest | GREEN (local) / YELLOW (live) | fixed |
| Productivity | RED | model + endpoint external; only mock-tested |
| Batch | RED (live) | 500s on NULL client_id/org — demo must use local mode only |
| Genealogy | YELLOW | local OK; live blocked by batch 500 |
| Split/Merge | YELLOW | local OK; live blocked by batch 500 |
| Lab | YELLOW | endpoint exists; live lab queue depends on org scope mapping |
| Evidence bundles | GREEN (local) / YELLOW (Fabric) | merkle real; anchor falls back to LOCAL-* |
| Blockchain | RED | local ledger unless EC2/gateway reachable; 3 live tests skipped |
| Passport | GREEN | server-rebuilt, rate-limited |
| QR | GREEN | generation + scan + server proof |
| Consumer verification | YELLOW | server-reported anchor only; no recompute client-side |
| Offline | GREEN | durable store + queue |
| Sync | YELLOW | idempotent; conflicts unhandled; requires network |

---

## 15. SIH SAFE CLAIMS

- Offline-first beekeeper app: hive/harvest/batch records persist locally and sync idempotently by stable client id.
- Working FastAPI modular-monolith backend with one domain model, service/repository layer, 18 routers, real auth (PBKDF2), server-enforced RBAC.
- Cryptographic evidence: canonical serialization → SHA-256 → Merkle root → anchor.
- Honest adapter architecture: Local / EVM / Fabric with truthful status; never fabricates confirmation.
- On-device health **screening** guidance (decision tree prototype) clearly labeled non-diagnostic.
- Honey Passport: public, PII-free, rebuilt from live records, reports tamper-evidence not purity.
- Backend/server-verified evidence bundles with Merkle recompute.
- 373 tests green + Flutter analyze clean (with the explicit in-memory/simulated caveat).
- Seven-language UI scaffolding (3 fully translated).

## 16. SIH CLAIMS TO AVOID

- ❌ "Blockchain-backed honey" / "blockchain proves purity/origin" (tamper-evidence only; `blockchain_anchors` seeded demo rows say `confirmed`/`simulated`).
- ❌ "Live Fabric/Hyperledger running end-to-end" in the demo (default adapter = local; Fabric tests skipped; EC2 external).
- ❌ "AI diagnoses bee diseases" (screening only, 40-row synthetic set, 0.667 accuracy).
- ❌ "Real-time IoT telemetry with ML anomaly detection" (no ML artifacts; anomaly disabled; simulator only).
- ❌ "Productivity prediction works" (model + endpoint not in repo).
- ❌ "Cryptographic verification via QR scan" (server-reported proof, no client-side chain).
- ❌ "Batch/provenance fully implemented across every entity" (batch API 500s on live DB).
- ❌ "Voice observation / audio-based productivity tracking" on Android (native stub, no RECORD_AUDIO).
- ❌ "Production ready" / "App Store / Play ready" (debug-signed release, `com.example` id).
- ❌ "SYSTEM live on Supabase with all features" (no live integration test; DB contract broken for batches).

---

## 17. CRITICAL FINDINGS

### CRITICAL 1 — Batch NULL normalization missing; live batch API 500s.
- File/functions: `backend/app/db/supabase.py` `create_batch` (1355-1361, incl. forced `organization_id=None` at 1359-1360), `get_batch` (1363), `get_batch_by_code` (1366), `list_batches` (1369-1381), `update_batch` (1383-1387); schema `backend/app/schemas/batch.py:43-53`; also `split`/`merge` in `batch_service.py:302-313,360-371`.
- Evidence: live SELECT shows 4/15 batches `client_id=NULL`, 14/15 `organization_id=NULL`; pydantic 2.13 `ValidationError: string_type` reproduced for both fields; `InMemoryRepository` always emits strings (`supabase.py:617`).
- Impact: POST/GET/PUT lists and split/merge → HTTP 500 in production; all 232 tests green (in-memory).
- Confidence: HIGH. Recommended next action (do NOT implement now): extend `_with_client_id`-style normalization to the batch read paths (once for `client_id`, once for `organization_id`) and add a `test_client_id_null_contract` case for batches; verify against live read before/after.

### CRITICAL 2 — JWT signing secret is empty in live config → public dev secret.
- File: `backend/.env` (`JWT_SECRET` empty) + `backend/app/core/config.py:70-79`; bypass path `core/security.py:137-147` (non-UUID subject claims trusted).
- Impact: token forgery of any role (admin included) for anyone on the wire to any instance running with this env unless `API_ENV` is exactly production + a real secret. 500-level risk severity above; auth bypass.
- Confidence: HIGH (config static; exploit not performed).
- Recommended action: set a strong JWT_SECRET, force-guard non-UUID subject acceptance, migrate demo creds.

### CRITICAL 3 — Live service-role key / DB password on disk (untracked but exported).
- Files: `backend/.env` (service role 219 chars), root `.env` (`SUPABASE_DB_URL` w/ password), `supabase/scripts/.env`. gitignored, NOT committed — but any distribution of the folder (zip, USB, sync) leaks full DB control and anon key.
- Confidence: HIGH. Recommended action: rotate the Supabase service-role key and DB password before sharing, or migrate to secret manager.

### CRITICAL 4 — ML anomaly detection artifact-intentionally absent.
- Files: `backend/app/services/honeychain_ml_service.py` (loads 3 `.joblib`), `ml/models_honeychain_event/` missing; skip in `test_honeychain_ml_service.py:46-53`.
- Impact: telemetry `ml_status=NORMAL/“ML warm-up”`, `ml_anomaly=False` always; no anomaly signal; claim of "real-time AI monitoring" false.
- Confidence: HIGH.

---

## 18. POTENTIAL FINDINGS (uncertain / latent)

1. `_next_organization_key` RPC is called by `SupabaseRepository` but its SQL is not in this checkout's migrations — if the live project lacks the RPC the fallback path is exercised; unverified live. MEDIUM confidence.
2. `update_batch` (route `batches.py:59-74`) allows buyers to edit non-status fields of any scoped batch — authorization over-reach; not exploited. MEDIUM.
3. `POST /evidence/bundles` allows anchoring evidence over non-batch refs without ownership proof. MEDIUM.
4. No pagination on the four primary list endpoints. MEDIUM (performance, not correctness).
5. Rate limiter is per-process (`rate_limit.py`) — n× quota under multi-worker. LOW today (single worker).
6. `BatchUpdate.status` unvalidated vs DB CHECK → 23514 500 on invalid status in production. MEDIUM.
7. Harvest evidence bundles never persisted to `blockchain_anchors` (bundle-only) — passport ANCHOR event will never show a harvest anchor. MEDIUM.
8. `Storage` of JWT in plain SharedPreferences. MEDIUM.
9. `passport` consumer path cannot cryptographically re-verify (no client-side recompute). MEDIUM (integrity claim).
10. Stale module references in `test_fabric_adapter.py` to deleted `fabric_adapter.py`/`simulated_adapter.py`. LOW (docs/smell only).
11. Release APK committed (74 MB) — slowness/bloat + anon key surface. LOW.
12. `screens/main.dart` empty + duplicate `CreateBatchScreen` class in `harvest_screen.dart` vs `create_batch_screen.dart` — risk of duplicate-class compile break when both imported. LOW-MEDIUM.

---

## 19. VERIFIED FACTS (from repo/tests/live read-only inspection)

- Working tree NOT clean: modified `backend/app/db/supabase.py`; untracked `backend/tests/test_client_id_null_contract.py` (the in-progress hives/harvests client_id fix). HEAD `64c748f`.
- Live production DB (via configured service-role key, read-only): hives 31 (21 NULL client_id), harvests 22 (12 NULL), batches 15 (**4 NULL client_id, 14 NULL organization_id**); batch statuses only `created|listed`; honey_type/qty never NULL.
- Pydantic v2.13 rejects `BatchRead(client_id=None, organization_id=None)` — reproduced.
- `ml/models_honeychain_event/` does not exist (Test-Path False).
- `ml/artifacts/model.pkl` + metadata/metrics/inference_checks and the 40-row synthetic CSV ARE tracked and committed; decision tree accuracy 0.667 test / 0.85 CV / F1 0.6.
- 30 backend test modules, 236 `def test_`; conftest pins in-memory + simulated blockchain; 4 skips are Fabric + One-Class-SVM (all legitimately gated).
- `.github/workflows/dart.yml` is the only workflow (Flutter only).
- `releases/HoneyChain-v2.0.2.apk` is committed to git; untracked debug/release APKs also present; release is debug-signed; app id `com.example.honeychain`.
- Android manifest: INTERNET + CAMERA only; no RECORD_AUDIO; no deep-link intent-filter.
- No `.joblib`, `.pem`, `.key`, keystores tracked in git; `.env` files untracked.
- Migration set 001–012; partial unique indexes on client_id (`005`) present; demo anchor row `network='simulated' status='confirmed'` seeded (`004`).
- 12 of the 13 `backend/.env` keys revealed as names only; values never printed.

---

## 20. FINAL STATUS

**AUDIT COMPLETE — CRITICAL ISSUES FOUND**

The batch NULL contract bug is an active production defect of the same class you fixed for hives/harvests, and it went undetected precisely because the entire test suite runs against the in-memory repository. Recommended immediate follow-ups (not performed): normalize `client_id` **and** `organization_id` on the batch read paths, add batch cases to the null-contract regression test, replace the empty `JWT_SECRET`, and rotate the on-disk Supabase credentials before distributing this checkout.