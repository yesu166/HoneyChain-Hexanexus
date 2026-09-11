# Provenance Model — how trust tier + hashes + anchors combine

**Scope:** the data model behind "where does this honey come from and how much can we prove
it". Companion: `QR_HONEY_PASSPORT.md` (passport/QR), `MOBILE_LIVE_FLOW.md` (live wiring).

## 1. Records → evidence → trust

Every step of the journey is a **record** with an explicit `evidence_type` / `evidence`
(value/author/at). The app keeps strong provenance for:

- harvests (beekeeper-reported),
- custody transfers (who held the lot when),
- lab tests (result, tested_by, tested_at),
- product consolidation + jar packaging,
- the final blockchain anchor.

`lib/services/trust_service.dart` merges these into a single `TrustState`:

| Tier | Meaning | Reached when |
|---|---|---|
| self_declared | beekeeper-reported only | default |
| organization_verified | FPO collected / vetted | org custody + collection records |
| lab_verified | lab test PASS | lab result `status == passed` |
| blockchain_anchored | on-chain anchor exists | anchor `chain_status == anchored` |

Tier merging is **weakest-tier-wins** (documented + tested). Missing independent proof is
reported openly ("no independent proof yet").

## 2. Hashing & integrity (backend)

`backend/app/services/merkle.py` builds merkle trees; `backend/app/core/crypto.py` owns
canonical serialization, SHA-256 and ECDSA signing (covered by `test_crypto.py` /
`test_merkle.py` / `test_evidence.py` with tamper detection).

The app-side **canonical serialization mirror** lives in
`lib/services/passport_verification_service.dart` (`canonicalProofJson`) so the same server
payload always serializes deterministically — proving the app and server agree on a subject
(the fixed-field-order test enforces this).

## 3. Anchoring — local vs. live

| Path | Where | Status label |
|---|---|---|
| **Prototype anchor** | `blockchain.mock.notice` | `PROTOTYPE / MOCK BLOCKCHAIN` (clearly shown in UI) |
| **Live Fabric anchor** (beekeeper path) | `honey_api_service` → `/api/v1/evidence/bundles` (`anchor: true`) → EC2 Fabric gateway port 9446 | real `committed` tx; read-back verified |
| **Public passport anchor** | backend `PassportResponse.anchor` | `chain_status`: `anchored` / `pending` / `none` |

The UI distinguishes these **three** states and never conflates a prototype placeholder with a
real committed tx.

## 4. Provenance guarantees (honest)

- **Tamper-evidence, not purity.** The anchor proves the hash existed at a time on the ledger;
  it does not certify honey quality, nutrition or health (see the fixed caveat text).
- **Fabric stays the real ledger.** No reset/redeploy of the EC2 chain; anchors extend
  `mychannel` (height 41 → 42 proven previously). The Node gateway remains firewalled
  (SSH tunnel only).
- **If nothing is anchored, the app says so** — `PassportAnchorStatus.none` renders
  "No blockchain anchor is on record for this batch yet."

## 5. What is NOT claimed

- ❌ EVM/other-chain anchoring (boundary only → `BLOCKCHAIN_NOT_CONFIGURED`).
- ❌ Supabase live writes (no `SUPABASE_SERVICE_ROLE_KEY`).
- ❌ QR payload signatures (plain schemes, see `QR_HONEY_PASSPORT.md`).