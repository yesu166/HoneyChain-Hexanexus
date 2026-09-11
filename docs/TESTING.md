# Testing

Two suites, both green this session.

## Backend — pytest (157 passed, 3 LIVE_RUNTIME skipped by default)

Run: `cd backend && ..\.venv_backend\Scripts\python.exe -m pytest -q`

The 3 `LIVE_RUNTIME` tests (`FABRIC_GATEWAY_URL` set) additionally run against the
real EC2 Hyperledger Fabric and pass. See [TEST_RESULTS.md](./TEST_RESULTS.md).

| File | Covers |
|---|---|
| `test_auth.py` | login, JWT, demo identity |
| `test_hives.py` / `test_harvests.py` / `test_batches.py` | CRUD + scoping |
| `test_custody.py` | custody transfers |
| `test_lab.py` | lab request/result flow |
| `test_passport.py` | public passport resolution |
| `test_sync.py` | idempotent offline sync |
| `test_rbac.py` | existing authz + resource scope |
| `test_crypto.py` | canonical serialization, SHA-256, ECDSA |
| `test_merkle.py` | root/proof/tamper |
| `test_event_ledger.py` | hash chain, tamper detection, fork preservation |
| `test_evidence.py` | bundles, verify, proofs, tamper |
| `test_certificates.py` | issue/revoke/verify |
| `test_lineage.py` | state machine transitions + custody holder |
| `test_gateway.py` | local vs EVM/Fabric boundary honesty |
| `test_rbac_matrix.py` | matrix + scope helpers |
| `test_new_routes.py` | API surface for new endpoints |
| `test_fabric_adapter.py` | Fabric adapter (mocked HTTP) + contract mapping + LIVE_RUNTIME |

## Flutter — 64 passed

Run: `flutter test`

Covers beekeeper portal, recording harvests, hive details/alerts, honey
passport drilldown, disease screening (rule-based), IoT simulation warnings,
responsive smoke tests.

## Acceptance matrix (traceability P0/P1)

| Requirement | Automated proof |
|---|---|
| Canonical hash stable | `test_crypto::test_canonical_number_normalization` |
| Evidence bundle builds + anchors | `test_evidence::test_create_bundle_builds_merkle_root_and_anchor` |
| Bundle tamper detected | `test_evidence::test_tampered_evidence_detected` |
| Event ledger chain integrity | `test_event_ledger::test_verify_chain_detects_tamper` |
| Fork preservation (no lost records) | `test_event_ledger::test_fork_preserves_both_records` |
| Tx state machine honesty | `test_gateway::test_fabric_adapter_reports_fabric_not_configured` |
| Certificate revocation | `test_certificates::test_revoke_certificate_flips_verification` |
| Illegal batch transitions blocked | `test_lineage::test_illegal_backwards_transition_rejected` |
| RBAC enforced server-side | `test_rbac_matrix`, `test_new_routes::test_state_transition_rbac` |
| DEMO tamper blocked in prod semantics | `test_new_routes::test_demo_tamper_requires_permission` |

## Not automated (explicit gaps)

- Camera hardware captures (needs device).
- QR scanning on-device (needs device).
- Real EVM network submission (needs a funded RPC wallet + deployed contract).
- Multi-instance rate limiting (needs Redis).

Real **Hyperledger Fabric** submission is no longer a gap: it is automated by the
`LIVE_RUNTIME` tests and has been proven against the live EC2 network
(`docs/evidence/live-fabric-backend-proof.md`).