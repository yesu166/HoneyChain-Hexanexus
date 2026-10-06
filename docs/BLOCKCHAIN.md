# Blockchain strategy (honest)

HoneyChain anchors cryptographic commitments, not marketing claims.
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

**LIVE NETWORK (verified baseline):**
- EC2: i-06063debd27c12e51 (ap-south-1, 13.127.118.165)
- Fabric v2.5.16, channel: mychannel, chaincode: honeychain v2.0 sequence 6
- Org1 + Org2 approved, endorsement: escc, validation: vscc

**Integration (deployed and PROVEN live, 2026-09-10):**
1. The `FabricBlockchainAdapter` (`backend/app/adapters/blockchain/gateway.py`)
   makes HTTP calls to a Node.js Fabric Gateway service.
2. The Node.js service (`fabric-gateway-service/`) uses the official
   `@hyperledger/fabric-gateway` SDK (gRPC + TLS, Org1 Admin MSP) and runs on
   EC2 as a systemd service (`honeychain-fabric-gateway`) on port **9446**.
3. Real committed transactions were written via this full chain and read back
   (evidence: `docs/evidence/live-fabric-backend-proof.md`), including one
   committed through the Python adapter with tx id
   `52c7801a3e1d05a89e8cb03e76ad38176e359a57fb49745ee0b6b04a62bd0fe4`.
4. Configuration via environment variables:
   - `BLOCKCHAIN_ADAPTER=fabric`
   - `FABRIC_CHANNEL=mychannel`
   - `FABRIC_CHAINCODE=honeychain`
   - `FABRIC_GATEWAY_URL=http://localhost:9446` (Node.js service)

**Chaincode contract (REAL, verified from the chaincode container):**
- Reads: `getEvent`, `getEventsByType`, `getBatch`, `getAllBatches`, `getAnchor`,
  `verifyMerkleRoot`, `getLineage`, `getCertificate`, `getCertificatesForBatch`,
  `getHistory`, `scanRange`
- Writes: `submitEvent`, `createBatch`, `transitionBatch`, `recordLineage`,
  `anchorMerkleRoot`, `registerCertificate`, `revokeCertificate`

The Python adapter maps `submit_anchor`→`anchorMerkleRoot`, `verify_anchor`→`getAnchor`,
`submit_event`→`submitEvent`. (This supersedes the older `tracer.js` interface in
`fabric/chaincode/tracer/`, which is NOT what is deployed.)

**Network reachability caveat:** EC2 security group does not open port 9446 inbound;
access is currently via an SSH tunnel. Opening the port (or running FastAPI on EC2) is
required for 24/7 production.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full integration path.
See [docs/evidence/live-fabric-backend-proof.md](./evidence/live-fabric-backend-proof.md)
for verified baseline and live evidence.

## Truth rules that are enforced by code

1. A `CONFIRMED` state requires confirmation from a reachable ledger.
2. `FABRIC_NOT_CONFIGURED` / `FABRIC_UNAVAILABLE` are returned, never the
   words "success" or "confirmed", when Fabric cannot be reached.
3. No block number, transaction hash or peer identity is invented.
4. The `local` ledger is named `local` in every API response (`ledger_name`),
   so no consumer can mistake it for real anchor.
5. Tamper endpoints return an honest `verify` result — a tampered bundle
   fails `evidence_intact: false`.