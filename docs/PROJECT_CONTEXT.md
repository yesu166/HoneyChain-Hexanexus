# HoneyChain — Project Context (persistent memory)

Last updated: 2026-09-10  (update after every major phase)

## 1. Current architecture
Modular monolith. Flutter (offline-first, SharedPreferences) → FastAPI domain
core → Repository boundary → Supabase PostgreSQL (canonical app truth) / Object
storage (files) → Evidence/Provenance layer (hash chain, Merkle) →
BlockchainGateway → FabricAdapter (PRIMARY, deployment-ready) / LocalLedgerAdapter
(dev/test) → Honey Passport → public QR verification. AI is advisory
(rule-based `risk_engine`). One platform, many role experiences.

## 2. Implementation status
- Flutter: REAL (64 tests) — beekeeper/org/buyer/consumer portals, passport,
  QR, offline sync.
- Backend: REAL (110+ tests) — auth, RBAC, hives/harvests/batches, evidence
  bundles, Merkle, certificates + revocation, lineage state machine, event
  ledger, IoT pipeline, notifications.
- Supabase: schema applied 001…; service-role persistence NOW BEING ENABLED.
- Fabric: NOT_CONFIGURED (no running network; Docker daemon down; chaincode deps
  not installed). Repair + local bring-up in progress this session.

## 3. Confirmed decisions (see ARCHITECTURE_DECISIONS.md)
- Modular monolith (not microservices). One domain model, one DB, one identity.
- Fabric primary ledger; EVM optional public checkpoint; local ledger for dev.
- Organization + Membership + Assignment as access model (migration in progress).
- Merkle-root anchoring with per-item proofs; append-only evidence; live
  verification (VERIFIED is computed, not stored).
- Offline-first idempotent sync with stable `client_id`; forks preserved.
- Supabase is canonical truth; in-memory repo is dev/test fallback only.
- No fake success anywhere; demo data explicitly labeled.

## 4. Rejected decisions
- ZK/Groth16/Circom, MPC, homomorphic encryption, DID/VC stack, NFT/marketplace
  tokenomics, Kafka/RabbitMQ/K8s/service-mesh, IPFS-as-mandatory, generic policy
  engine.
- Microservices, generic blockchain plugin framework, "two sources of truth"
  between Fabric and EVM.

## 5. Active blockers
- B1 Docker daemon not running (local Fabric bring-up at risk).
- B2 AWS EC2 credentials absent (EC2 deployment planned for tomorrow by user).
- B3 No physical device (camera QR runtime unverified on hardware).
- B4 EVM credentials absent (EVM optional, not P0).

## 6. Current infrastructure
- Local: Windows 11, Flutter 3.47.1, Python 3.14.6, Node 24.19.0, git 2.55.0.
- Supabase live project: `hhxwhopaazqjdlreqhkf` (URL + DB URL configured;
  service-role key authorized).
- AWS EC2 `Honeychain` (ap-south-1, mychannel, Org1/Org2) — NOT reachable now.

## 7. Current database
- Supabase migrations 001–007 on disk. Applied set being verified this session.
- Tables: profiles, clusters, organizations, beekeepers, hives, hive_readings,
  health_scores, harvest_events, batches, batch_harvest_links, batch_genealogy,
  custody_events, lab_tests, blockchain_anchors, qr_codes, evidence_bundles,
  ledger_events, certificates, iot_devices, telemetry_events, notifications.

## 8. Current Fabric state
- `fabric/` = deployment definition (chaincode `tracer` in JS, docker-compose
  fabric-peer/orderer/cli 2.5, configtx, crypto-config, scripts). Never started.

## 9. Current API state
- FastAPI on `DemoSeededRepository` (in-memory). 22 test files green.
- Real Supabase persistence being enabled this session.

## 10. Current Flutter state
- v2.0.2+4, offline-first store, beekeeper/org/buyer/consumer flows, trust
  tiers, QR roundtrip, developer screen. 64 tests green.

## 11. Current test status
- Backend pytest: 110+ across 22 files (in-memory; Supabase path needs live
  verification). Flutter: 64.

## 12. Next priorities
1. Enable + verify real Supabase persistence (live write/read).
2. Verify/apply pending migrations; align doc drift (007, `simulated`→`local`).
3. Fabric: install chaincode deps, attempt local Docker network, deploy
   chaincode, PROVE one real transaction (capture tx id / block).
4. Wire backend FabricAdapter deployment-ready (connection profile).
5. P0 vertical slice end-to-end via real Supabase.
6. (P1) Organization/Membership/Assignment model + device signatures + Field
   Officer portal + Developer Center evidence debugger.