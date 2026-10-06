# HoneyChain Web Portal

<p align="center">
  <strong>Hive-to-Home Traceability for Indian Honey</strong><br/>
  A role-based web portal for managing, verifying, and exploring HoneyChain supply-chain records.
</p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#platform">Platform</a> ·
  <a href="#portals">Portals</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#local-development">Local Development</a> ·
  <a href="#judge-demo">Judge Demo</a> ·
  <a href="#passport--qr-verification">Passport & QR</a> ·
  <a href="#deployment">Deployment</a>
</p>

---

## Overview

**HoneyChain** is a traceability platform designed to connect the honey supply chain from **beekeeper to consumer** through a shared backend and role-specific workspaces.

This repository contains the **web portal layer** of HoneyChain. It is a client of the HoneyChain backend and does not maintain an independent production dataset.

The web portal provides operational views for organizations, laboratories, processors, buyers, institutions, administrators, and beekeepers, together with a public **Honey Passport** experience that can be reached from a QR code without signing in.

### Data flow

```text
Flutter Beekeeper App
        │
        │ HTTPS REST
        ▼
HoneyChain Backend API
        │
        ├── PostgreSQL / Supabase
        │      ├── hives
        │      ├── readings
        │      ├── harvests
        │      ├── batches
        │      ├── lab tests
        │      ├── certificates
        │      ├── custody events
        │      ├── genealogy / lineage
        │      ├── notifications
        │      └── audit / platform data
        │
        ├── Blockchain / provenance status
        ├── IoT data
        └── AI / productivity services
        │
        ▼
React Web Portal
    ├── FPO / Organization
    ├── Laboratory
    ├── Processor
    ├── Buyer
    ├── KVIC / Institution
    ├── Admin
    ├── Beekeeper
    └── Public Honey Passport
```

**Single source of truth:** the live portal reads HoneyChain records from the REST API. It does not create a second client-side copy of the honey-chain dataset.

---

## Platform

The portal is built as a modern **React + TypeScript** application using **TanStack Start**, **TanStack Router**, **TanStack Query**, **Vite**, **Nitro**, and **Tailwind CSS**.

### Core capabilities

| Capability | Portal role / surface |
| --- | --- |
| Organization operations | FPO / Organization |
| Laboratory workflow | Laboratory |
| Processing & packaging | Processor |
| Procurement & traceability | Buyer |
| Institutional oversight | KVIC / Institution |
| Platform administration | Admin |
| Beekeeper-facing web experience | Beekeeper |
| Consumer verification | Public Honey Passport |
| QR generation | Passport / batch flows |
| Supply-chain lineage | Batch detail / passport |
| Custody history | Batch detail / buyer / processor |
| Blockchain status | Admin / passport surfaces |
| AI assistant integration | HoneyChain backend API |
| Productivity prediction | Separate HoneyChain model endpoint |
| Offline UI walkthrough | Explicit Offline Preview |

---

## Portals

HoneyChain exposes role-specific workspaces while keeping authorization grounded in the authenticated backend identity.

| Portal | Route | Purpose |
| --- | --- | --- |
| **KVIC / Institution** | `/kvic` | Platform-level statistics, organization clusters, rollups, and alerts. |
| **FPO / Organization** | `/org` | Harvest intake, batch creation, lab submission, packaging, custody, and notifications. |
| **Beekeeper** | `/beekeeper` | App-first beekeeper experience with hive, harvest, batch, and supply-chain state. |
| **Laboratory** | `/lab` | Lab queue, test processing, results, and certificate workflow. |
| **Processor** | `/processor` | Verified incoming batches, processing, packaging, custody, and genealogy. |
| **Buyer** | `/buyer` | Incoming lots, source information, verification state, and custody history. |
| **Admin** | `/admin` | Platform statistics, organizations, beekeepers, audit trail, blockchain status, and API health. |
| **Consumer Passport** | `/verify/<code>` | Public honey verification with no login required. |
| **Passport links** | `/passport/<code>` | Public passport route for shared links. |
| **Offline Preview** | `/login` → Offline Preview | Explicitly labeled static demo data for UI walkthroughs. |

Authorization is checked from the authenticated HoneyChain identity rather than being granted by the portal UI alone.

---

## Architecture

### Frontend

- **React 19**
- **TypeScript**
- **TanStack Start**
- **TanStack Router**
- **TanStack Query**
- **Vite**
- **Nitro**
- **Tailwind CSS**
- **Lucide React**
- **Recharts**
- **QRCode generation**

### API integration

The central live client is:

`src/lib/hc/live-api.ts`

It connects the portal to HoneyChain endpoints for:

- authentication and session lookup
- hives and hive readings
- harvests
- batches
- batch state, lineage, and genealogy
- custody events
- laboratory requests and results
- certificates
- notifications
- audit and platform statistics
- assertions and evidence
- IoT devices and telemetry
- public passports
- blockchain status and transaction lookup
- productivity prediction
- AI status and chat
- API health

### Supply-chain derivation

`src/lib/hc/supply-chain.ts` derives the visible supply-chain timeline from recorded custody events, laboratory tests, certificates, and batch state.

The portal deliberately distinguishes:

- **COMPLETED** — the stage occurred
- **PENDING** — the stage is expected but not recorded yet
- **SKIPPED** — the route did not include that stage
- **NOT_APPLICABLE** — the batch state makes the stage irrelevant
- **FAILED** — the stage occurred and failed

This avoids turning an optional route step into a false failure.

---

## Local Development

### Prerequisites

- **Node.js 20+**
- HoneyChain backend running locally

### Start the backend

From the HoneyChain backend directory:

```bash
uvicorn app.main:app --reload --port 8001
```

### Start the web portal

```bash
npm install
npm run dev
```

Default development URL:

```text
http://localhost:8080
```

The Vite development server proxies:

- `/api` → HoneyChain backend
- `/predict-productivity` → productivity model service

Default proxy targets:

```text
HoneyChain API:          http://127.0.0.1:8001
Productivity API:        http://127.0.0.1:8000
```

Override them when required:

```bash
VITE_API_PROXY=http://127.0.0.1:8001 npm run dev
VITE_PRODUCTIVITY_API_PROXY=http://127.0.0.1:8000 npm run dev
```

---

## Environment Variables

Copy:

```text
.env.example → .env.local
```

Public `VITE_*` variables are embedded into the browser bundle. **Never place secrets, admin credentials, JWT secrets, or database passwords in a `VITE_*` variable.**

| Variable | Default | Purpose |
| --- | --- | --- |
| `VITE_API_BASE_URL` | unset | Production HoneyChain API origin. |
| `VITE_API_PROXY` | `http://127.0.0.1:8001` | Development API proxy target. |
| `VITE_PRODUCTIVITY_API_PROXY` | `http://127.0.0.1:8000` | Development productivity service proxy. |
| `VITE_PUBLIC_APP_URL` | current origin | Public portal origin used when generating QR verification URLs. |

When `VITE_API_BASE_URL` is cross-origin, the backend must allow the portal origin through CORS.

---

## Authentication & Demo Access

The portal's demo flow uses seeded HoneyChain identities rather than a client-side authentication bypass.

Default seeded credentials documented by the application:

```text
Password: HoneyChainDemo!1
```

Example seeded identities include:

| Role | Account |
| --- | --- |
| Beekeeper | `demo@honeychain.in` |
| FPO / Organization | `org@honeychain.in` |

Additional roles can be provisioned through the HoneyChain authentication backend.

### Live vs Offline

The portal intentionally keeps **live mode** and **Offline Preview** separate.

**Live mode**

```text
Login
  ↓
JWT session
  ↓
HoneyChain REST API
  ↓
Live backend data
```

**Offline Preview**

```text
Explicit Preview entry
  ↓
Static demo dataset
  ↓
DEMO / PREVIEW indicator
```

If the live backend becomes unreachable, the portal reports the connection problem instead of silently replacing live records with demo data.

---

## Judge Demo

A complete cross-portal walkthrough can be demonstrated from one HoneyChain workflow.

### Suggested flow

1. Sign in as **FPO / Organization**.
2. Open the **Beekeeper** workspace and show live hives, harvests, batches, and alerts.
3. In **FPO → Collection**, select incoming harvests and create a batch.
4. In **FPO → Verification**, request a laboratory test.
5. Open **Laboratory** and process the queued test.
6. Submit the laboratory result.
7. Return to the batch and record **packaging / custody**.
8. Open **Processor** or **Buyer** to show the same batch's evolving traceability state.
9. Open **KVIC / Institution** to show platform-level rollups.
10. Open the batch's **Honey Passport**.
11. Scan the generated QR code from a phone.
12. Verify that the public passport loads **without login**.

The important demonstration point is the continuity of one record across multiple workspaces rather than isolated mock screens.

---

## Honey Yatra QR & Honey Passport Verification

The public passport is designed around a simple principle:

> **The QR identifies the record; it does not contain the passport data.**

The QR encodes a stable verification URL:

```text
/verify/<code>
```

The browser then requests the public HoneyChain endpoint:

```text
GET /api/v1/passport/<code>
```

This means the passport is **server-backed**.

### Public verification routes

```text
/verify/<code>
/passport/<code>
/passport?code=<code>
/verify?code=<code>
```

A public scan does not need an account.

### What the passport does not invent

If the backend does not return a value, the UI presents it as **Not recorded** rather than fabricating a value.

Likewise, blockchain state is shown according to the backend response:

- **Blockchain anchored**
- **Anchoring pending**
- **Blockchain anchoring unavailable**

The portal does not manufacture transaction IDs to make an unanchored record appear verified.

---

## Blockchain & Provenance

The portal exposes dedicated backend integration points for blockchain provenance:

```text
GET /api/v1/blockchain/status
GET /api/v1/blockchain/health
GET /api/v1/blockchain/transactions/<ref>
```

For a judge demonstration, the strongest evidence is the complete chain:

```text
HoneyChain event
   ↓
Backend transaction
   ↓
Blockchain anchoring
   ↓
Transaction reference / ledger evidence
   ↓
Passport verification
```

The web portal intentionally reports the backend's blockchain status rather than claiming an anchor that the backend has not confirmed.

---

## Data Integrity & Supply-Chain Evidence

HoneyChain records are designed around traceable operational evidence:

```text
Hive
  ↓
Reading / telemetry
  ↓
Harvest
  ↓
Batch
  ↓
Laboratory test
  ↓
Processing / packaging
  ↓
Custody movement
  ↓
Passport / public verification
```

The portal can retrieve supporting data through assertions, discrepancies, impacts, evidence bundles, certificates, genealogy, and custody endpoints exposed by the HoneyChain API.

---

## Productivity Prediction & AI

Productivity prediction is treated as a separate model service.

The portal calls:

```text
POST /predict-productivity
```

and surfaces the response as model output.

When the model service is unavailable, the application is designed to report that honestly rather than inventing a prediction.

The portal also integrates with HoneyChain AI endpoints:

```text
GET  /api/v1/ai/status
POST /api/v1/ai/chat
```

---

## Deployment

This project is a **TanStack Start / Nitro application**, not a plain static SPA.

The Vite configuration uses a **Vercel Nitro preset by default** and can emit a Node server bundle for alternate hosts.

### Production build

```bash
npm run build
```

### Local production preview

```bash
npm run preview
```

Default preview target:

```text
http://127.0.0.1:8081
```

### Vercel

The default Nitro preset targets Vercel.

The public API origin should be configured as:

```text
VITE_API_BASE_URL
```

### Render

The repository also includes:

```text
render.yaml
```

for a Node-server deployment using:

```text
NITRO_PRESET=node-server
```

The Render configuration starts:

```text
.output/server/index.mjs
```

Direct navigation to public passport routes must remain supported, especially for QR scans and shared links.

---

## Quality & Development Commands

Useful project commands:

```bash
npm run dev
npm run build
npm run build:dev
npm run build:node
npm run preview
npm run typecheck
npm run lint
npm test
npm run check:auth
```

The repository includes focused tests around application data, authentication gates, HoneyChain API behavior, AI integration, routing integrity, and readiness / scheduling behavior.

---

## Project Structure

The portal keeps the existing application organization centered around routes, features, components, and HoneyChain integration code.

Key areas:

```text
src/
├── components/          UI and application components
├── features/            Domain-focused portal experiences
├── lib/
│   ├── auth/             Authentication/session logic
│   ├── hc/               HoneyChain API, models, passport, QR, lineage
│   └── ...               Supporting application utilities
├── routes/               TanStack Start routes
└── styles.css            Global styling

server/                   Server-side helpers / middleware
scripts/                  Development and build tooling
render.yaml               Render deployment definition
vite.config.ts            Vite + TanStack Start + Nitro configuration
.env.example              Environment variable template
```

---

## Design Principles

HoneyChain's web portal is built around a few practical principles:

**One backend, many workspaces**  
Different actors see different operational surfaces while working from the same HoneyChain records.

**Traceability over templates**  
Supply-chain timelines are derived from recorded events instead of a fixed story that every batch is forced to follow.

**Public verification without public editing**  
Consumers can verify a passport without an account, while write operations remain behind authenticated backend endpoints.

**No silent demo fallback**  
Offline Preview is explicit. A failed live connection does not silently turn real operations into synthetic data.

**Honest evidence**  
Missing records remain missing, optional stages remain optional, and blockchain status is shown only when the backend reports it.

---

## License

This repository is distributed under the project's selected license.

See the repository license file for the authoritative terms.

---

<p align="center">
  <strong>HoneyChain</strong><br/>
  Hive → Harvest → Batch → Lab → Processing → Custody → Passport
</p>
