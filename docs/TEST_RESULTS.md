# Test Results — Verified Matrix

**Date:** 2026-09-11
**Backend interpreter:** `C:\Users\Admin\AppData\Local\Python\pythoncore-3.14-64\python.exe` (pytest via that env)
**All Fabric HTTP interactions in unit tests are mocked and labeled `UNIT`.**

## Backend suite (default run)

Command: `cd backend && ..\.venv_backend\Scripts\python.exe -m pytest -q`

Result: **157 passed, 3 skipped** (about 61s).

The 3 skipped are `LIVE_RUNTIME` tests gated by
`@pytest.mark.skipif(not get_settings().fabric_gateway_url, ...)`.

| Area | Result |
|---|---|
| `tests/test_fabric_adapter.py` (UNIT) | 25 passed, 3 skipped |
| All other backend tests | 132 passed |
| **Total** | **157 passed / 3 skipped** |

## LIVE_RUNTIME suite (against real EC2 Fabric)

The live tests need the EC2 gateway reachable. Because EC2's security group does
not expose port 9446, the proof used a persistent SSH tunnel wrapper that keeps
the tunnel alive for the whole pytest process:

```
ssh -N -L 9446:localhost:9446 -i D:\HACKATHON\HoneyChain\honeychain-key.pem ubuntu@13.127.118.165
env: FABRIC_GATEWAY_URL=http://127.0.0.1:9446 FABRIC_CHANNEL=mychannel FABRIC_CHAINCODE=honeychain
```

Result: **3 passed**.

```
tests/test_fabric_adapter.py::TestLiveFabricRuntime::test_live_health_check        PASSED
tests/test_fabric_adapter.py::TestLiveFabricRuntime::test_live_verify_anchor_probe PASSED
tests/test_fabric_adapter.py::TestLiveFabricRuntime::test_live_submit_and_verify   PASSED
```

- `test_live_health_check` — real `getAnchor` probe through the gateway; asserts
  `status == "connected"`, `channel == "mychannel"`, `chaincode_version == "2.0"`.
- `test_live_verify_anchor_probe` — real `getAnchor("HC-DEMO-001")`, returns a bool.
- `test_live_submit_and_verify` — `createBatch` + `anchorMerkleRoot` committed to the
  live ledger, then `getAnchor` read-back confirms the anchor exists.

## Live transactions recorded during the session (evidence)

| # | Chaincode function | Caller | Transaction ID | Outcome |
|---|---|---|---|---|
| 1 | `anchorMerkleRoot` (HC-DEMO-001) | direct gateway | `dbcbd8feeff5761c98736c114d9a0f699b2d616398f6c8a1d9075728b52ad2cf` | committed (2232 ms) |
| 2 | `submitEvent` (PROVENANCE_ANCHORED) | direct gateway | `93698012206aa1664c90d7a71258390a4f10d8bc4f80ebe8ebcf02e8c2665e29` | committed (2101 ms) |
| 3 | `createBatch` (HC-LIVE-1789054361) | Python adapter | (createBatch tx) | accepted |
| 4 | `anchorMerkleRoot` (HC-LIVE-1789054361) | Python adapter | `52c7801a3e1d05a89e8cb03e76ad38176e359a57fb49745ee0b6b04a62bd0fe4` | CONFIRMED + read-back verified |
| 5 | `submitEvent` (`INTEGRATION_TEST`) | direct gateway | — | **REJECTED** (`10 ABORTED`) — demonstrates real validation |

Also present on the ledger before this session (pre-existing): batches HC-DEMO-001/002/003,
with anchor tx `e92531a1e51b10e47792e3e83bc45fb57c5858c1a7d867ff5a93fbb428a9a499` on
HC-DEMO-001.

## Block-level ledger proof (EC2, 2026-09-10 15:49 UTC)

| Metric | Before write | After write |
|---|---|---|
| Channel height (`peer channel getinfo -c mychannel`) | 41 | 42 |
| Current block hash | `VjfVVyCcKEW4FDFDCnyVuULaX6mBpH66wXXDXh1/xxw=` | `8b2OU2Vh3FBTCZTbTkS5TCbT9KdQLkpTZc0xgJoEafM=` |
| New block's previous hash | — | `VjfVVyCcKEW4FDFDCnyVuULaX6mBpH66wXXDXh1/xxw=` (equals pre-write tip) |

The write (`anchorMerkleRoot` on HC-DEMO-001, **committed**, tx
`d9f71c53cc8036ff306b70ce3aa14508181271ecb0a039f54a8ede9a2079660c`, commit_ms=2067,
submitted_at `2026-09-10T15:49:55.011Z`) grew the channel from height 41 to 42, and the new
block links back to the previous chain tip — proving a genuine extension of the existing ledger.

## Regression risk tracking

Previous suite baseline in this repo was 110 tests; the session's contract-driven
updates bumped the adapter tests to the real chaincode interface (25 UNIT + 3 LIVE).
No `SIMULATED`/`MOCK` labels were introduced anywhere; the truth labels are audited in
[FINAL_TRUTH_REPORT.md](./FINAL_TRUTH_REPORT.md).

## Flutter suite (2026-09-11)

Command: `flutter analyze` then `flutter test` (Flutter 3.47.1 / Dart 3.13.1)

Result: **analyze clean (no issues) · `flutter test` → 112 passed** (up from 94).

Coverage includes the existing portal/widget flows plus:
- `test/api_config_test.dart` — build-time URL policy gate (https only for
  production; localhost / 127.0.0.1 / Android emulator host `10.0.2.2` for dev).
- `test/backend_mode_integration_test.dart` — backend-mode guards (no faked
  success when the backend is absent), server row → beekeeper UI mapping, and
  restart durability of the offline pending queue (record survives on disk with
  `pending` status).
- `test/honey_api_service_test.dart` — beekeeper API contract
  (auth / hives / harvests / batches / evidence / Fabric status) with MockClient.
- `test/auth_session_test.dart` — canonical auth state machine
  (signed-out / offline-authenticated), durable JWT + workspace restore across
  restarts, workspace switching without re-login, logout keeping local data,
  and role-scoped workspace eligibility.
- `test/passport_verification_service_test.dart` — online passport
  verification client (verified anchor / not found / rate-limited / unreachable
  / deterministic canonical proof JSON) with MockClient.
- Existing: offline queue + retry + no-duplicate sync, QR/trace/trust tiers,
  responsive smoke tests.

## Android builds (2026-09-11)

- `flutter build apk --debug` → `releases/honeychain-2.0.2+4-debug.apk` ✅ built.
- `flutter build apk --release` → `releases/honeychain-2.0.2+4-release.apk`
  (74.7 MB) ✅ builds, but uses the template's **debug signing config** → not
  Play-Store-ready (real keystore must be provisioned).
- The `cmdline-tools`/licenses warning from `flutter doctor` did NOT block the
  Gradle build (toolchain already present).
- Real Android device/emulator E2E: **NOT TESTED** (none available in this
  environment — `flutter devices` lists only Windows/Chrome/Edge).