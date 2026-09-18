# 🍯 HoneyChain 3.0

**Simple for Beekeepers.**

**SIH26021 — Honey Chain:** A blockchain-based honey traceability and smart beekeeping platform designed for fragmented, multi-organization, and intermittently connected honey supply chains.

> **Repository state audited:** `main` at commit `92b1577639007519dfb9bacca719fc2afb5fac69` (2026-09-18). This README separates implemented behavior, simulated/demo surfaces, historical runtime evidence, and remaining work.

HoneyChain is a flexible trust infrastructure for fragmented honey supply chains — connecting independent organizations and offline field operations into one continuously verifiable provenance network.

HoneyChain combines:

- 🐝 Beekeeper-first mobile workflows
- 🤖 AI-assisted hive intelligence
- 📷 Structured evidence capture
- 📶 Offline-first field operations
- 🔐 Cryptographic evidence integrity
- ⛓ Hyperledger Fabric provenance anchoring
- 📱 QR-based Honey Passports

---

## What HoneyChain Does

HoneyChain traces honey from hive to consumer, recording verifiable provenance events at every stage:

```
Beekeeper
  → Hive / Apiary
    → Inspection
      → Harvest
        → Field Verification
          → Evidence Bundle
            → Laboratory Certification
              → Processing
                → Packaging
                  → Distribution
                    → Honey Passport
                      → Consumer QR Verification
```

Provenance events are linked through batch lineage, trust tiers, and cryptographic commitments. Each stage is evaluated for evidence completeness and can be anchored to Hyperledger Fabric when the blockchain adapter is configured and reachable.

### Trust Tiers

Every batch is evaluated into one of four tiers derived **only** from recorded events:

| Tier | Meaning |
|---|---|
| `selfDeclared` | Beekeeper-reported harvest |
| `organizationVerified` | FPO / collection center confirmed |
| `labVerified` | Laboratory certification passed |
| `blockchainAnchored` | Merkle root committed to distributed ledger |

Merged lots take the weakest child tier. A tier does **not** certify purity, taste, nutrition, or health claims.

---

## Key Differentiators

### Flexible Organization Model

```
Organization
  → Membership
    → Assignment
      → Domain workflow
```

The same backend supports different stakeholders — beekeeper, field officer, FPO, collection center, laboratory, processor, packager, logistics, retailer, regulator, consumer, administrator — without creating a separate system for every organization.

### Offline-First Field Operations

Beekeepers can record observations, inspections, and harvests without continuous connectivity. Work is queued locally and synchronized when the network returns.

### Evidence-First Provenance

HoneyChain does not merely store a claim that an event happened. It links provenance to structured evidence, hashes, signatures, and event history. An evidence bundle associates beekeeper, apiary, source hives, field inspection, GPS, photos, timestamp, device identity, quantity, and metadata — then commits the Merkle root to a trust layer.

### Blockchain as Infrastructure

Beekeepers do not manually manage blockchain transactions. Blockchain is used underneath the application as a verifiable trust layer, anchored only when the backend confirms the actual state.

### One Domain, Multiple Experiences

The same core system supports beekeeper, FPO, laboratory, processor, consumer, regulator, and administrator workflows through role-based access control.

---

## System Architecture

```
Flutter Mobile App
        │
        ▼
API Client / HoneyChainStore
        │
        ▼
FastAPI Backend (Python)
        │
        ├──────── Domain Services
        │         (hive, harvest, batch, custody, lab,
        │          evidence, merkle, lineage, passport, sync)
        │
        ├──────── Supabase / PostgreSQL
        │         (canonical data store)
        │
        ├──────── Evidence + Cryptographic Layer
        │         (SHA-256, ECDSA P-256, Merkle trees)
        │
        └──────── BlockchainGateway
                         │
                         ▼
                Node.js Fabric Gateway Service
                  (@hyperledger/fabric-gateway)
                         │
                         ▼
              Hyperledger Fabric (EC2)
                         │
                         └── Consortium/network boundary
```

**Key principle:** Flutter does not communicate directly with Fabric. The backend controls domain validation, evidence integrity, and blockchain interaction. The application talks to exactly one boundary — `BlockchainGateway` — which dispatches to one adapter selected by configuration.

### Blockchain Adapter Taxonomy

| Adapter | When Used | Behavior |
|---|---|---|
| `LocalLedgerAdapter` | Default; no EVM/Fabric credentials | In-process dev ledger; labeled `local`; never presented as a real chain |
| `EVMBlockchainAdapter` | `BLOCKCHAIN_ADAPTER=evm` + RPC/wallet/contract | Returns `BLOCKCHAIN_NOT_CONFIGURED` when unconfigured |
| `FabricBlockchainAdapter` | `BLOCKCHAIN_ADAPTER=fabric` + channel/chaincode | Real submission via Node.js gateway when the gateway is reachable |

The gateway never fabricates confirmations. `CONFIRMED` requires confirmation from a reachable ledger.

---

## Beekeeper Mobile Experience

**"The beekeeper should interact with the apiary, not the blockchain."**

Core actions available to the beekeeper:

- Check hive health
- Record inspection
- Take photo
- Record voice observation
- Record harvest
- Review hive health scores and risk levels
- Review tasks
- View harvest history
- View Honey Passport
- Ask HoneyChain (AI-assisted assistant)

Technical infrastructure is hidden unless the beekeeper explicitly opens technical details.

**UX principles:**
- Large touch targets
- Minimal typing
- Camera-first workflows
- Voice-ready workflows
- Local-language-ready UI
- Offline status indicator
- Automatic synchronization when connected

---

## Ask HoneyChain

Ask HoneyChain currently has two assistive surfaces:

- **Local intent parser:** deterministic, on-device intent handling for supported HoneyChain actions/questions, with a fallback instead of inventing unsupported answers.
- **AI Snapshot research assistant:** an AI-native research/search surface for general honey-chain concepts and related knowledge; it does not create, certify, or modify supply-chain records.

The hive-health path is an **assistive rule/evidence-based pre-screen**, not a served trained ML model, neural network, disease-diagnosis system, or LLM/RAG pipeline.

**Example interaction:**

> **Beekeeper:** "My bees are less active today."

> **HoneyChain:**
> - Identifies the observation
> - Associates it with a hive where context exists
> - Provides an AI-assisted risk assessment
> - Recommends an appropriate next action
> - Allows the beekeeper to save the structured observation

**Hard boundary:** AI does not diagnose disease, replace laboratory testing, issue/revoke certificates, change batch quantities/custody, or alter verification state. It may surface a risk signal or recommend inspection. The current backend risk engine is rule/evidence-based and explicitly reports "insufficient data" when evidence is thin.

---

## Offline-First Design

```
Local event
  → local queue
    → connectivity returns
      → synchronization
        → server validation
          → canonical persistence
            → provenance update
              → blockchain anchoring (when configured/available)
```

- Work recorded while offline keeps a `pending` status with retry counters persisted to local storage.
- When connectivity returns, the sync engine drains the queue in dependency order.
- Each item is retried up to a cap; records are protected against duplicate sync through idempotent `client_id` upserts.
- Fork preservation: both branches of a conflict are preserved and surfaced; merging is an explicit operation.

**Current limitation:** the repository proves concrete offline/sync paths and recent create/sync fixes, but full offline synchronization of every provenance entity is not established as a production guarantee. The Supabase sync fallback handles tables without a `client_id` conflict arbiter, but select-then-insert remains race-prone until database uniqueness constraints are guaranteed everywhere.

**Important:** Offline mode does not mean blockchain operates offline. The field record can be created offline; blockchain anchoring occurs when the backend and network are available.

---

## Evidence + Cryptographic Integrity

### Evidence Bundle

A Harvest Evidence Bundle may associate:

- Beekeeper and apiary identity
- Source hives
- Hive intelligence records
- Field inspection data
- GPS coordinates
- Photos (content hashes — raw files never reach the ledger)
- Timestamps
- Device identity
- Field officer signature
- Quantity and metadata

### Cryptographic primitives

| Primitive | Implementation |
|---|---|
| Canonical serialization | Object keys sorted, nulls omitted, numbers normalized, ISO-8601 timestamps |
| Hash | SHA-256 (hex-encoded) |
| Payload hash | `sha256(canonical_json(payload))` |
| Actor signatures | ECDSA P-256 (NIST P-256 / secp256r1), DER-encoded |
| Merkle tree | Leaves = canonical hash of each evidence object; internal nodes use sorted-pair hashing; root anchored to trust layer |
| Hash chain | Offline event ledger with `previous_event_hash` references — tamper-evident local history |

Blockchain stores verifiable references and commitments (Merkle roots, event hashes). Raw sensitive data, PII, photos, and lab sheets are **never** placed on-chain.

---

## Hyperledger Fabric

### Network Configuration

| Property | Value |
|---|---|
| Hosting | AWS EC2 (ap-south-1) |
| Fabric Version | v2.5.16 |
| Channel | `mychannel` |
| Chaincode | `honeychain` |
| Chaincode Version | `2.0` |
| Chaincode Sequence | `6` |
| Org1 Approval | Yes |
| Org2 Approval | Yes |
| Endorsement Plugin | escc |
| Validation Plugin | vscc |
| Org1 Peer | `peer0.org1.example.com:7051` |
| Orderer | `orderer.example.com:7050` |

### Integration

| Component | Technology |
|---|---|
| Gateway Service | Node.js (`@hyperledger/fabric-gateway` ^1.4.0, gRPC + TLS) |
| Service Runtime | systemd (`honeychain-fabric-gateway`), port 9446 on EC2 |
| Backend Adapter | Python `FabricBlockchainAdapter` → HTTP → Node.js gateway |
| Protocol | `POST /evaluate` for reads, `POST /submit` for writes |

**Important:** The deployed chaincode is **not** the local `fabric/chaincode/tracer/`. The deployed contract is `honeychain.js` with a different function interface. The local `tracer` source in `fabric/chaincode/tracer/` is a development reference only.

The Node gateway is now allowlist-based rather than accepting arbitrary chaincode function names. Its write path obtains the real Fabric proposal transaction ID and waits for commit status before reporting confirmation. The gateway remains behind the private/SSH-tunnel boundary until service authentication is added.

### Chaincode Functions

**Reads:** `getEvent`, `getEventsByType`, `getBatch`, `getAllBatches`, `getAnchor`, `verifyMerkleRoot`, `getLineage`, `getCertificate`, `getCertificatesForBatch`, `getHistory`, `scanRange`

**Writes:** `submitEvent`, `createBatch`, `transitionBatch`, `recordLineage`, `anchorMerkleRoot`, `registerCertificate`, `revokeCertificate`

**Verification note:** These interfaces were documented from the existing deployment evidence/audit; this README does not claim a fresh live-network verification on every commit.

---

## 🟠 Live Runtime Verification

HoneyChain includes two categories of Fabric tests:

1. **Unit tests** — Fabric HTTP interactions are mocked and labeled `UNIT`. These run without any network dependency.
2. **LIVE_RUNTIME tests** — designed to connect to the real AWS EC2 Fabric gateway and execute actual chaincode transactions when the gateway is reachable.

The repository contains evidence of previous live Fabric verification, including committed transactions and read-back checks. The latest source audit was read-only and did **not** independently re-run the EC2 transactions.

### Gateway Health / Live Evidence

The repository's recorded verification evidence includes a gateway health response showing:

```json
{
  "status": "connected",
  "channel": "mychannel",
  "chaincode": "honeychain",
  "chaincode_version": "2.0",
  "chaincode_sequence": 6,
  "peer": "localhost:7051",
  "msp_id": "Org1MSP"
}
```

Recorded live transaction evidence includes successful `anchorMerkleRoot`, `submitEvent`, and `createBatch` operations, plus a deliberately invalid event that was rejected by Fabric chaincode validation. These are **recorded evidence from the project**, not a claim that the current runtime is continuously available.

### Block-Level Proof

Recorded evidence also includes a channel-height change from 41 to 42 and a matching previous-block hash, supporting that the documented write extended the channel ledger.

---

## Honey Passport / QR Verification

The Honey Passport provides consumer-facing QR verification of honey provenance.

### Passport Journey

```
Hive → Harvest → Verification → Lab → Processing → Packaging → Distribution
```

### Current QR contract

The QR currently contains a **plain `honeychain://trace/<productCode>` or legacy `honeychain://jar/<jarId>` identifier**. It does **not** embed a cryptographic signature or hash. Scanning resolves local records first and can fall back to the public backend passport endpoint for an unknown code. A real server response can expose the evidence root/data hash and real Fabric transaction hash when an actual anchor exists; the app does not fabricate these values.

**Remaining QR-proof work:** bind the QR/passport directly to the canonical batch/evidence commitment so the consumer flow can recompute the expected SHA-256/Merkle root and compare it with the recorded Fabric anchor as one explicit `VERIFIED` check. Merely displaying a hash is not the same as this proof loop.

### Statuses

| Status | Meaning |
|---|---|
| `RECORDED` | Event captured in the system |
| `INFERRED` | Derived from linked events |
| `CERTIFIED` | Laboratory certification passed |
| `VERIFIED` | Evidence integrity confirmed |
| `MISMATCH` | Evidence no longer matches anchored commitment |
| `REVOKED` | Certificate revoked |
| `DISPUTED` | Under review |

**Important:** A trust tier and blockchain anchor do **not** certify the physical purity or authenticity of honey. See [Scientific Limitation](#scientific-limitation) below.

---

## User Roles

HoneyChain enforces a server-side RBAC matrix (`backend/app/core/rbac.py`) across 7 roles and ~24 actions:

| Role | Description |
|---|---|
| `beekeeper` | Dashboard, hive health, risk insight, record harvest, view history |
| `fpo` | Harvests, batches, custody, verification, traceability, marketplace |
| `lab` | Verify batches (PASS/FAIL), issue/revoke certificates |
| `processor` | Custody, processing, split/merge genealogy, corrections |
| `buyer` | Batch audit, published passports |
| `institution` | Audit access across organizations |
| `admin` | Full system access, audit, demo tools |

Scoping: beekeepers see only their own data; FPO/processor see their org's data; lab/buyer/institution/admin have broader read access. Authorization is enforced by the backend RBAC layer; the broader database policy surface still requires hardening before production.

---

## Technology Stack

### Verified Technologies

| Layer | Technology | Version |
|---|---|---|
| Mobile Frontend | Flutter | 3.47.1 |
| Language (Mobile) | Dart | 3.13.1 |
| Backend Framework | FastAPI | 0.141.1 |
| Language (Backend) | Python | 3.14.6 |
| Data Validation | Pydantic | 2.13.5 |
| Database | PostgreSQL (Supabase) | — |
| Supabase Client | supabase-py | 2.31.0 |
| Cryptography | SHA-256, ECDSA P-256 | cryptography 50.0.1 |
| JWT | PyJWT (HS256) | — |
| Blockchain | Hyperledger Fabric | v2.5.16 |
| Fabric SDK | @hyperledger/fabric-gateway | ^1.4.0 |
| Fabric Gateway | Node.js + Express | ^4.18 |
| gRPC | @grpc/grpc-js | ^1.10.0 |
| QR Generation | qr_flutter | ^4.1.0 |
| QR Scanning | mobile_scanner | ^7.4.0 |
| Connectivity | connectivity_plus | ^7.3.1 |
| Local Storage | shared_preferences | ^2.3.0 |
| ML | Rule-based risk engine | (not a trained neural net) |
| Testing (Backend) | pytest | 9.1.1 |
| Testing (Frontend) | flutter_test | — |
| CI/CD | GitHub Actions | Flutter CI |
| Containerization | Docker | 29.7.2 (Dockerfile present) |

---

## Current Verified Status

### What Is Verified

| Component | Status | Evidence |
|---|---|---|
| Flutter app (offline-first) | 🟡 VERIFIED IN TEST SUITE | Latest repository commit reports `flutter test` → 120 passed; physical-device E2E remains unverified |
| Flutter ↔ backend (beekeeper path) | ✅ INTEGRATED | `honey_api_service` — real login, server hives/harvests, evidence/Fabric status path |
| FastAPI backend | 🟡 VERIFIED IN TEST SUITE | Latest repository commit reports 207 backend tests passing; checked-in `TEST_RESULTS.md` still contains the older 157/3 baseline, so this is a commit-reported count rather than a fresh audit execution |
| Supabase schema (migrations 001–008) | ✅ APPLIED | Migrations documented as applied to the project |
| Backend repository abstraction | ✅ REAL | InMemory + Supabase repositories |
| Evidence bundles + Merkle integrity | ✅ VERIFIED | Unit tests with tamper detection |
| Event ledger (hash-chained) | ✅ VERIFIED | Append-only, fork-preserving |
| BlockchainGateway + tx state machine | ✅ VERIFIED | PENDING → SUBMITTED → CONFIRMED |
| Local dev ledger | ✅ REAL | Labeled `local` in responses |
| EVM adapter boundary | ⚠️ NOT CONFIGURED | Returns `BLOCKCHAIN_NOT_CONFIGURED` |
| Fabric adapter | 🟡 LIVE EVIDENCE + CURRENT CODE PATH | Previous EC2 transactions are documented; current source propagates real Fabric tx IDs/commit status, but this audit did not re-run the live EC2 network |
| Lab certificate issue/verify/revoke | ✅ VERIFIED | Content-hash anchoring + revocation |
| Trust tiers | ✅ VERIFIED | Weakest-tier merge logic tested |
| RBAC matrix | ✅ VERIFIED | 7 roles × ~24 actions, server-side |
| Honey Passport | 🟡 REAL + ONLINE PATH | Server-backed PII-free passport; QR is still an unsigned identifier and the full QR→Merkle→Fabric proof loop is not yet complete |
| Hive Intelligence risk engine | ⚠️ RULE/EVIDENCE-BASED | Assistive pre-screen; not a served trained model and not disease diagnosis |
| ML artifacts | ⚠️ PROTOTYPE | `ml/model.pkl` / metrics are prototype material and are not wired into the live API |
| Admin / oversight routing | ✅ FIXED IN CURRENT SOURCE | `RootGate` routes the active platform workspace separately from the beekeeper workspace |

### What Is NOT Verified / NOT Complete

| Component | Status | Current gap |
|---|---|---|
| Live Supabase writes | NOT VERIFIED | No live write/read E2E was executed in this audit |
| Full QR cryptographic verification | NOT COMPLETE | QR is a plain identifier; full QR → real batch → recomputed Merkle root → Fabric anchor comparison remains to be wired as one consumer proof path |
| Harvest evidence → Fabric anchor | PARTIAL | Generic evidence bundles compute a real Merkle root, but the current harvest entity path submits an empty batch reference to the anchor adapter; batch-scoped anchoring is the canonical persisted path |
| EVM anchoring | NOT CONFIGURED | No RPC + wallet + deployed contract |
| Public Fabric access | PRIVATE / SSH TUNNEL | EC2 gateway port 9446 is not publicly exposed |
| Docker container builds | NOT VERIFIED IN THIS AUDIT | Docker runtime was not exercised here |
| Camera/QR on hardware | NOT TESTED | No physical device access in the audit environment |
| Real Android device E2E | NOT TESTED | No device/emulator in the audit environment |
| Production release signing | NOT READY | Release APK is debug-signed; production keystore is still required |
| Physical IoT protocols | NOT COMPLETE | Current telemetry path is software/simulation; MQTT/LoRa/BLE/Wi-Fi/cellular hardware adapters are not established as live |
| Served ML model | NOT COMPLETE | Current risk engine is rule/evidence-based; prototype model artifacts are not wired into the API |

---

## Test Results

### Backend — pytest

**207 passing — latest repository commit report.** The checked-in `TEST_RESULTS.md` contains an older 157 passed / 3 skipped baseline; this README uses the newer commit-reported count while distinguishing it from a fresh audit execution.

| Test File | Coverage |
|---|---|
| `test_fabric_adapter.py` | 25 passed (UNIT, mocked HTTP) + 3 skipped (LIVE_RUNTIME) |
| `test_auth.py` | Login, JWT, demo identity |
| `test_hives.py` / `test_harvests.py` / `test_batches.py` | CRUD + scoping |
| `test_custody.py` | Custody transfers |
| `test_lab.py` | Lab request/result flow |
| `test_passport.py` | Public passport resolution |
| `test_sync.py` | Idempotent offline sync |
| `test_rbac.py` | Authorization + resource scope |
| `test_crypto.py` | Canonical serialization, SHA-256, ECDSA |
| `test_merkle.py` | Root/proof/tamper |
| `test_event_ledger.py` | Hash chain, tamper detection, fork preservation |
| `test_evidence.py` | Bundles, verify, proofs, tamper |
| `test_certificates.py` | Issue/revoke/verify |
| `test_lineage.py` | State machine transitions + custody holder |
| `test_gateway.py` | Local vs EVM/Fabric boundary honesty |
| `test_rbac_matrix.py` | Matrix + scope helpers |
| `test_new_routes.py` | API surface for new endpoints |

The 3 skipped tests are `LIVE_RUNTIME` tests gated by `FABRIC_GATEWAY_URL`.

### Flutter — flutter test

**120 passing — latest repository commit report.** Coverage includes beekeeper portal, recording harvests, hive details/alerts, honey passport drilldown, rule-based disease screening, IoT simulation warnings, responsive smoke tests, backend API service, offline queue + restart durability, no-duplicate sync, backend-mode guards, API config policy, auth/session state machine, workspace switching, and online passport verification client.

**One session, many workspaces:** a signed-in account can switch between the Beekeeper, Organization / FPO, Buyer and Consumer experiences from the More tab without logging out and without re-entering a persona login. The active workspace is persisted, a backend-backed account is narrowed to the workspaces its role is actually allowed to enter, and `logout` never deletes local domain records or the pending-sync queue.

**Beekeeper ↔ backend integration (`lib/services/honey_api_service.dart`):** when the app is built with `--dart-define=API_BASE_URL=…`, the login screen offers a real backend sign-in. Once signed in, My Hives shows server hives, create hive posts to the backend, harvest recording pushes to the API, and the blockchain screen maps backend chain status. The exact live Fabric path depends on the configured backend/gateway runtime.

**Config policy (fail-fast):** the app does not hardcode a production backend or secrets. `API_BASE_URL` is injected at build time; production/staging must be `https://`, and plain `http://` is allowed only for local development hosts. A compiled-but-rejected URL aborts startup with an explicit error instead of silently running without a backend.

### Android builds

- **Debug APK** — previously built and verified on the audit machine: `releases/honeychain-2.0.2+4-debug.apk`.
- **Release APK** — `releases/honeychain-2.0.2+4-release.apk` (74.7 MB) builds, but uses the **debug signing key**, so it is NOT Play-Store-ready. A real release keystore must be provisioned before distribution.
- **Real-device E2E** — NOT TESTED in the audit environment: no Android device/emulator was available.

### Test Integrity

- Unit tests use mocked Fabric HTTP interactions and are labeled `UNIT`.
- LIVE_RUNTIME tests are separate and require a reachable Fabric gateway.
- No simulated blockchain success should be represented as live blockchain verification.
- Truth status is documented in [`docs/FINAL_TRUTH_REPORT.md`](docs/FINAL_TRUTH_REPORT.md).

---

## Security Notes

- Secrets stay server-side; `.env` files are intended to be gitignored.
- Supabase secret/service-role credentials are not shipped to Flutter; only the publishable client key is intended for the app.
- **No third-party API key was detected in the current repository scan** for common Google/Gemini, OpenAI, GitHub, AWS, Supabase-secret and private-key patterns.
- A development-only JWT fallback string exists in configuration and must never be used as a production secret.
- Blockchain private keys / MSP material should never be committed.
- Authentication and authorization remain backend-controlled (RBAC matrix).
- Idempotency protects repeated operations (`client_id` upserts).
- Conflict history is preserved (fork-recording, not auto-merge).
- Raw photos / lab sheets / PII are not intended to be placed directly on-chain — only hashes/commitments.
- **Production hardening required:** the Node.js Fabric gateway's privileged `/submit` and `/evaluate` endpoints must be authenticated and restricted/allowlisted before network exposure.
- **Production hardening required:** Flutter JWT storage currently uses `SharedPreferences`; a platform-secure credential store should be used for production.
- **Production hardening required:** database RLS policies and transitional direct-Supabase sync paths need alignment with backend RBAC.
- Rate limiting exists for the public passport endpoint (in-memory; Redis recommended for production).
- Tamper/demo endpoints are gated behind `DEMO_MODE` / 403 in production where implemented.

---

## Roadmap

### ✅ Verified / Implemented

- Offline-first mobile workflows
- Structured evidence capture + Merkle integrity
- Batch lineage + trust tiers
- FastAPI backend with RBAC
- Supabase schema/migrations
- Local dev ledger (honest, labeled `local`)
- Hyperledger Fabric adapter and recorded live-runtime evidence
- Honey Passport (PII-free, public)
- Rule-based hive intelligence
- QR camera scanning
- Voice-ready observation recording
- Split / merge / correction business logic

### 🟡 In Progress / Partially Verified

- Full offline synchronization across all provenance entities
- Supabase live persistence / end-to-end write verification
- Full consumer QR proof: QR identifier → real passport → recomputed evidence commitment → Fabric comparison
- Harvest evidence anchor semantics: attach harvest evidence to a canonical batch anchor before presenting it as blockchain-anchored
- EVM adapter (boundary code exists, no network configured)
- Physical IoT protocol adapters and real sensor ingestion
- Served ML model / validated real-world hive-health training data
- Disease screening from photos (not a validated diagnostic capability)
- Multi-organization Fabric topology hardening

### 🔵 Planned / Production Hardening

- Authenticated Node.js Fabric gateway service before any network exposure (the function allowlist is already present)
- Canonical QR/passport cryptographic proof flow with explicit recomputation + Fabric comparison
- Secure platform-backed JWT storage
- Alignment of Supabase RLS with backend RBAC
- 24/7 public Fabric gateway endpoint (requires secure deployment rather than the current SSH-tunnel arrangement)
- Stronger token refresh/revocation
- Richer beekeeper localization
- Advanced AI models for hive health
- IoT integrations
- Expanded organization workflows
- Advanced analytics
- Photo/media object storage
- Redis-backed rate limiting for multi-instance deployment

---

## Current Implementation Priorities

The next work should stay inside the existing architecture — no reconstruction or repository restructure is required:

1. **Provenance correctness:** finish harvest evidence → canonical batch anchoring and verify the persisted relationship.
2. **Consumer proof:** make the QR resolve to the real passport and expose the real evidence root / Fabric tx reference; then add the explicit recompute-and-compare verification step. Do not fake a hash just to populate the QR.
3. **Supabase E2E:** execute real Flutter → FastAPI → Supabase write/read and offline-sync recovery tests.
4. **Hardware path:** test QR scanning on a physical Android device and normalize real IoT inputs behind the existing telemetry pipeline.
5. **Intelligence:** improve the local parser/risk logic first; only call the system ML/AI once an actual served model is wired and evaluated.
6. **Security:** add service authentication to the private Fabric gateway before exposing it beyond the current boundary.

## Demo Flow

### Backend API Demo (Local)

```bash
cd backend
../.venv_backend/Scripts/uvicorn app.main:app --port 8000
# Open http://localhost:8000/docs
# Use demo credentials documented in docs/DEMO.md
```

See [`docs/DEMO.md`](docs/DEMO.md) for a scripted walkthrough, demo credentials, and step-by-step instructions.

### SIH Demonstration Flow

| Step | Action | Status |
|---|---|---|
| 1 | Beekeeper opens mobile app | ✅ Runtime-tested workflow |
| 2 | Checks hive health scores | ✅ Rule-based engine |
| 3 | Ask HoneyChain identifies an observation | ✅ AI-assisted recommendation |
| 4 | Beekeeper performs inspection | ✅ Workflow tested |
| 5 | Takes photo | ⚠️ Requires device camera |
| 6 | Saves observation offline | ✅ Offline queue tested |
| 7 | Connectivity returns | ✅ Sync path tested |
| 8 | Record synchronizes to backend | ✅ Idempotent sync path |
| 9 | Harvest is recorded | ✅ API + tests |
| 10 | Evidence bundle is created | ✅ Merkle root computed |
| 11 | Evidence commitment generated | ✅ SHA-256 + Merkle tree |
| 12 | Blockchain anchor submitted | ⚠️ Requires configured/reachable Fabric gateway |
| 13 | Fabric commits transaction | ⚠️ Previous live evidence exists; not continuously available |
| 14 | Backend verifies anchor | ⚠️ Requires configured/reachable Fabric gateway |
| 15 | Honey Passport QR displayed | ✅ QR generation |
| 16 | Consumer verifies provenance | ⚠️ Device scan requires camera; manual verification path exists |
| 17 | Tampered data produces mismatch | ✅ Tamper detection logic |

---

## Scientific Limitation

> **Blockchain verifies the integrity and provenance of recorded information; it does not independently prove the physical purity or authenticity of honey.**

Laboratory testing is required for claims about:

- Purity
- Adulteration
- Chemical composition
- Microbiological quality
- Other physical properties

A `blockchainAnchored` lot can still be counterfeited at the physical-good level. The system proves provenance of **records**, not the physical product. Trust tiers reflect recorded evidence; they do not certify taste, nutrition, or health claims.

---

## Documentation

Complete documentation is in [`docs/`](docs/):

| Document | Description |
|---|---|
| [`FINAL_TRUTH_REPORT.md`](docs/FINAL_TRUTH_REPORT.md) | Verified state audit — everything evidence-backed |
| [`TEST_RESULTS.md`](docs/TEST_RESULTS.md) | Verified test matrix with transaction evidence |
| [`BLOCKCHAIN.md`](docs/BLOCKCHAIN.md) | Blockchain strategy and adapter taxonomy |
| [`FEATURE_STATUS.md`](docs/FEATURE_STATUS.md) | Feature completion status (honest classifications) |
| [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) | System architecture and deployment modes |
| [`SERVICE_STATUS.md`](docs/SERVICE_STATUS.md) | Component reality matrix |
| [`TECH_STACK_VERSIONS.md`](docs/TECH_STACK_VERSIONS.md) | Verified technology versions |
| [`API.md`](docs/API.md) | HTTP API reference |
| [`CRYPTOGRAPHY.md`](docs/CRYPTOGRAPHY.md) | Cryptographic primitives and Merkle structure |
| [`SECURITY.md`](docs/SECURITY.md) | Security model and guarantees |
| [`KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md) | Explicit, honest limitations |
| [`TESTING.md`](docs/TESTING.md) | Test suite documentation |
| [`DEMO.md`](docs/DEMO.md) | Demo walkthrough |
| [`ROLE_MATRIX.md`](docs/ROLE_MATRIX.md) | RBAC permission matrix |
| [`ASSUMPTIONS.md`](docs/ASSUMPTIONS.md) | Assumptions and decisions record |
| [`AUTH_SESSION_MODEL.md`](docs/AUTH_SESSION_MODEL.md) | One-session auth state machine + durable JWT restore |
| [`ROLE_UX_MAP.md`](docs/ROLE_UX_MAP.md) | Workspace switching without re-login, role→workspace map |
| [`QR_HONEY_PASSPORT.md`](docs/QR_HONEY_PASSPORT.md) | QR contract + Honey Passport + online verification |
| [`PROVENANCE_MODEL.md`](docs/PROVENANCE_MODEL.md) | Trust tiers, hashing, anchors (local vs live Fabric) |
| [`MOBILE_LIVE_FLOW.md`](docs/MOBILE_LIVE_FLOW.md) | End-to-end demo / backend / consumer flows |
| [`evidence/live-fabric-backend-proof.md`](docs/evidence/live-fabric-backend-proof.md) | Recorded Fabric integration evidence |

---

## License

This project is developed for **Smart India Hackathon 2026** (SIH26021). License terms to be determined.
