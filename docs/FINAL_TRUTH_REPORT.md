# Final Truth Report — HoneyChain 3.0

**Date:** 2026-09-11
**Audit method:** source inspection + `git ls-files` / `git status` + live runtime proof against
the EC2 Hyperledger Fabric network + `flutter analyze` / `flutter test` / Android APK builds.
Nothing in this report is fabricated; anything not directly
proven is explicitly marked `NOT VERIFIED`.

## 1. Classifications used

| Label | Meaning |
|---|---|
| VERIFIED | executed against real infrastructure, evidence captured |
| REAL | genuine implementation running on real infra (code inspected) |
| PARTIAL | works but has known limits |
| SIMULATED / MOCK | explicitly labeled, never presented as live |
| NOT CONNECTED / NOT VERIFIED | exists but was not executed / not proven |
| BLOCKED | cannot complete without external action |

## 2. Foundation — backend (VERIFIED by test execution)

| Area | Status | Evidence |
|---|---|---|
| pytest backend suite | 157 passed / 3 skipped | `docs/TEST_RESULTS.md` (+ test run 2026-09-11) |
| Flutter suite | 112 passed, analyze clean | `docs/TEST_RESULTS.md` (Flutter 3.47.1) |
| Flutter ↔ backend (beekeeper path) | INTEGRATED | `honey_api_service` — real login, hives/harvests, Fabric-anchored bundles, live chain status (unit-tested with MockClient; full live E2E from the device NOT TESTED — see below) |
| Config / repository / services layers | REAL | source in `backend/app`, covered by unit tests |
| Supabase schema migrations | REAL, applied to live project (per prior session) | `supabase/` migrations |
| Supabase **writes** | NOT VERIFIED | no `SUPABASE_SERVICE_ROLE_KEY` in this environment |

## 3. Blockchain layer — VERIFIED against real Fabric

| Column | Status |
|---|---|
| `BlockchainGateway` / tx state machine | REAL, unit-tested (25 tests) |
| `LocalLedgerAdapter` (dev ledger) | REAL, honestly labeled `local` |
| `EVMBlockchainAdapter` | boundary only → `BLOCKCHAIN_NOT_CONFIGURED` (no network) |
| `FabricBlockchainAdapter` | REAL + VERIFIED live |
| Node.js gateway service | REAL, deployed on EC2 as systemd `honeychain-fabric-gateway` (port 9446) |
| Live chaincode contract mapping | VERIFIED — real source read from chaincode container, functions called live |
| Chaincode identity on ledger | VERIFIED — `honeychain` v2.0 seq 6, Org1+Org2 approved, escc/vscc |

### Live, read-back, real transactions (VERIFIED)

| Tx ID (blockchain) | Chaincode fn | How proven |
|---|---|---|
| `dbcbd8feeff5761c98736c114d9a0f699b2d616398f6c8a1d9075728b52ad2cf` | `anchorMerkleRoot` (HC-DEMO-001) | gateway returned `committed`, read-back via `getAnchor` |
| `93698012206aa1664c90d7a71258390a4f10d8bc4f80ebe8ebcf02e8c2665e29` | `submitEvent` (PROVENANCE_ANCHORED) | `committed`, read-back via `getEvent` |
| `52c7801a3e1d05a89e8cb03e76ad38176e359a57fb49745ee0b6b04a62bd0fe4` | `createBatch`+`anchorMerkleRoot` full chain via **Python** | adapter `CONFIRMED`, `getAnchor` read-back |
| `d9f71c53cc8036ff306b70ce3aa14508181271ecb0a039f54a8ede9a2079660c` | `anchorMerkleRoot` block-height probe | `committed` (2067 ms), channel height 41 → 42, previous-hash links old tip |

### Chain-level proof (VERIFIED)

`peer channel getinfo -c mychannel` before/after a real write:
height **41 → 42**, new current hash `8b2OU2Vh3FBTCZTbTkS5TCbT9KdQLkpTZc0xgJoEafM=` with
`previousBlockHash = VjfVVyCcKEW4FDFDCnyVuULaX6mBpH66wXXDXh1/xxw=` (pre-write tip). The new
block is a genuine extension of the existing channel, not a rebuild.

## 4. Truth-leak audit (no misrepresentation)

Grep across `backend/app` for `simulated|mock|fabricat|fake`:
- Every hit is an **honest label**: IoT readings carry `is_simulated=True` /
  `source='simulation'`; the AI risk engine receives `simulated=False` by default; the
  gateway docs say "never fabricates success / never faked statuses"; `simulated` is only a
  legacy alias for the `local` dev ledger (never for a real chain).
- Real tx IDs appear **only in `docs/`**, never hardcoded in application code or unit tests.
- The only "mock" objects in the backend live in `backend/tests/` (MagicMock for HTTP) and are
  used solely by UNIT tests; `LIVE_RUNTIME` tests are the only code that touches real Fabric.

Grep across `lib/` for `MOCK|FAKE|TODO|FIXME|not implemented|placeholder`:
- No `TODO/FIXME/not implemented` markers in app code; only localized input-field
  "placeholder" strings.
- Every mock/anchor reference is visibly labelled `(mock)` or sits behind
  `blockchain.mock.notice` ("PROTOTYPE / MOCK BLOCKCHAIN"). The new beekeeper Fabric path
  (`honey_api_service`) carries no mock labels — it reports real backend/chain data or an
  honest "anchor pending" state when the backend is unreachable.
- QR codes are plain `honeychain://trace/<code>` schemes, **not** cryptographically signed —
  the app never claims otherwise.

## 5. Security audit (VERIFIED findings)

| Check | Result |
|---|---|
| `.env` / `*.env.local` / `fabric-gateway-service/.env` gitignored | PASS (`git check-ignore`) |
| Tracked files contain env files? | NO — only `.env.example`s are tracked |
| Private keys / certs in tracked files | NONE (only `BEGIN PUBLIC KEY` assertions in tests) |
| `fabric-gateway-service/` git status | untracked/new (never committed) — no secret leakage |
| Backend secret handling | envar-driven; `SUPABASE_SERVICE_ROLE_KEY` never committed |
| Flutter app credential exposure | NONE — Supabase/backend config is injected via `--dart-define` only; no keys/tokens/URLs in `lib/` or `android/` |
| Startup config gate | `ApiConfig.startUpIssue` aborts any build with a rejected `API_BASE_URL` instead of silently running without a backend |
| Gateway service auth | HTTP on localhost only; EC2 security group does not expose 9446 (SSH tunnel required) |

Ongoing item (not a leak): the gateway binds 9446 on EC2 with no token; keep it firewalled
until a token (e.g. shared secret in `.env`) is added for production exposure.

## 5c. Session / workspace / passport layer (2026-09-11)

| Check | Result |
|---|---|
| Canonical auth state machine | ADDED — single `AuthState` derived from persisted login + backend config + connectivity (`docs/AUTH_SESSION_MODEL.md`) |
| Backend JWT survives restart | FIXED — `ApiTokenStore.instance.init()` is now called during startup and the JWT identity/role is restored (`docs/AUTH_SESSION_MODEL.md`) |
| Workspace switching without re-login | ADDED — More tab switcher; organization/buyer/consumer open directly, no persona login (`docs/ROLE_UX_MAP.md`) |
| Logout preserves local records | VERIFIED (test) — `logout()` clears only the session flag; domain data + pending-sync queue stay |
| Online passport verification | ADDED — `GET /api/v1/passport/{code}` client with honest states; `verify` only when the backend actually returns a real anchor (`docs/QR_HONEY_PASSPORT.md`) |
| Never-fabricated verification | PASS — no `API_BASE_URL` build → panel says "not available in this build", never a fake result |

## 5b. Android build status (2026-09-11)

| Artifact | Status |
|---|---|
| Debug APK | `releases/honeychain-2.0.2+4-debug.apk` — built ✅ |
| Release APK | `releases/honeychain-2.0.2+4-release.apk` (74.7 MB) — built ✅ but **debug-signed** (template signingConfig) → NOT Play-Store-ready |
| Real device/emulator E2E | **NOT TESTED** — no Android device/emulator in this environment (`flutter devices` = Windows/Chrome/Edge only) |
| Network-failure test on device | **NOT TESTED** for the same reason; offline queue is covered by widget/unit tests |

## 6. What we honestly do NOT claim

- ❌ "Supabase is live-written" — no service-role key available → NOT VERIFIED.
- ❌ "EVM is live" — no RPC/wallet/contract → boundary only.
- ❌ "Fabric is reachable from the public internet" — port 9446 is NOT open in the EC2
  security group; 24/7 exposure needs the group opened or FastAPI running on EC2.
- ❌ "The Fabric chaincode is `tracer.js`" — corrected: the deployed contract is
  `honeychain.js` (see `docs/evidence/live-fabric-backend-proof.md`).
- ❌ "Any block number, MSP, or tx was invented" — none were; every number above was read
  from the running chain.
- ❌ "The Android app was exercised on real hardware" — no device/emulator available;
  E2E from the phone is NOT TESTED.
- ❌ "The release APK is store-ready" — it builds but is debug-signed; a keystore must be
  provisioned.
- ❌ "QR payloads are cryptographically signed" — they are plain readable schemes that the
  backend/ledger data backs; no signature claim is made.

## 7. Action items for full 24/7 production status

1. Open EC2 security group inbound for the gateway port (or co-locate FastAPI on EC2).
2. Add an auth token to the Node gateway before exposing it.
3. Provide `SUPABASE_SERVICE_ROLE_KEY` to verify Supabase writes.
4. Optionally deploy FastAPI behind a reverse proxy on EC2.