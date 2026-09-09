# HoneyChain v2

A demo build for Smart India Hackathon giving every honey batch a trusted digital identity:

**Hive → Beekeeper → FPO → Lab → Processing → Verified Marketplace → Consumer**

The app is **offline-first**: it runs fully on deterministic local mock data with **no** dependence on
physical IoT hardware, a live blockchain, or an external AI API. It is also **optionally wired to a
live Supabase project** so beekeeper/FPO records sync to the cloud when a network is available — and
it never loses locally recorded work.

## New in this build

- **First-launch role gate ("WHO ARE YOU?")** — the app opens with a two-option gate
  (`lib/screens/who_are_you_screen.dart`): tap **Beekeeper** to enter the phone + OTP login and
  portal, or **Organization / FPO** to open the lightweight org sign-in. The app returns to this
  gate after any logout.
- **Explicit trust tiers** (`lib/models/domain.dart`, `lib/services/trust_service.dart`) — every
  batch is evaluated into one of four tiers: `selfDeclared` → `organizationVerified` →
  `labVerified` → `blockchainAnchored`. The tier is derived *only* from recorded events (harvest
  links, custody, lab PASS/FAIL, anchors); merged lots take the weakest child tier and split
  child batches inherit the parent tier. The passport always shows caveats — a tier does **not**
  certify purity, taste, nutrition or health claims, and anchoring runs on **prototype mock
  infrastructure** (never "real blockchain").
- **Real connectivity + durable offline sync** — a single canonical status (CHECKING / ONLINE /
  OFFLINE / SYNCING / SYNC FAILED) driven by a connectivity service (`supabase`-created lazily,
  probed against the configured URL, with a fallback reachability check), one shared
  `SyncStatusBadge`, and an offline-first pending queue. Work recorded while offline keeps a
  `pending` status with attempt counters persisted to local storage; when connectivity returns the
  sync engine drains the queue in dependency order (harvests before batches), retries each item up
  to a cap, and never duplicates records (idempotent `client_id` upserts). The Developer screen has
  a **Sync panel** (sync now / clear log / demo sign-in & sign-out).
- **One canonical QR contract** (`lib/services/trace_qr_service.dart`) — the canonical payload is
  `honeychain://trace/<productCode>`; `honeychain://jar/<jarId>` remains parseable for legacy
  compatibility. One service class owns parse/validate/build so screens can never drift onto
  placeholder or non-standard payloads.
- **Real camera scanning** (`lib/screens/scanner_screen.dart`) via `mobile_scanner` — permission
  denial / camera unsupported / generic errors get a friendly retry UI with a manual-entry
  fallback ("Enter the code from the jar manually."). Codes resolve to jars, products or batch
  codes at runtime.
- **Unified Honey Passport** (`lib/screens/honey_passport_screen.dart`) — one screen for jars,
  products and batch codes: trust certificate card, evidence rows (what was actually recorded),
  mock-anchor notice, jar/batch identity, a recorded-event journey timeline, and a **real**
  `QrImageView` QR (no placeholder graphics).
- **Split / merge / correction business logic** (`BatchService`) — `splitBatch` enforces that
  parts sum to the parent quantity and mints new batch codes; `mergeBatches` aggregates harvest
  links and records `AGGREGATED_FROM` per child; `recordCorrection` appends a correction event
  instead of rewriting history. All three show up in the passport trust evaluation and timeline.
- **Functional developer mode** (`lib/screens/developer_screen.dart`) — reset/seed demo data,
  step any batch through custody → lab → mock anchor, IoT + disease-screen simulations, and a
  live debug panel. Tucked inside **More**; never surfaced on production-facing screens.

## Three pillars

1. **Produce smarter** — historical/IoT hive readings (temperature, humidity, weight, trend)
   produce a health score, risk level, productivity insight, and inspection recommendation.
   These are *risk predictions*, not disease diagnoses.
2. **Prove & trace** — harvest → batch → lab verification → prototype anchor → custody →
   genealogy → QR Honey Passport, evaluated into explicit trust tiers.
3. **Sell better** — verified batches go to a marketplace where buyers can request purchase.
   No payments, logistics, or carts.

## Roles

- **Beekeeper**: dashboard, hive health, risk insight, record harvest, harvest history.
- **FPO / Collection Center**: harvests, create batch, custody, verification, traceability, marketplace, QR.
- **Laboratory**: verify batches (PASS / FAIL).
- **Processor**: custody, processing, split/merge genealogy, corrections.
- **Consumer**: camera-scan a jar/product QR — or enter the code manually — to open the Honey
  Passport with live trust tier and recorded journey.
- **Regulator / Admin**: batch + audit view.

## Architecture

```
lib/
  models/       typed domain models (v2, incl. TrustTier/TrustState/BatchEvent)
  data/         local repository + deterministic demo seed
  repositories/ local/mock implementation of the data boundaries
  services/     trust, trace QR, hive insight, batch (split/merge/correction),
                verification, custody, prototype anchor, genealogy, marketplace, speech
  screens/      presentation layer (incl. org/ portal, who-are-you gate, scanner)
  bee_health/   symptom questions, illustration + result screens
  widgets/      reusable presentation components
  theme/        shared cream/orange/green theme
```

The presentation layer is separated from services and data so a future Figma-generated UI can
replace the screens without changing the business logic, models, or services.

Blockchain is intentionally present as **prototype/mock infrastructure** — it preserves record
integrity and does **not** detect counterfeit honey.

## Supabase sync

The demo syncs to an existing Supabase project (`hhxwhopaazqjdlreqhkf`) as its system of record.
The schema, RLS policies, demo users and the `get_public_passport` function all live in
`supabase/migrations/` (versioned, idempotent SQL — applied and verified against the live project).

- **App config (client-safe):** the app is compiled with the project URL and its *publishable* key
  only — never a service-role key:
  ```text
  flutter run --dart-define=SUPABASE_URL=https://hhxwhopaazqjdlreqhkf.supabase.co \
              --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
  ```
  Without these defines the app runs standalone in mock/offline mode (no network dependency). The
  publishable key is safe to ship: every table is guarded by RLS, and no client path ever holds an
  admin credential.
- **Relational access (migrations only):** `supabase/scripts/apply_migrations.js` applies the
  migrations over the project's Postgres connection. It reads `SUPABASE_DB_URL` from `.env`
  (gitignored; `.env.example` holds placeholders) and, when `SUPABASE_DB_INSECURE=1`, tolerates the
  project's self-signed TLS cert for local tooling only:
  ```powershell
  $env:SUPABASE_DB_URL = (Get-Content .env) -replace '^SUPABASE_DB_URL=', ''
  $env:SUPABASE_DB_INSECURE = '1'
  npm run apply   # from supabase/scripts
  ```
- **Demo sign-in (seeded by migration 004):** `demo@honeychain.in` (beekeeper) and
  `org@honeychain.in` (org admin), password `HoneyChainDemo!1` — sign in via the Developer screen's
  Sync panel or `DemoAuthService`.
- **Offline behavior:** any harvest/batch recorded without a connection is queued as `pending`
  (persisted, with a retry counter); the badge shows the queue size; a sync pass retries each item
  up to 3 times per pass and reports failures without dropping data. Developer screen exposes
  "Sync now", the error log, and connectivity/sync state readouts.

## Running

- `flutter analyze` — clean
- `flutter test` — all tests pass
- `flutter run` (any enabled device)
- `flutter build web` for a web bundle
- `flutter build apk --release` for an Android APK

## Backend & provenance layer

The FastAPI backend (`backend/`) adds the proof-of-integrity surfaces on top of
the sync flow. All of it is honest-by-construction:

- **Harvest Evidence Bundle** (`/api/v1/evidence/bundles`) — canonical hash per
  evidence object → Merkle root → anchored via the BlockchainGateway. Verify
  recomputes the root from stored payloads, so any payload tamper flips
  `evidence_intact: false`.
- **BlockchainGateway + adapters** (`backend/app/adapters/blockchain/`) — one
  facade, three adapters: `LocalLedgerAdapter` (dev/testing, labeled `local`),
  `EVMBlockchainAdapter` and `FabricBlockchainAdapter` (real boundaries that
  return `BLOCKCHAIN_NOT_CONFIGURED` / `FABRIC_NOT_CONFIGURED` / `UNKNOWN` when
  the network/credentials are absent). Transactions carry an explicit state
  machine; `CONFIRMED` is never fabricated.
- **Offline event ledger** — append-only, hash-chained; forks are preserved
  (losing records are never silently dropped).
- **Lab certificates** — issue/verify/revoke with `content_hash` anchoring.
- **RBAC matrix** (`backend/app/core/rbac.py`) — server-side enforcement across
  roles/actions; tamper endpoints gated behind `DEMO_MODE`.
- **Health** — `/health/live` + `/health/ready`.

Tests: backend `pytest` **110 passed**; Flutter `flutter test` **64 passed**.
Supabase migrations 001–006 applied and verified against the live project.
See `docs/` for the full control center (SERVICE_STATUS, BLOCKCHAIN,
FEATURE_STATUS, API, TESTING, ...).

## Android build notes

Latest build reaches the Gradle `assembleRelease` target (the duplicate-Kotlin "Redeclaration"
issue in the Flutter SDK tooling is fixed by removing the `(1).kt` copies). The remaining blocker
is a network resolution error downloading a Gradle dependency
(`No such host is known: dl.google.com`), i.e. connectivity during dependency fetch, not an app
code problem. Retry with a live connection, or open the project in Android Studio (`android/`) to
build the APK there.