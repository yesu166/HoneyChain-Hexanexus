# 🍯 HoneyChain 3.0

**Simple for Beekeepers.**

**SIH26021 — Honey Chain:** A blockchain-based honey traceability and smart beekeeping platform designed for fragmented, multi-organization, and intermittently connected honey supply chains.

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
              ┌──────────┴──────────┐
              ▼                     ▼
           Org 1                  Org 2
              │
              ▼
          mychannel
              │
              ▼
       honeychain v2.0
```

**Key principle:** Flutter does not communicate directly with Fabric. The backend controls domain validation, evidence integrity, and blockchain interaction. The application talks to exactly one boundary — `BlockchainGateway` — which dispatches to one adapter selected by configuration.

### Blockchain Adapter Taxonomy

| Adapter | When Used | Behavior |
|---|---|---|
| `LocalLedgerAdapter` | Default; no EVM/Fabric credentials | In-process dev ledger; labeled `local`; never presented as a real chain |
| `EVMBlockchainAdapter` | `BLOCKCHAIN_ADAPTER=evm` + RPC/wallet/contract | Returns `BLOCKCHAIN_NOT_CONFIGURED` when unconfigured |
| `FabricBlockchainAdapter` | `BLOCKCHAIN_ADAPTER=fabric` + channel/chaincode | Real submission via Node.js gateway; verified live against EC2 Fabric |

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

Ask HoneyChain is a structured AI assistant, not a generic chatbot. It connects observations to hive context and provides AI-assisted risk assessments.

**Example interaction:**

> **Beekeeper:** "My bees are less active today."

> **HoneyChain:**
> - Identifies the observation
> - Associates it with a hive where context exists
> - Provides an AI-assisted risk assessment
> - Recommends an appropriate next action
> - Allows the beekeeper to save the structured observation

**Important:** AI inference must not be presented as confirmed disease diagnosis or factual measurement. The risk engine is **rule-based**, not a trained neural net. It explicitly reports "insufficient data" rather than inventing a reading.

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
- Each item is retried up to a cap; records are never duplicated (idempotent `client_id` upserts).
- Fork preservation: both branches of a conflict are preserved and surfaced; merging is an explicit operation.

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
| Merkle tree | Leaves = canonical hash of each evidence object; internal nodes = `sha256(left \|\| right)` (sorted-pair); root anchored to trust layer |
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

### Chaincode Functions (verified from live container)

**Reads:** `getEvent`, `getEventsByType`, `getBatch`, `getAllBatches`, `getAnchor`, `verifyMerkleRoot`, `getLineage`, `getCertificate`, `getCertificatesForBatch`, `getHistory`, `scanRange`

**Writes:** `submitEvent`, `createBatch`, `transitionBatch`, `recordLineage`, `anchorMerkleRoot`, `registerCertificate`, `revokeCertificate`

---

## 🟠 Live Runtime Verification

HoneyChain includes two categories of Fabric tests:

1. **Unit tests** — All Fabric HTTP interactions are mocked and labeled `UNIT`. These run without any network dependency.
2. **LIVE_RUNTIME tests** — Connect to the real AWS EC2 Fabric gateway and execute actual chaincode transactions.

### Gateway Health (verified)

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

### Live Transaction Evidence

| # | Chaincode Function | Transaction ID | Outcome |
|---|---|---|---|
| 1 | `anchorMerkleRoot` (HC-DEMO-001) | `dbcbd8feeff5761c98736c114d9a0f699b2d616398f6c8a1d9075728b52ad2cf` | committed (2232 ms) |
| 2 | `submitEvent` (PROVENANCE_ANCHORED) | `93698012206aa1664c90d7a71258390a4f10d8bc4f80ebe8ebcf02e8c2665e29` | committed (2101 ms) |
| 3 | `createBatch` (HC-LIVE-1789054361) | _(accepted — exact tx ID not documented)_ | accepted |
| 4 | `anchorMerkleRoot` (HC-LIVE-1789054361) | `52c7801a3e1d05a89e8cb03e76ad38176e359a57fb49745ee0b6b04a62bd0fe4` | CONFIRMED + read-back verified |
| 5 | `submitEvent` (invalid type `INTEGRATION_TEST`) | — | **REJECTED** (`10 ABORTED`) |

The rejected transaction (#5) is valuable evidence: it demonstrates real chaincode validation rather than a UI-only success state.

### Block-Level Proof

| Metric | Before Write | After Write |
|---|---|---|
| Channel height | 41 | 42 |
| Current block hash | `VjfVVyCcKEW4FDFDCnyVuULaX6mBpH66wXXDXh1/xxw=` | `8b2OU2Vh3FBTCZTbTkS5TCbT9KdQLkpTZc0xgJoEafM=` |
| New block's previous hash | — | `VjfVVyCcKEW4FDFDCnyVuULaX6mBpH66wXXDXh1/xxw=` (matches pre-write tip) |

The new block's `previousBlockHash` equals the pre-write chain tip, confirming a genuine extension of the existing channel ledger.

---

## Honey Passport / QR Verification

The Honey Passport provides consumer-facing QR verification of honey provenance.

### Passport Journey

```
Hive → Harvest → Verification → Lab → Processing → Packaging → Distribution
```

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

Scoping: beekeepers see only their own data; FPO/processor see their org's data; lab/buyer/institution/admin have broader read access.

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
| Flutter app (offline-first) | ✅ VERIFIED | `flutter test` → 112 passed, `flutter analyze` clean |
| Flutter ↔ backend (beekeeper path) | ✅ INTEGRATED | `honey_api_service` — real login, server hives/harvests, Fabric-anchored evidence, live chain status |
| FastAPI backend | ✅ VERIFIED | `pytest` → 157 passed, 3 skipped |
| Supabase schema (migrations 001–008) | ✅ APPLIED | Migrations applied to live project |
| Backend repository abstraction | ✅ REAL | InMemory + Supabase repositories |
| Evidence bundles + Merkle integrity | ✅ VERIFIED | Unit tests with tamper detection |
| Event ledger (hash-chained) | ✅ VERIFIED | Append-only, fork-preserving |
| BlockchainGateway + tx state machine | ✅ VERIFIED | PENDING → SUBMITTED → CONFIRMED |
| Local dev ledger | ✅ REAL | Labeled `local` in every response |
| EVM adapter boundary | ⚠️ NOT CONFIGURED | Returns `BLOCKCHAIN_NOT_CONFIGURED` |
| Fabric adapter | ✅ VERIFIED LIVE | Real EC2 Fabric proven with committed tx + read-back |
| Lab certificate issue/verify/revoke | ✅ VERIFIED | Content-hash anchoring + revocation |
| Trust tiers | ✅ VERIFIED | Weakest-tier merge logic tested |
| RBAC matrix | ✅ VERIFIED | 7 roles × ~24 actions, server-side |
| Honey Passport | ✅ REAL | PII-free public view |
| Hive Intelligence risk engine | ⚠️ RULE-BASED | Not a trained model; reports "insufficient data" |
| ML artifacts | ⚠️ DEMO | `ml/model.pkl` and metrics are demo artifacts |

### What Is NOT Verified

| Component | Status | Blocker |
|---|---|---|
| Live Supabase writes | NOT VERIFIED | No `SUPABASE_SERVICE_ROLE_KEY` provided |
| EVM anchoring | NOT CONFIGURED | No RPC + wallet + deployed contract |
| Public Fabric access | SSH TUNNEL ONLY | EC2 security group does not open port 9446 |
| Docker container builds | NOT RUNNING | Docker daemon not running in this environment |
| Camera/QR on hardware | NOT TESTED | Widget tests only; no device access |
| Real Android device E2E | NOT TESTED | No device/emulator in this environment |
| Production release signing | NOT READY | Release APK builds but is debug-signed; keystore not provisioned |

---

## Test Results

### Backend — pytest

**157 passed, 3 skipped** (default suite)

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

### LIVE_RUNTIME — against real EC2 Fabric

**3 passed** (when the EC2 gateway is reachable via SSH tunnel)

```
test_live_health_check        PASSED
test_live_verify_anchor_probe PASSED
test_live_submit_and_verify   PASSED
```

### Flutter — flutter test

**112 passed** — beekeeper portal, recording harvests, hive details/alerts, honey passport drilldown, disease screening (rule-based), IoT simulation warnings, responsive smoke tests, backend API service (auth/hives/harvests/batches/evidence/Fabric status mapping), offline queue + restart durability, no-duplicate sync, backend-mode guards, the API config policy gate (HTTPS / localhost / emulator host), the canonical auth/session state machine, workspace switching (see `docs/AUTH_SESSION_MODEL.md`, `docs/ROLE_UX_MAP.md`), and the online passport verification client (see `docs/QR_HONEY_PASSPORT.md`).

**One session, many workspaces:** a signed-in account can switch between the Beekeeper, Organization / FPO, Buyer and Consumer experiences from the More tab without logging out and without re-entering a persona login. The active workspace is persisted, a backend-backed account is narrowed to the workspaces its role is actually allowed to enter, and `logout` never deletes local domain records or the pending-sync queue.

**Beekeeper ↔ backend integration (`lib/services/honey_api_service.dart`):** when the app is built with `--dart-define=API_BASE_URL=…`, the login screen offers a real backend sign-in (`demo@honeychain.in` / `HoneyChainDemo!1`, role `beekeeper`). Once signed in, My Hives shows the beekeeper's server hives (create hive posts to the backend), recording a harvest pushes it to `/api/v1/harvests` and anchors the evidence bundle onto the live Fabric chain (`POST /api/v1/evidence/bundles` with `anchor: true`), and the Blockchain screen shows the real chain status (`/api/v1/blockchain/health` + `/status`) with on-chain verify. Offline demo/OTP login remains the fallback when no backend URL is compiled in.

**Config policy (fail-fast):** the app never hardcodes a backend or secrets. `API_BASE_URL` is injected at build time; production/staging must be `https://`, and plain `http://` is allowed only for `localhost`, `127.0.0.1` or the Android emulator host alias `10.0.2.2`. A compiled-but-rejected URL aborts startup with an explicit error instead of silently running without a backend.

### Android builds

- **Debug APK** — built and verified on this machine: `releases/honeychain-2.0.2+4-debug.apk`.
- **Release APK** — `releases/honeychain-2.0.2+4-release.apk` (74.7 MB) builds, but uses the **debug signing key** (signingConfig from the template), so it is NOT Play-Store-ready. A real release keystore must be provisioned before distribution.
- **Real-device E2E** — NOT TESTED: no Android device/emulator is available in this environment (`flutter devices` lists only Windows/Chrome/Edge).

### Test Integrity

- Unit tests use mocked Fabric HTTP interactions and are labeled `UNIT`.
- LIVE_RUNTIME tests use the real Fabric gateway.
- No simulated blockchain success is represented as live blockchain verification.
- Truth status is documented in [`docs/FINAL_TRUTH_REPORT.md`](docs/FINAL_TRUTH_REPORT.md).

---

## Project Structure

```
HC-3.0-main/
├── lib/                        Flutter application (offline-first, model/service/screen split)
│   ├── bee_health/             Bee health screening (question engine, knowledge, prediction)
│   ├── core/                   API client, Supabase config
│   ├── data/                   Local repository, demo seed, HoneyChainStore
│   ├── l10n/                   Localized strings
│   ├── models/                 Domain models (honey_batch, domain, iot, disease)
│   ├── repositories/           Local/mock data boundaries
│   ├── screens/                38+ screens (beekeeper portal, org portal, scanner, etc.)
│   ├── services/               Trust, trace QR, hive insight, batch, speech, and more
│   ├── theme/                  Cream/orange/green theme
│   ├── utils/                  Formatting utilities
│   └── widgets/                20+ reusable presentation components
│
├── backend/                    FastAPI backend
│   ├── app/
│   │   ├── adapters/           Blockchain (gateway + local/evm/fabric) + AI (risk engine)
│   │   ├── api/routes/         17 HTTP route modules
│   │   ├── core/               Config, security, RBAC, crypto, logging
│   │   ├── db/                 Supabase / InMemory / DemoSeeded repositories
│   │   ├── schemas/            14 Pydantic schema modules
│   │   └── services/           16 domain services
│   └── tests/                  24 test files (pytest)
│
├── fabric-gateway-service/     Node.js Fabric Gateway HTTP service
│   └── src/                    index.js, config.js, fabricGateway.js, chaincode.js
│
├── fabric/                     Hyperledger Fabric network definition
│   ├── chaincode/tracer/       Local chaincode source (NOT what is deployed on EC2)
│   ├── crypto-config/          MSP identity material
│   └── scripts/                Network start + chaincode deploy scripts
│
├── supabase/                   Versioned SQL migrations + migration runner
│   ├── migrations/             8 idempotent migration files (001–008)
│   └── scripts/                Node.js migration applier
│
├── ml/                         Machine learning artifacts (demo)
│   ├── artifacts/              model.pkl, metrics, inference checks
│   ├── data/                   Training dataset
│   └── reports/                Confusion matrix, decision tree
│
├── test/                       Flutter widget tests
├── docs/                       26 documentation files + evidence/
├── assets/                     Flutter assets (bee_health knowledge)
├── releases/                   APK builds (v2.0.2 debug + release)
└── .github/workflows/          Flutter CI (GitHub Actions)
```

---

## Setup / Development

### Prerequisites

- Flutter SDK (stable channel)
- Python 3.14+ with pip
- Node.js 18+ with npm
- Supabase project (optional — app runs standalone without it)

### Backend

```bash
cd backend
python -m venv ../.venv_backend
../.venv_backend/Scripts/pip install -r requirements.txt
../.venv_backend/Scripts/pip install -r requirements-dev.txt

# Copy and configure environment
cp .env.example .env
# Edit .env with your settings

# Run the server
../.venv_backend/Scripts/uvicorn app.main:app --port 8000
```

API docs available at `http://localhost:8000/docs` in development mode.

### Flutter

```bash
# Copy and configure environment
cp .env.example .env
# Edit .env with your Supabase project settings

# Run the app
flutter pub get
flutter run

# Or with Supabase defines
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co \
            --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Without the `--dart-define` flags, the app runs standalone in mock/offline mode with no network dependency.

### Supabase Migrations

```bash
cd supabase/scripts
cp .env .env.local  # configure SUPABASE_DB_URL
npm install
node apply_migrations.js
```

### Fabric Gateway Service

```bash
cd fabric-gateway-service
cp .env.example .env
# Configure FABRIC_PEER_ENDPOINT, MSP paths, TLS cert
npm install
npm start
```

---

## Environment Variables

### Root `.env.example` (Flutter + Backend)

| Variable | Purpose |
|---|---|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_PUBLISHABLE_KEY` | Client-safe Supabase key (safe to ship) |
| `SUPABASE_DB_URL` | Direct PostgreSQL connection (migrations only) |
| `API_ENV` | `development` or `production` |
| `JWT_SECRET` | Required in production |
| `SUPABASE_SERVICE_ROLE_KEY` | Required for backend Supabase writes |
| `BLOCKCHAIN_ADAPTER` | `local`, `evm`, or `fabric` |
| `FABRIC_CHANNEL` | e.g. `mychannel` |
| `FABRIC_CHAINCODE` | e.g. `honeychain` |
| `FABRIC_GATEWAY_URL` | e.g. `http://localhost:9446` |
| `AI_ADAPTER` | `risk_engine` (rule-based) |

### Fabric Gateway Service `.env.example`

| Variable | Purpose |
|---|---|
| `FABRIC_PEER_ENDPOINT` | Peer endpoint (e.g. `localhost:7051`) |
| `FABRIC_PEER_HOST_ALIAS` | Peer hostname for TLS |
| `FABRIC_MSP_ID` | MSP identity (e.g. `Org1MSP`) |
| `FABRIC_CERT_PATH` | Admin certificate path |
| `FABRIC_KEY_PATH` | Admin private key path |
| `FABRIC_TLS_CA_CERT_PATH` | TLS CA certificate |
| `FABRIC_CHANNEL` | Channel name |
| `FABRIC_CHAINCODE` | Chaincode name |
| `FABRIC_GATEWAY_PORT` | Service port (default: 9443) |

**Never commit real credentials.** All `.env` files are gitignored. Only `.env.example` files with placeholders are tracked.

---

## Fabric Development

### Local Development vs. Live AWS Fabric

| Environment | Purpose |
|---|---|
| Local Fabric (`fabric/`) | Definition and scripts for local dev network (Docker Compose) |
| AWS Fabric (EC2) | Live network used for runtime verification |

**The existing AWS Fabric deployment is treated as an external dependency. Do not reset or redeploy it unless intentionally performing a controlled deployment procedure.**

### Current Chaincode State

- Chaincode: `honeychain` v2.0
- Sequence: 6
- Org1 + Org2 approved
- Channel: `mychannel`

### Network Reachability

EC2 security group does not currently open port 9446 inbound. Access is via SSH tunnel to the EC2 instance hosting the Fabric network (see `docs/BLOCKCHAIN.md` for connection details).

For 24/7 production, the security group must open port 9446 or FastAPI must run on EC2.

---

## Truth & Verification Policy

HoneyChain follows a strict evidence hierarchy:

```
Verified runtime evidence
  > tests / infrastructure evidence
    > configuration
      > documentation
        > claims / assumptions
```

Every major status should be evidence-backed.

### Examples

| ✅ Good | ❌ Bad |
|---|---|
| "Blockchain anchored" (backend confirms actual state) | "Blockchain verified" (UI only generated a hash) |
| "Blockchain integration configured" (runtime connectivity not yet verified) | "Blockchain production-ready" (no live transactions) |
| "AI-assisted risk assessment" (rule-based recommendation) | "AI detected disease" (only generated a recommendation) |
| "157 passed, 3 skipped" (exact test count) | "160 tests passed" (inflated count) |

Full truth audit: [`docs/FINAL_TRUTH_REPORT.md`](docs/FINAL_TRUTH_REPORT.md)

---

## Security Notes

- Secrets stay server-side; `.env` files are gitignored
- Supabase secret key is never shipped to Flutter — only the publishable key
- Blockchain private keys / MSP material are never committed
- Authentication and authorization remain backend-controlled (RBAC matrix)
- Idempotency protects repeated operations (`client_id` upserts)
- Conflict history is preserved (fork-recording, not auto-merge)
- Raw photos / lab sheets / PII never placed directly on-chain — only SHA-256 hashes
- Blockchain is not treated as a substitute for application authorization
- Rate limiting exists for public passport endpoint (in-memory; Redis recommended for production)
- Tamper endpoints are gated behind `DEMO_MODE` / 403 in production

---

## Roadmap

### ✅ Verified

- Offline-first mobile workflows
- Structured evidence capture + Merkle integrity
- Batch lineage + trust tiers
- FastAPI backend with RBAC
- Supabase schema (applied)
- Local dev ledger (honest, labeled `local`)
- Hyperledger Fabric anchoring (live EC2, verified)
- Honey Passport (PII-free, public)
- Rule-based hive intelligence
- QR camera scanning
- Voice-ready observation recording
- Split / merge / correction business logic

### 🟡 In Progress / Partially Verified

- Supabase backend writes (schema applied, writes not verified — no service-role key)
- EVM adapter (boundary code exists, no network configured)
- ML model training (demo artifacts only)
- Disease screening from photos (simulated path only)

### 🔵 Planned

- 24/7 public Fabric gateway endpoint (requires EC2 security group change or EC2-hosted FastAPI)
- Auth token on Node.js gateway for production exposure
- Richer beekeeper localization
- Advanced AI models for hive health
- IoT integrations
- Expanded organization workflows
- Advanced analytics
- Photo/media object storage
- Redis-backed rate limiting for multi-instance deployment

---

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
| 1 | Beekeeper opens mobile app | ✅ Runtime verified |
| 2 | Checks hive health scores | ✅ Rule-based engine verified |
| 3 | Ask HoneyChain identifies an observation | ✅ AI-assisted recommendations |
| 4 | Beekeeper performs inspection | ✅ Workflow verified |
| 5 | Takes photo | ⚠️ Requires device camera |
| 6 | Saves observation offline | ✅ Offline queue verified |
| 7 | Connectivity returns | ✅ Sync engine verified |
| 8 | Record synchronizes to backend | ✅ Idempotent sync verified |
| 9 | Harvest is recorded | ✅ API + tests verified |
| 10 | Evidence bundle is created | ✅ Merkle root computed |
| 11 | Evidence commitment generated | ✅ SHA-256 + Merkle tree |
| 12 | Blockchain anchor submitted | ✅ Fabric adapter verified |
| 13 | Fabric commits transaction | ✅ Live EC2 transactions |
| 14 | Backend verifies anchor | ✅ Read-back confirmed |
| 15 | Honey Passport QR displayed | ✅ QR generation verified |
| 16 | Consumer verifies provenance | ✅ Camera scan + manual entry |
| 17 | Tampered data produces mismatch | ✅ Tamper detection verified |

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
| [`evidence/live-fabric-backend-proof.md`](docs/evidence/live-fabric-backend-proof.md) | Verified Fabric integration evidence |

---

## License

This project is developed for **Smart India Hackathon 2026** (SIH26021). License terms to be determined.
