# HoneyChain

**Hive-to-Consumer Traceability and Rural-First Smart Beekeeping**

HoneyChain is an integrated digital platform for the Indian honey value chain. It connects rural beekeepers, FPOs and collection centres, laboratories, processors, buyers, consumers, KVIC and institutional stakeholders around a common batch identity.

The platform is designed around one core idea:

> **The evidence should travel with the honey.**

A harvest record created at the hive should remain connected to collection, laboratory verification, custody, processing, packaging and public verification instead of becoming a disconnected certificate, receipt or spreadsheet.

## What HoneyChain provides

- **Rural-first beekeeper experience:** offline-first hive, inspection, reading and harvest capture with multilingual/conversational assistance.
- **Batch traceability:** hive → harvest → collection → laboratory → processing → packaging → custody → consumer.
- **Honey Yatra QR:** a persistent package QR that identifies a server-backed Honey Passport; the QR does not contain the whole provenance record.
- **Evidence integrity:** SHA-256 commitments, Merkle proofs, hash-chained event records and ECDSA P-256 device-reading attribution.
- **Permissioned provenance:** Hyperledger Fabric for governed participants and confirmed ledger evidence.
- **AI assistance:** Ask My Bee, hive-health screening, telemetry anomaly detection and productivity-prediction integration.
- **FPO market linkage:** verified lots, procurement requests and sale/custody recording.
- **KVIC field operations:** cluster visibility and a mobile processing-van submodule.
- **Public consumer verification:** no-login Honey Passport lookup with honest verification and blockchain states.

## Repository structure

```text
HoneyChain-Hexanexus/
├── lib/                         Flutter mobile application
├── backend/                    FastAPI backend and domain services
├── fabric-gateway-service/     Node.js/TypeScript Fabric gateway
├── fabric/                     Fabric/chaincode deployment material
├── ml/                         ML training/data/model material
├── supabase/                   PostgreSQL schema and migrations
├── docs/                       Architecture, operations, testing and security
├── web-portal/                 Integrated React/TypeScript web portal
├── test/                       Flutter application tests
└── backend/tests/              Backend tests
```

## System architecture

```text
RURAL / FIELD
Flutter Beekeeper App
  ├─ Offline-first hive + inspection + harvest capture
  ├─ Hive readings / alerts
  ├─ Ask My Bee
  └─ Honey Yatra QR / Honey Passport

                 HTTPS REST
                      │
                      ▼
CENTRAL SERVICE
Python / FastAPI
  ├─ Authentication + RBAC
  ├─ Sync + idempotent writes
  ├─ Batch / harvest / custody workflows
  ├─ Laboratory + certificate workflows
  ├─ Market linkage
  ├─ QR package identity + reuse detection
  ├─ Honey Passport
  ├─ AI / ML integrations
  └─ Provenance / evidence services

              ┌───────┴────────┐
              ▼                ▼
        PostgreSQL /        Fabric Gateway
        Supabase              │
              │               ▼
              │        Hyperledger Fabric
              ▼
      Web Portal / APIs
        ├─ FPO / Collection
        ├─ Laboratory
        ├─ Processor
        ├─ Buyer / Procurement
        ├─ KVIC / Institution
        ├─ Admin / Platform
        ├─ Beekeeper web surface
        └─ Public Honey Passport
```

## Web portal

The integrated web portal lives in `web-portal/`. It is the operational web layer over the HoneyChain backend; it is not a second production database.

Detailed capability documentation:

- [Portal Capability Matrix](docs/PORTAL_CAPABILITY_MATRIX.md)
- [Security Audit](docs/SECURITY_AUDIT.md)
- [Honey Yatra QR & Honey Passport](docs/QR_HONEY_PASSPORT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Data Model](docs/DATA_MODEL.md)
- [API](docs/API.md)
- [Deployment](docs/DEPLOYMENT.md)
- [Testing](docs/TESTING.md)
- [Known Limitations](docs/KNOWN_LIMITATIONS.md)

## Portal roles and surfaces

| Surface | Route | Primary purpose |
|---|---|---|
| Admin / Platform | `/admin`, `/admin/platform` | Platform administration, organisations, members, audit, health, ledger and cross-workspace operations |
| KVIC / Institution | `/kvic` | Cluster oversight, statistics, alerts and mobile processing-van operations |
| FPO / Collection | `/org` | Harvest intake, batch formation, laboratory requests, market linkage and operational notifications |
| Beekeeper | `/beekeeper` | Hive, harvest and field-state visibility on the web |
| Laboratory | `/lab` | Laboratory test queue, testing state and PASS/FAIL result workflow |
| Processor | `/processor` | Incoming/verified lots, processing, packaging, custody and Honey Yatra QR package operations |
| Buyer / Procurement | `/buyer` | Verified lots, procurement requests, seller decisions and fulfilment |
| Ask My Bee | `/ask-my-bee` | Conversational operational guidance |
| Alerts | `/alerts` | Action-required notifications |
| Honey Passport | `/verify/<code>`, `/passport/<code>` | Public product verification without login |

**Honey Yatra QR, market linkage, genealogy, blockchain status and the KVIC mobile-processing-van workflow are capabilities inside these surfaces, not separate portals.**

## Beekeeper application

The Flutter application is the rural-first field surface.

Core capabilities include:

1. Create and manage hives.
2. Record hive conditions, inspections and field observations.
3. Submit hive readings and receive understandable alerts.
4. Record harvests while offline.
5. Synchronise queued changes after reconnecting.
6. Review harvest history and batch state.
7. Review hive-health screening and associated guidance.
8. Record/track treatment follow-up information where supported by the workflow.
9. Open and review the Honey Passport.
10. Use Ask My Bee for natural-language assistance.
11. Use camera/manual QR scanning for Honey Yatra verification.
12. Continue working locally when the backend is unavailable, with the UI explicitly showing offline or unverified states instead of inventing success.

See [Mobile Live Flow](docs/MOBILE_LIVE_FLOW.md) and [Role / Workspace UX Map](docs/ROLE_UX_MAP.md) for the current mobile behavior.

## Honey Yatra QR

Honey Yatra QR is the product name for the consumer-facing QR capability.

The design separates the physical label identity from the provenance data:

```text
Printed QR
   │
   │ stable verification URL / package identity
   ▼
HoneyChain public verification endpoint
   │
   ▼
Current package + batch record
   ├─ source / origin
   ├─ harvest
   ├─ laboratory evidence
   ├─ processing / custody
   ├─ package state
   └─ blockchain anchor state
```

The QR is **not itself a cryptographic signature**. It identifies a server-backed record. The backend applies rate limiting and returns only public, PII-free passport information.

Reuse/clone detection records scan history and can flag signals such as unknown codes, recalled packages, duplicate prints, reuse by another organisation and excessive scans.

Existing QR schemes remain backward-compatible in the parser where required. Human-facing documentation and UI use **Honey Yatra QR**.

## Provenance and evidence

The evidence model is layered:

```text
Hive
  ↓
Harvest
  ↓
Batch
  ↓
Laboratory verification
  ↓
Processing / packaging
  ↓
Custody
  ↓
Honey Yatra QR
  ↓
Public Honey Passport
```

Integrity mechanisms include:

- canonical payload hashing with SHA-256
- Merkle bundle roots and proofs
- hash-chained offline event records
- ECDSA P-256 for IoT device-reading attribution
- Hyperledger Fabric commitments and event anchoring
- explicit transaction states such as pending, submitted, confirmed, failed and unavailable

HoneyChain deliberately distinguishes **record integrity/provenance** from physical honey authenticity. A blockchain anchor proves what was recorded and committed; it does not physically prevent adulteration of the contents of a jar.

## AI and ML

### Ask My Bee

Ask My Bee is the conversational interface for operational assistance. The backend exposes AI status and chat endpoints and uses tool calling for domain actions. Write operations require confirmation.

### Hive-health screening

The current application includes a Decision Tree based screening workflow. It is a risk/screening aid and not a medical-style diagnosis system.

### Telemetry anomaly detection

Telemetry anomaly detection uses a One-Class SVM integration path.

### Productivity prediction

Productivity prediction is treated as a separate model-service integration. The portal reports the model as unavailable when the service is not configured rather than fabricating a prediction.

## Government / KVIC operations

The institutional surface provides:

- cluster and organisation status
- programme/platform statistics
- batch trust mix
- alerts requiring institutional attention
- field workflow visibility
- mobile processing-van visits
- visit lifecycle management
- field sample collection
- field sample result capture

A KVIC field result is not the same as an accredited laboratory certificate; the van module records field operations without silently changing the laboratory trust state.

## Market linkage

Market linkage is integrated into the FPO, processor and buyer workflows:

```text
Verified batch
      ↓
Seller listing
      ↓
Buyer request
      ↓
Seller accept / reject
      ↓
Fulfilment
      ↓
Sale custody event
```

Quantity checks and state transitions are enforced by the backend. The buyer UI is not treated as the security boundary.

## Authentication and authorization

HoneyChain uses server-side role/permission enforcement.

Backend roles include:

- beekeeper
- FPO
- laboratory
- processor
- buyer
- institution
- platform oversight
- admin
- retailer where applicable

The permission matrix is defined in `backend/app/core/rbac.py`.

The browser cannot grant itself a role by hiding or displaying a button. Backend authorization remains authoritative.

The web portal also contains server-side request isolation and authenticated-route gates. Public Honey Passport endpoints intentionally remain unauthenticated.

## Development

### Backend

```bash
cd backend
uvicorn app.main:app --reload --port 8001
```

### Web portal

```bash
cd web-portal
npm install
npm run dev
```

### Quality checks

```bash
# web portal
npm run typecheck
npm run lint
npm test
npm run build

# backend
pytest

# Flutter
flutter analyze
flutter test
```

Use the repository's own environment templates and never place server secrets into Flutter `--dart-define` values or Vite `VITE_*` variables unless they are explicitly public values.

## Deployment

The backend Render definition is in the repository root `render.yaml`.

The web portal has its own deployment definition in:

```text
web-portal/render.yaml
```

The portal supports Vercel/Nitro output and a Node-server Render target.

Public URLs are configuration:

```text
VITE_API_BASE_URL
VITE_PUBLIC_APP_URL
```

Secrets such as JWT secrets, Supabase service-role keys, Gemini keys and Fabric bridge tokens must remain server-side.

## Current security posture

Security controls currently include:

- PBKDF2-HMAC-SHA256 password hashing with 480,000 iterations
- environment-only JWT secrets
- production refusal when JWT secret is missing
- server-side RBAC/permission checks
- resource/org scope checks
- public passport rate limiting
- HMAC-authenticated internal Fabric bridge
- production-disabled demo tamper endpoints
- explicit CORS configuration
- no silent live→demo fallback in the web portal
- public Honey Passport restricted to PII-free fields
- explicit distinction between laboratory verification and blockchain anchoring

Known hardening items are documented in [Security Audit](docs/SECURITY_AUDIT.md).

## Naming policy

This repository now uses **HoneyChain** as the product name, without project-version labels.

- Product: **HoneyChain**
- Consumer QR system: **Honey Yatra QR**
- Consumer public view: **Honey Passport**
- Web layer: **HoneyChain Web Portal**

Internal compatibility namespaces such as `src/lib/hc` remain unchanged where renaming them would create unnecessary import/API breakage. They are implementation paths, not product branding.

## Project principle

HoneyChain does not attempt to make one technology solve every problem. It connects the evidence already produced by the honey ecosystem into one traceable workflow, then adds rural-first tooling, verification, market linkage and governed provenance around it.

**Hive → Harvest → Batch → Lab → Processing → Custody → Honey Yatra QR → Consumer.**
