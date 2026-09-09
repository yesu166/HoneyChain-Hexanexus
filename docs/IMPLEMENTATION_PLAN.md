# Implementation Plan (current truth)

Ordered roadmap with the **done** items marked. Anything marked "next" has an
honest status — it has a code boundary, not a live external call.

## Phase A/B — audit & foundations ✅
- [x] Repo/tooling audit (Flutter, Node, Python, Docker, Supabase access).
- [x] Permission/access audit + user decisions (see docs/ASSUMPTIONS.md).
- [x] Baseline test inventory: backend 54, Flutter 64.
- [x] `docs/ARCHITECTURE.md`, `docs/CRYPTOGRAPHY.md`.

## Phase C — control-center docs ✅
- [x] SERVICE_STATUS, BLOCKCHAIN, FEATURE_STATUS, ASSUMPTIONS, BLOCKERS,
      ARCHITECTURE_DECISIONS, ROLE_MATRIX, DATA_MODEL, OFFLINE_SYNC, SECURITY,
      DEPLOYMENT, TESTING, API, DEMO, SERVICE_SETUP, KNOWN_LIMITATIONS,
      TECH_STACK_VERSIONS.

## Phase D — proof-of-integrity core ✅
- [x] Canonical serialization, SHA-256, ECDSA P-256 (`core/crypto.py`).
- [x] Merkle tree + proofs (`services/merkle.py`).
- [x] Harvest Evidence Bundle service + routes (`evidence`).
- [x] Offline event ledger (hash-chained, fork-preserving) + routes (`ledger`).
- [x] BlockchainGateway + tx state machine + Local/EVM/Fabric adapters.
- [x] `/api/v1/blockchain/*` status + retry routes.

## Phase E — domain rules ✅
- [x] RBAC permission matrix + `require_permission` dependency.
- [x] Lab certificate issue/verify/revoke + routes.
- [x] Batch state machine + lineage + routes.
- [x] DEMO_MODE-gated tamper endpoints.
- [x] `/health/live` + `/health/ready`.

## Phase F — persistence ✅ (schema) / ⚠️ (live writes)
- [x] Supabase migrations 001–006 **applied to the live project**.
- [x] Repository methods for evidence/ledger/certificate (InMemory + Supabase).
- [x] `.env.example` expanded for blockchain knobs.

## Phase G — verification ✅
- [x] Backend: 110 tests pass.
- [x] Flutter: 64 tests pass.
- [x] Acceptance matrix (`docs/TESTING.md`) + final status report.

## Next (blocked on credentials/infra, would not be faked)
- [ ] Backend writes to hosted Supabase (needs service-role key).
- [ ] EVM contract deploy + `submit_anchor` via provider.
- [ ] Fabric network bring-up + `submit_anchor` via Gateway SDK.
- [ ] Docker images (daemon down).
- [ ] On-device camera/QR E2E.