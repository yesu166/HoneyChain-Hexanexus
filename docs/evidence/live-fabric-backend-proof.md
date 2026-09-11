# Live Fabric Backend Integration Proof

**Status:** VERIFIED — full chain (FastAPI → FabricBlockchainAdapter → Node.js gateway → live EC2 Fabric → mychannel → honeychain) proven with real committed transactions.

**Date:** 2026-09-10

## Verified Fabric Baseline (EC2)

| Property | Value |
|----------|-------|
| EC2 Instance | i-06063debd27c12e51 |
| Region | ap-south-1 |
| Public IP | 13.127.118.165 |
| Fabric Version | v2.5.16 |
| Channel | mychannel |
| Chaincode | honeychain |
| Chaincode Version | 2.0 |
| Chaincode Sequence | 6 |
| Org1 Approval | true |
| Org2 Approval | true |
| Endorsement Plugin | escc |
| Validation Plugin | vscc |
| Org1 Peer | peer0.org1.example.com:7051 |
| Org2 Peer | peer0.org2.example.com:9051 |
| Orderer | orderer.example.com:7050 |
| Network | fabric_test (all peer/orderer/chaincode containers running) |

## IMPORTANT CORRECTION: Real Chaincode Contract

The deployed chaincode is **NOT** the local `fabric/chaincode/tracer/lib/tracer.js`. It is a
distinct `honeychain` contract. The real deployed source was read directly from the running
chaincode container:
`dev-peer0.org1.example.com-honeychain_2.0-87b1af...` at `/usr/local/src/lib/honeychain.js`.

Actual exposed functions (verified against `honeychain.js` + `events.js` + `state-machine.js`, and
by live calls):

| Function | Kind | Notes |
|----------|------|-------|
| `getEvent` | read | returns stored event or null |
| `getEventsByType` | read | filtered list |
| `getBatch` | read | batch state + `Anchored`/`LastTxID` fields |
| `getAllBatches` | read | list |
| `getAnchor` | read | `{ anchored: true/false, ... }` |
| `verifyMerkleRoot` | read | merkle commitment check |
| `getLineage` | read | batch lineage graph |
| `getCertificate` | read | certificate |
| `getCertificatesForBatch` | read | list |
| `getHistory` | read | world-state history |
| `scanRange` | read | key range scan |
| `submitEvent` | write | requires `eventType` in fixed EVENT_TYPES list + 64-hex `payloadHash` |
| `createBatch` | write | creates `BATCH:<batchId>` |
| `transitionBatch` | write | state transitions |
| `recordLineage` | write | parent/child links |
| `anchorMerkleRoot` | write | requires batch to EXIST; commits merkle root |
| `registerCertificate` | write | certificates |
| `revokeCertificate` | write | revocations |

Gateways use HTTP `POST /evaluate` for reads and `POST /submit` for writes, passing
`{ "function": "<name>", "args": ["<single JSON string>"] }`. Evaluation response wraps the
chaincode return value under `result`.

## Real Evidence Log (all observed, nothing fabricated)

### 1. Gateway service deployed and running on EC2 (24/7)

- Location: `~/honeychain/fabric-gateway-service/` (`src/index.js`, `src/chaincode.js`, `src/fabricGateway.js`, `config.js`)
- Runtime: Node.js **v22.23.2** (`@hyperledger/fabric-gateway` v1.12.1 requires Node ≥ 18 ESM; EC2 was upgraded from v18)
- Port: **9446** (9443/9444/9445 already occupied by orderer/peer admin ports)
- systemd unit `honeychain-fabric-gateway.service` — **active** (Restart=always)
- Identity: Org1 Admin MSP (signcerts + keystore), TLS CA from peer TLS
- Network access: only via SSH tunnel (`localhost:9446` Windows → `localhost:9446` EC2) because EC2 security group does **not** open 9446 (no AWS CLI available to modify it).

Direct gateway health over the tunnel:

```json
{"status":"connected","channel":"mychannel","chaincode":"honeychain",
 "chaincode_version":"2.0","chaincode_sequence":6,"peer":"localhost:7051",
 "msp_id":"Org1MSP"}
```

(Queries real chaincode via `getAnchor("health-check-probe")`.)

### 2. Direct real writes committed to the ledger

**Write A — `anchorMerkleRoot`** on existing batch HC-DEMO-001:

```json
{"status":"committed","txId":"dbcbd8feeff5761c98736c114d9a0f699b2d616398f6c8a1d9075728b52ad2cf",
 "anchorId":"HC-FABRIC-INT-1789053590","commitMs":2232}
```

**Write B — `submitEvent`** (eventType `PROVENANCE_ANCHORED`, valid 64-hex payloadHash):

```json
{"status":"committed","txId":"93698012206aa1664c90d7a71258390a4f10d8bc4f80ebe8ebcf02e8c2665e29",
 "eventId":"HC-FABRIC-INTEGRATION-1789053631","commitMs":2101}
```

Both were read back with `getEvent`/`getAnchor` to confirm the exact record persisted.

Note: an invalid event type (`INTEGRATION_TEST`) was **rejected** by chaincode (`10 ABORTED`) —
proof the ledger applies real validation, nothing is rubber-stamped.

### 3. Pre-existing demo data discovered on the live ledger

- 3 demo batches exist: `HC-DEMO-001`, `HC-DEMO-002`, `HC-DEMO-003`.
- `HC-DEMO-001` already carried an anchor from a prior session (tx
  `e92531a1e51b10e47792e3e83bc45fb57c5858c1a7d867ff5a93fbb428a9a499`).

### 4. FULL CHAIN through the Python FastAPI adapter — proven

FastAPI `FabricBlockchainAdapter` → HTTP tunnel → Node.js gateway → gRPC → real peer →
`mychannel`/`honeychain`:

```
[1/5] health_check()  -> {"status":"connected","network":"mychannel","chaincode_version":"2.0",
                          "chaincode_sequence":6,"peer":"localhost:7051","msp_id":"Org1MSP",
                          "last_verified_at":"2026-09-10T15:32:39.893Z"}
[2/5] verify_anchor("HC-DEMO-001") -> True          (getAnchor read of existing anchor)
[3/5] createBatch("HC-LIVE-1789054361")             (chaincode accepted)
[4/5] submit_anchor(...) -> state=CONFIRMED
      tx_hash = 52c7801a3e1d05a89e8cb03e76ad38176e359a57fb49745ee0b6b04a62bd0fe4
      fabric_result.anchorId  = HC-HC-LIVE-1789054361-live-tes
      fabric_result.batchId   = HC-LIVE-1789054361
      fabric_result.merkleRoot= f50ff9e5c5a6c57321799ba95e1f9a9c6cc2c0e2a0f8f3e5b9a1c2d3e4f5a6b7
[5/5] verify_anchor("HC-LIVE-1789054361") -> True   (real read-back after commit)
```

Real committed transaction ID: **`52c7801a3e1d05a89e8cb03e76ad38176e359a57fb49745ee0b6b04a62bd0fe4`**
(the block this landed in is verifiable on EC2 via `peer channel getinfo`).

### 5. BLOCK-LEVEL PROOF — chain height advanced by a real commit

Run on EC2 (`peer channel getinfo -c mychannel`, before/after a gateway write):

```
BEFORE: height 41
  currentBlockHash  = VjfVVyCcKEW4FDFDCnyVuULaX6mBpH66wXXDXh1/xxw=
WRITE:  anchorMerkleRoot on HC-DEMO-001 -> {"status":"committed",...,"commit_ms":2067,
          "blockchainTxId":"d9f71c53cc8036ff306b70ce3aa14508181271ecb0a039f54a8ede9a2079660c"}
        submitted_at 2026-09-10T15:49:55.011Z
AFTER:  height 42
  currentBlockHash  = 8b2OU2Vh3FBTCZTbTkS5TCbT9KdQLkpTZc0xgJoEafM=
  previousBlockHash = VjfVVyCcKEW4FDFDCnyVuULaX6mBpH66wXXDXh1/xxw=   <-- equals BEFORE hash
```

The new block's `previousBlockHash` equals the pre-write chain tip, so the write is a genuine
extension of the existing channel ledger — not a rebuilt or simulated one.

### 5. LIVE_RUNTIME tests — all 3 pass against real Fabric (via persistent tunnel)

```
tests/test_fabric_adapter.py::TestLiveFabricRuntime::test_live_health_check        PASSED
tests/test_fabric_adapter.py::TestLiveFabricRuntime::test_live_verify_anchor_probe PASSED
tests/test_fabric_adapter.py::TestLiveFabricRuntime::test_live_submit_and_verify   PASSED
```

These open a fresh batch per run, anchor it, and verify it read-back on the live ledger.

### 6. Python adapter contract update

`backend/app/adapters/blockchain/gateway.py` now maps to the REAL contract:

```python
CHAINCODE_FUNCTIONS = {
    "GET_EVENT": "getEvent", "GET_BATCH": "getBatch", "GET_ANCHOR": "getAnchor",
    "VERIFY_MERKLE_ROOT": "verifyMerkleRoot", "GET_LINEAGE": "getLineage",
    "GET_CERTIFICATE": "getCertificate", "GET_HISTORY": "getHistory",
    "SUBMIT_EVENT": "submitEvent", "CREATE_BATCH": "createBatch",
    "ANCHOR_MERKLE_ROOT": "anchorMerkleRoot", "RECORD_LINEAGE": "recordLineage",
    "REGISTER_CERTIFICATE": "registerCertificate", "TRANSITION_BATCH": "transitionBatch",
    "REVOKE_CERTIFICATE": "revokeCertificate",
}
```

- `submit_anchor(...)` → `anchorMerkleRoot` with anchor JSON arg
- `verify_anchor(ref)` → `getAnchor` → `{ anchored: bool }`
- `submit_event(...)` → `submitEvent` with event JSON arg

## Integration Architecture (as built)

```
Flutter App
    |
    v
FastAPI Backend (Python)  -- BLOCKCHAIN_ADAPTER=fabric, FABRIC_GATEWAY_URL=http://localhost:9446
    |
    v
BlockchainGateway (gateway.py)
    |
    v
FabricBlockchainAdapter (gateway.py)
    |  HTTP POST /health /submit /evaluate
    v
Node.js Fabric Gateway Service (EC2, systemd, port 9446)
    |  @hyperledger/fabric-gateway SDK (gRPC + TLS, Org1 Admin MSP)
    v
peer0.org1.example.com:7051   (fabric_test network, EC2)
    |
    v
mychannel -> honeychain v2.0 (chaincode seq 6)
```

## Test Status

- **157 backend tests pass** (all `UNIT` — Fabric HTTP mocked), 3 `LIVE_RUNTIME` skipped unless `FABRIC_GATEWAY_URL` set.
- With `FABRIC_GATEWAY_URL=http://127.0.0.1:9446` + persistent tunnel, the 3 `LIVE_RUNTIME` tests **pass**.
- See `docs/TEST_RESULTS.md` for the verified matrix.

## Remaining / Known Limitations (for 24/7 production)

1. **EC2 security group does not open port 9446 inbound.** The gateway is only reachable through
   the SSH tunnel used for this proof. For 24/7 production the group must open 9446 (or FastAPI
   should run on the same EC2 host). No AWS CLI was available during this session to change it.
2. The FastAPI backend was proven against live Fabric via the tunnel from the dev machine; it is not
   itself deployed on EC2.
3. `submit_event` requires a valid `eventType` from the chaincode's fixed list; arbitrary types fail.

## What This Document Does NOT Claim

- It does NOT claim external/internet clients can reach Fabric — port 9446 is not publicly open.
- It does NOT claim any block numbers we did not read back (only transaction IDs and chaincode
  return values were observed directly).
- It does NOT claim the FastAPI server is deployed on EC2.
- All unit tests mock HTTP and are labeled `UNIT`; only `LIVE_RUNTIME` tests touch real Fabric.