# Blockchain strategy (honest)

HoneyChain 3.0 anchors cryptographic commitments, not marketing claims.
This document explains exactly what the blockchain layer does and what it does
NOT do, and how to move from the local dev ledger to a real network without
changing the application layer.

## What gets anchored

Only **hash commitments** and **explicit business events**:

- `submit_anchor(batch_id, evidence_root, ...)` — the Merkle root of a
  Harvest Evidence Bundle.
- `submit_event(...)` — explicit events: batch state transitions, custody
  transfers, certificate anchors, lineage events.

Sensitive payloads, PII, photos and lab sheets are **never** written to a
blockchain. Only their canonical SHA-256 hashes are.

## The three adapters

The application talks to exactly one boundary: `BlockchainGateway`
(`backend/app/adapters/blockchain/gateway.py`). The gateway dispatches to one
adapter selected by configuration:

| Adapter | When it is used | Honest behaviour |
|---|---|---|
| `LocalLedgerAdapter` | default; any env without EVM/Fabric credentials | in-process dict ledger; labeled `local`; usable for demos/tests |
| `EVMBlockchainAdapter` | `BLOCKCHAIN_ADAPTER=evm` + RPC/wallet/contract env set | live submission once wired; until then raises `BLOCKCHAIN_NOT_CONFIGURED` |
| `FabricBlockchainAdapter` | `BLOCKCHAIN_ADAPTER=fabric` + channel/chaincode set | real submission once a Fabric network + connection profile exists; otherwise `FABRIC_NOT_CONFIGURED` / `FABRIC_UNAVAILABLE` |

There is **no** simulated Fabric or simulated EVM. If you choose Fabric/EVM and
the network is not there, the API reports the honest status code — it does not
invent blocks, peers, MSP identities, transactions or "confirmed" receipts.

## Transaction state machine

Gateway transactions (`backend/app/adapters/blockchain/state.py`):

```
PENDING → SUBMITTED → CONFIRMED
            |            |
            v            v
        RETRYING    FAILED / UNKNOWN
```

- `RETRY` is allowed while `attempts < max_attempts` and never for `CONFIRMED`.
- Idempotency: every submission carries a `tx_ref` derived from the payload
  hash, so anchoring the same evidence twice does not double-write.

## What the local ledger verifies

`verify_anchor(ref)` returns `True` only for a `CONFIRMED` local entry matching
`ref` as either its `tx_hash` or its `data_hash`. The evidence service then
does the real tamper detection by recomputing the Merkle root from the stored
payloads and comparing to the anchored root.

## How to connect a real network (and what we would not fake)

### EVM (e.g. Polygon Amoy)

1. Export `.env`:
   - `BLOCKCHAIN_ADAPTER=evm`
   - `BLOCKCHAIN_RPC_URL=https://rpc-amoy.polygon.technology`
   - `BLOCKCHAIN_CHAIN_ID=80002`
   - `BLOCKCHAIN_CONTRACT=0x…` (deployed `HoneyChainAnchor` contract)
   - `BLOCKCHAIN_PRIVATE_KEY=…` (never commit; shim exists in `Settings`)
2. Implement `EVMBlockchainAdapter.submit_anchor` with a web3 provider +
   a signer. The `_require()` guard and `LedgerUnavailable` boundary already
   give the honest failure behaviour; the provider call replaces the boundary.

### Hyperledger Fabric

1. Stand up the network (see instructions in the wrap-up question at the end
   of this session: "Should I deploy/start the Fabric network now?").
2. Provide a connection profile (e.g. `fabric/connection-profile.json`), MSP
   identity, channel = `honeychain`, chaincode = `tracer`.
3. Implement `FabricBlockchainAdapter.submit_anchor` against the Fabric
   Gateway SDK. Until then the adapter raises `FABRIC_NOT_CONFIGURED`.

## Truth rules that are enforced by code

1. A `CONFIRMED` state requires confirmation from a reachable ledger.
2. `FABRIC_NOT_CONFIGURED` / `FABRIC_UNAVAILABLE` are returned, never the
   words "success" or "confirmed", when Fabric cannot be reached.
3. No block number, transaction hash or peer identity is invented.
4. The `local` ledger is named `local` in every API response (`ledger_name`),
   so no consumer can mistake it for real anchor.
5. Tamper endpoints return an honest `verify` result — a tampered bundle
   fails `evidence_intact: false`.