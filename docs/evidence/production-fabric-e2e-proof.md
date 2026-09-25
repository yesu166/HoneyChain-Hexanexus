# Production Fabric E2E Proof (EC2 backend to live mychannel)

**Status:** VERIFIED - the production HC-3.0 backend on EC2 committed real
transactions to the live Hyperledger Fabric network, and the result was read
back independently from the ledger and from a decoded orderer block.

**Date:** 2026-09-25
**Instance:** i-06063debd27c12e51 / ap-south-1 / 13.127.118.165 (host ip-172-31-8-236)
**Host user:** `ubuntu` (SSH key `honeychain-key.pem`)
**Proof artifact:** `docs/evidence/live-e2e-proof-2026-09-25.json` (captured by the run below)
**Script used:** `backend/scripts/live_fabric_e2e_proof.py` (copied to `/tmp/e2e_fabric_proof.py` on the EC2 host and executed there with the deployed venv)

---

## 1. Deployed state

| Item | Value |
|------|-------|
| HC-3.0 code deployed | commit **6083028** (`fix: round-robin one Gemini key per request`) |
| Deployment method | `git archive 6083028` snapshot, tarball sha256 verified on both ends (`7196af13...`) |
| Per-file proof | `git hash-object <deployed>` vs `git ls-tree 6083028` for every file in `backend/` + `fabric-gateway-service/`: **checked=144 mismatches=0 missing=0** |
| Gateway fix deployed on top | commit **46a8d71**, deployed blob `6451b33da99299f8573f1b4f97917ca2e9f3f142` (identical to the commit blob) |
| FastAPI | systemd `honeychain-api.service`, uvicorn on `0.0.0.0:8000`, active |
| Fabric gateway | systemd `honeychain-fabric-gateway.service`, Node on `:9446`, active, now **enabled** at boot |
| Fabric network | orderer + peer0.org1 + peer0.org2 + 2 CAs, `fabric_test`, up since 2026-09-08 |
| Backend `.env` | `BLOCKCHAIN_ADAPTER=fabric`, `FABRIC_CHANNEL=mychannel`, `FABRIC_CHAINCODE=honeychain`, `FABRIC_GATEWAY_URL=http://localhost:9446`, perms `600` |

Nothing in Fabric was rebuilt, re-created, or faked; the existing channel,
peer, orderer and chaincode were used as-is.

---

## 2. Independent Fabric verification (no application code involved)

Run directly on the host with the `peer` CLI and the Org1 Admin MSP:

```
$ peer channel list
Channels peers has joined:
mychannel

$ peer channel getinfo -c mychannel
Blockchain info: {"height":63,
  "currentBlockHash":"YzeuOzs+aAtvVK1MnckwHHeN8+Gc4vNU9lWIDLTntLg=",
  "previousBlockHash":"H3XItC/7SlhJpOn9vLAdCfyGrFuMmHD78Owl3j0F54Y="}

$ peer lifecycle chaincode querycommitted --channelID mychannel --output json
{ "chaincode_definitions": [
    { "name": "honeychain", "sequence": 6, "version": "2.0",
      "endorsement_plugin": "escc", "validation_plugin": "vscc" },
    { "name": "basic", "sequence": 1, "version": "1.0", ... } ] }
```

The gateway health endpoint (`GET /health` on `127.0.0.1:9446`) additionally
performs a real `getAnchor('health-check-probe')` query against the chaincode:

```json
{"status":"connected","adapter":"fabric","channel":"mychannel",
 "chaincode":"honeychain","chaincode_version":"2.0","chaincode_sequence":6,
 "peer":"localhost:7051","msp_id":"Org1MSP","error":null}
```

---

## 3. The real end-to-end transaction

Executed through the **production HTTP API on EC2** (not a test harness):

1. Platform org + invited admin created (`POST /api/v1/platform/organizations`,
   `POST .../admins`, `POST /api/v1/auth/register`, `POST /api/v1/auth/login`).
2. Real batch created in the production database:
   `POST /api/v1/batches` -> `201` `id=16da050c-a5f1-4a88-873e-3fe6c5cb7b78`,
   `batch_code=E2E-FABRIC-1790296445`.
3. Real evidence bundle + anchor through the production service path:
   `POST /api/v1/evidence/bundles` with `anchor: true`.
   The adapter probed `getBatch` (chaincode replied `NOT_FOUND`), created the
   batch on the ledger (`createBatch`) and committed the Merkle root
   (`anchorMerkleRoot`).

Captured result:

| Field | Value |
|-------|-------|
| Bundle id | `72becb289bcf` |
| Merkle root | `787d93ec5c10a97ba5e080c92c72205b4ff14532d7ab93fe258a597256abac24` |
| Tx ref (internal) | `32fc42593d9d8315cd0d4fc8089e4f12e0156677` |
| **Transaction ID** | **`b7534f6b7a47dc1ce501924b05bcb515807f867b8d3b2d8089580103b7ce03b5`** |
| State | `CONFIRMED` (commit-status gate, not merely "submitted") |
| Network | `fabric:mychannel` |
| Channel / chaincode | `mychannel` / `honeychain` v2.0, sequence 6 |
| Timestamp (UTC) | 2026-09-25T00:34:10Z (created) / 00:34:14Z (confirmed) |

Independent read-backs:

* Application tracker: `GET /api/v1/blockchain/status` ->
  `txs=2 matching_tx=1 state=CONFIRMED tx_hash=b7534f6b...`
* Gateway evaluate (a different code path from the write):
  * `getAnchor(batchId)` -> `{"anchored":true,"anchorId":"HC-16da050c-...-32fc4259","merkleRoot":"787d93ec..."}`
  * `verifyMerkleRoot(batchId, root)` -> `{"verified":true}`
  * `getBatch(batchId)` -> on-ledger batch record (`batchType: honey_batch`,
    `actorId: ORG-000019`)

### Block-level proof

`peer channel getinfo` before/after: **height 63 -> 65** (two real blocks:
`createBatch` and `anchorMerkleRoot`). Both new blocks were fetched from the
orderer and decoded with `configtxlator`:

| Block | previous_hash | txid_in_block | extends_pre_tip |
|-------|---------------|---------------|-----------------|
| 63 | `YzeuOzs+aAtvVK1MnckwHHeN8+Gc4vNU9lWIDLTntLg=` | false | **true** (equals the pre-run chain tip) |
| 64 | `xGvXXUVkC4b+eRf9l1LexkbsO5o6sudq9RFf4nBgTFA=` | **true** | false |

Block 63 extends the pre-existing ledger tip and block 64 contains our
transaction id, so the write is a genuine extension of the existing channel
ledger, not a rebuilt or simulated one.

The repository's own live suite also passes on the host:

```
$ cd /home/ubuntu/honeychain/backend && FABRIC_GATEWAY_URL=http://127.0.0.1:9446 \
    .venv/bin/python -m pytest tests/test_fabric_adapter.py -k TestLiveFabricRuntime -v
3 passed, 25 deselected
```

---

## 4. Defects found by this live verification

### 4.1 Gateway `/submit` silently dropped every chaincode argument (FIXED in 46a8d71)

Commit a08db31 rewrote `/submit` as
`contract.newProposal(fn, ...stringArgs)` -> `proposal.endorse()` ->
`contract.submit(...)` -> `contract.commitStatus(...)`.
In `@hyperledger/fabric-gateway` 1.12.1 the second parameter of `newProposal`
is `ProposalOptions`, not a chaincode argument, and `Contract.submit(endorsed)`
/ `Contract.commitStatus()` are not SDK methods. Every write was therefore
endorsed with zero arguments and the peer log showed:

```
WARN [gateway] Endorse call to endorser failed ... error="chaincode response 500,
Expected 1 parameters, but 0 have been supplied"
10 ABORTED: failed to endorse transaction
```

Fix (commit 46a8d71) uses the documented fine-grained flow:

```js
const proposal = contract.newProposal(fn, { arguments: stringArgs });
const txId = proposal.getTransactionId();
const transaction = await proposal.endorse();
const submittedTx = await transaction.submit();
const commitStatus = await submittedTx.getStatus();   // successful === true && code === 0
const raw = Buffer.from(transaction.getResult()).toString('utf-8');
```

Reads (`/evaluate`) were always correct because they use
`contract.evaluateTransaction(fn, ...stringArgs)`.

### 4.2 Platform invites store the organization KEY where a UUID is expected (OPEN)

`POST /api/v1/platform/organizations/{key}/admins` + `POST /api/v1/auth/register`
leave the new admin with `users.org_id = "ORG-0000NN"` (the human-readable
`organization_key`), while `batches.organization_id` is a uuid FK and every
production user carries the organization UUID. Result:

```
postgrest.exceptions.APIError: invalid input syntax for type uuid: "ORG-000016" (22P02)
```

The proof run realigns the freshly created test admin to the org UUID (the
production convention) before creating the batch. Recommended fix: resolve the
invite to `organizations.id` at register time.

### 4.3 `organizations.client_id` unique constraint blocks a second platform org (OPEN)

`uq_organizations_client_id` is unique, yet platform-created organizations
default to `client_id=""`:

```
duplicate key value violates unique constraint "uq_organizations_client_id" (23505)
Key (client_id)=() already exists.
```

Only the first platform-created org can be inserted at all. The proof run passes
a unique `client_id`. Recommended fix: partial unique index
(`WHERE client_id <> ''`) or default the column to a generated value.

---

## 5. Remaining gaps (not part of this proof)

1. **Lifecycle events not wired (STEP 8):** `submit_batch_state_transition`,
   `submit_custody_transfer`, `submit_lineage_event` exist in the gateway but
   have no call sites; `transitionBatch` / `recordLineage` are therefore not yet
   exercised by services.
2. **`block_number` is empty** in transaction snapshots: the Fabric Gateway SDK
   exposes commit status, not the containing block; the on-ledger anchor record
   does store its own `blockchainTxId`.
3. **Gateway binds `*:9446`**; the EC2 security group blocks it externally, but
   binding to `127.0.0.1` would be defence in depth (the unit file is already
   enabled at boot).
4. **No HTTPS reverse proxy** in front of FastAPI (`0.0.0.0:8000`); needed before
   the portal/public API is exposed.
5. **`API_ENV=development`** on EC2; switching to `production` requires the real
   `JWT_SECRET` to be present (it is) and should be validated by a restart.
6. `GET /health` on the gateway still reports static `chaincode_version` /
   `chaincode_sequence` values; the authoritative values come from
   `peer lifecycle chaincode querycommitted` (verified above).

---

## 6. Reproduce

```bash
# 0. access
ssh -i honeychain-key.pem ubuntu@13.127.118.165

# 1. system state
systemctl is-active honeychain-api honeychain-fabric-gateway
curl -s http://127.0.0.1:9446/health
curl -s http://127.0.0.1:8000/api/v1/blockchain/health

# 2. ledger state (independent of the app)
export PATH=/home/ubuntu/honeychain/fabric-samples/bin:$PATH
export FABRIC_CFG_PATH=/home/ubuntu/honeychain/fabric-samples/config
export CORE_PEER_TLS_ENABLED=true CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_TLS_ROOTCERT_FILE=/home/ubuntu/honeychain/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_MSPCONFIGPATH=/home/ubuntu/honeychain/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
peer channel getinfo -c mychannel
peer lifecycle chaincode querycommitted --channelID mychannel --output json

# 3. the end-to-end proof
/home/ubuntu/honeychain/backend/.venv/bin/python /tmp/e2e_fabric_proof.py   # writes /tmp/e2e_proof.json
cd /home/ubuntu/honeychain/backend && FABRIC_GATEWAY_URL=http://127.0.0.1:9446 \
  .venv/bin/python -m pytest tests/test_fabric_adapter.py -k TestLiveFabricRuntime -v
```