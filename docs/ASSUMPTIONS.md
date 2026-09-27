# Assumptions & Decisions Record

## Assumptions (stated, never silently acted upon)

1. **Supabase is the system of record.** The `.env` DB URL points at project
   `hhxwhopaazqjdlreqhkf`. Backend writes to Supabase require the
   `SUPABASE_SERVICE_ROLE_KEY`, which the user did NOT provide; therefore the
   backend runs on `DemoSeededRepository` locally. Migrations ARE applied.
2. **Hyperledger Fabric is the selected live provenance network for the current prototype path.** A real Fabric network exists on EC2 on `mychannel` with `honeychain` v2.0, and backend-side live submission/read-back has been verified. The gateway is currently protected from public exposure and is reached through the documented EC2 path/tunnel.
3. **The local ledger remains a development fallback.** `LocalLedgerAdapter` is explicitly labelled `local` and must never be presented as a distributed blockchain.
4. **The ML artifacts are demo artifacts.** `ml/model.pkl` and its metrics are
   not claims of trained-model accuracy. The risk engine is rule-based.
5. **Photos and labs never reach a ledger.** Only canonical hashes do.
   This is a design decision, not a limitation.
6. **Camera/QR need a real device.** This environment has none; features are
   covered by widget/integration tests only.
7. **Docker daemon is down.** No container image builds or `supabase` CLI
   workflows this session (CLI not installed either).

## Decisions (with rationale)

| # | Decision | Rationale |
|---|---|---|
| D1 | Gateway is the single blockchain boundary | app never talks to an SDK; adapter swapped by config |
| D2 | `simulated` → `local` dev ledger (renamed) | honesty: never present an in-process ledger as a real chain |
| D3 | Evidence bundles anchored by Merkle root only | per-hash anchor cost/space; proof path enables per-item verification |
| D4 | Offline ledger preserves forks, never collapses losers | a "losing" record is still evidence; reconciliation must be explicit |
| D5 | Lab certificates carry `content_hash` + revocation event | a revoked cert can never verify; tamper-evidence on the hash |
| D6 | Tamper endpoints gated by `DEMO_MODE` / production 403 | demo capability must be impossible in production |
| D7 | RBAC matrix is server-side only | hiding buttons is not security |
| D8 | Certificate/evidence tables reference batches by `text` (no FK) | offline-first ordering: evidence may precede the batch row |
| D9 | Blockchain state machine distinct from DB state | DB+ledger stay consistent; status reflects what the ledger actually says |
| D10 | Trust tiers: merged lots take the weakest contributing tier | prevents laundering low-trust honey into a high-trust lot |

## Non-decisions (open)

- Which real ledger to fund pay-for — EVM vs Fabric is left as a deployment
  choice; both boundaries exist.
- Whether photos are uploaded to object storage and only hashed locally — TBD
  with the customer; code currently stores `content_hash` + value.