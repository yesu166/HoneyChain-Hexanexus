# HoneyChain 3.0 — Restructure Audit

Audit date: 2026-09-10
Baseline commit: `f319697` (main, clean)

Goal: compare the EXISTING repository against the HoneyChain 3.0 master
specification and classify every subsystem REAL / PARTIAL / SIMULATED / MOCK /
NOT_CONFIGURED / BLOCKED — with verified evidence, not wishful claims.

## 1. What already exists and works (verified)

| Subsystem | State | Evidence |
|-----------|-------|----------|
| Flutter app | REAL (64 tests) | `test/` has 13 files; offline-first store; 4-language strings; trust tiers; canonical QR contract; `mobile_scanner`; developer screen. |
| FastAPI backend | REAL (110+ tests) | 22 test files; auth (PBKDF2+JWT), RBAC (7 roles, ~25 actions), scoped services, evidence bundles + Merkle, certificates, lineage state machine, hash-chained ledger, IoT pipeline, notifications. |
| Rule-based Hive Intelligence | REAL (rule-based) | `RiskEngineAdapter` temperature/humidity/weight bands ± 1 sigma; honest `risk_engine` label. |
| Local ledger (blockchain dev adapter) | REAL (LOCAL only) | `LocalLedgerAdapter` commits in memory; transactions guaranteed within process. |
| Offline-first storage | REAL | SharedPreferences; idempotent `client_id` sync; retry queue (3 attempts/pass, never silently dropped). |
| QR generation/scanning | REAL | `qr_flutter` + `mobile_scanner`; canonical `honeychain://trace/<code>` payload. |
| Supabase migrations | REAL (applied 001–007, 007 pending?) | `supabase/migrations/` 001–007 idempotent; live project URL + DB URL configured. |
| Documentation | REAL | 20 coherent "control center" docs, honest `BLOCKERS.md`/`FEATURE_STATUS.md`. |

## 2. What is PARTIAL / NOT_CONFIGURED / BLOCKED

| Subsystem | Spec target | Current | Gap |
|-----------|-------------|---------|-----|
| Real Supabase persistence | Canonical source of truth | Backend boots `DemoSeededRepository` (in-memory) because service-role key absent. `SupabaseRepository` is fully implemented (backend/app/db/supabase.py:699) and auto-selected when credentials exist. | Enable + verify real writes; keep in-memory only for dev/tests. |
| Hyperledger Fabric | PRIMARY provenance ledger | No network running; backend `FabricBlockchainAdapter` raises `LedgerUnavailable`/`LedgerNotConfigured`; chaincode `node_modules` never installed; Docker daemon down. | Local Docker bring-up (or honest BLOCKED) + reproducible EC2 transfer kit. |
| EVM adapter | OPTIONAL public checkpoint | Boundary-only, honest `FABRIC/EV/…_UNAVAILABLE` codes. | Deliberately not a P0. |
| Organization / Membership / Assignment | Primary access model | Backend has `role` (global) + `org_id` scoping; no `memberships`/`assignments` tables. | Additive schema + repository/service extension (P1). |
| Device identity (P-256 keypair from Flutter) | Event signing on device | Backend supports ECDSA verify + IOT device keys; Flutter app does not mint a device keypair for evidence. | P1 (device signature on evidence events). |
| Portals | 11 role experiences | Beekeeper (rich), FPO/Org (rich), Buyer, Consumer (rich), Lab (legacy), Regulator (legacy), Admin (partial). Field Officer, Processor, Packager, Logistics, Retailer missing. | P1/P2 breadth after P0 slice. |
| Developer Center | Full diagnostics + Fabric control | `developer_screen.dart` has demo reset/sim controls/sync status; no evidence debugger, Merkle viewer, Fabric control. | P1. |
| Evidence file object storage | Real uploads | Evidence is content-hash references only; no blob upload endpoint. | P1. |
| Real AI/ML | Structured advisory | Rule-based engine (honest); `ml/train.py` produces demo Dart-exported decision tree with honest `DEMO/PROTOTYPE` labeling. | Keep rule-based; do not fake. |

## 3. Fake-success scan (hallucination protection §2.6)

Incidental findings, none used to claim REAL functionality:
- `docsim`/demo screens clearly label demo data.
- Blockchain anchors set `isMock: true` in Flutter — good (honest).
- Backend adapters never fabricate `CONFIRMED`. `test_gateway.py` asserts
  EVM/Fabric raise honest codes.
- `ml/artifacts/*` marked demo; runtime adapter is rule-based.
- No hardcoded transaction IDs / hashes / certificates found.

Selected to fix:
- `backend/.env.example` still says `BLOCKCHAIN_ADAPTER=simulated` (ADR-007
  renamed it to `local`). Cosmetic doc drift — fix.
- Migration 007 exists on disk but docs only list 001–006 — verify + align.

## 4. Restructure decisions (this session)

1. Keep modular monolith + repository-boundary architecture (spec §6, §13).
2. Enable REAL Supabase persistence now (authorized). In-memory repo becomes
   explicit dev/test fallback only. Add honest config/status handling.
3. Fabric: repair chaincode deps; attempt local Docker bring-up; if blocked,
   produce reproducible EC2 transfer kit and classify BLOCKED (no faking).
4. P0 priority: one complete vertical traceability slice (spec §93).
5. All demo/simulated surfaces remain clearly labeled.

## 5. Doc drift log

- `backend/.env.example` `simulated` → align with `local`.
- `README`/docs mention migrations 001–006; migration 007 present — verify applied.

## 6. Milestone update — Supabase persistence VERIFIED (2026-09-10)

Migrations **001–008 all applied** to the live project (`hhxwhopaazqjdlreqhkf`).

008 adds the backend-facing persistence surface: `users`, `passports`,
`batches.origin`, `hives.location`, `harvest_events.collected`, lab_tests
`status`/`requested_note`/`tested_by`/`notes`/`requested_at`/`tested_at`
(result nullable, lab_id widened to text), and batch_genealogy
`SPLIT_FROM`/`AGGREGATED_FROM`.

`SupabaseRepository` now translates domain ↔ cloud columns:
- custody `action/actor/event_at + notes` ↔ `event_type/actor_role/timestamp + metadata`
- `batch_harvests` ↔ `batch_harvest_links` (harvest_event_id)
- `relations` ↔ `batch_genealogy` (relationship_type; split/merge semantics)
- certificate empty-string `valid_until`/`revoked_at` → NULL
- reading `temperature_c/humidity_percent` ↔ `temperature/humidity`
- beekeeper `organization_id` ↔ domain `org_id`
- datetime/epoch values serialized to ISO on write
- beekeeper-role users mirrored into `beekeepers` (same uuid) so cloud FKs resolve
- evidence/certificate anchors persist honestly (gateway state, never faked)

Live E2E proof (service-role, REAL): registered beekeeper → hive → reading →
harvest → batch (origin) → batch–harvest link → custody TRANSFER → lab test
requested→PASS (batch auto-promoted to `lab_verified`) → evidence bundle
(Merkle root) → anchor (LOCAL ledger, `chain_status=anchored`) → passport
resolve + cache. All rows re-confirmed via the raw PostgREST API.

Test contract: in-memory stays deterministic (132 pass). `conftest.py` pins
`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY=""` after config import so a dev
`backend/.env` never leaks into the suite.

Still BLOCKED: Hyperledger Fabric (Docker daemon down, chaincode deps not
installed, EC2 key unreachable locally). `FabricBlockchainAdapter` stays
deployment-ready; no fake transactions.