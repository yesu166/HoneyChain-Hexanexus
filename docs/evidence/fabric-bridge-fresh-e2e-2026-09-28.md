# Fresh Fabric Bridge E2E Evidence — 2026-09-28

All values below were captured live during this session. Nothing is copied from
older evidence files, and nothing is inferred.

## Environment

| Fact | Value |
|---|---|
| Timestamp (UTC) | 2026-09-28 16:28 → 17:03 |
| Fabric host | EC2 `i-06063debd27c12e51`, `13.127.118.165` (`ip-172-31-8-236`), ap-south-1 |
| Fabric network | existing network `fabric_test`, up 19+ days, **not rebuilt, not recreated** |
| Channel | `mychannel` |
| Chaincode | `honeychain` |
| Chaincode version / sequence | **2.0 / 6** (independent proof below) |
| Bridge TLS | Caddy 2.6.2, `/etc/caddy/Caddyfile` = `backend/deploy/Caddyfile.ledger` |
| Bridge API | `honeychain-api.service` (uvicorn, 127.0.0.1:8000) + `internal_fabric` router |
| Gateway service | `honeychain-fabric-gateway.service` (node, 127.0.0.1:9446) |
| Org1 peer / Org2 peer / orderer | `peer0.org1.example.com:7051`, `peer0.org2.example.com:9051`, `orderer.example.com:7050` |

## Independent Fabric-side proof (peer CLI, Org1 Admin MSP)

```
peer lifecycle chaincode querycommitted --channelID mychannel --name honeychain --output json
{
    "sequence": 6,
    "version": "2.0",
    "endorsement_plugin": "escc",
    "validation_plugin": "vscc",
    "approvals": { "Org1MSP": true, "Org2MSP": true }
}
```

```
peer channel getinfo -c mychannel
height 67 -> 68 (createBatch) -> 69 (anchorMerkleRoot) -> 70 (submitEvent)
```

## Fresh real transaction (the required anchor)

The request was sent over HTTPS to `/internal/fabric/anchor` with
`Authorization: Bearer <FABRIC_BRIDGE_TOKEN>`, through the exact Caddy allowlist
routing that `ledger.honeychain.in` uses (a local TLS instance with identical
routing, because the public DNS name does not resolve yet — see Blockers).

| Field | Value |
|---|---|
| Batch ID | `HC-E2E-0928-164429-32505` (created on-chain in this session) |
| Merkle root | `e5508e25d50ba3bd534c4a543de23b01b8355d6babf60547a5fed443a57432c3` |
| **Fabric tx id** | `a105c691e3c8958d6b8938c55becc1fbce0d3b035af465c51e369e8265e5e283` |
| Commit result | `state: CONFIRMED`, `network: fabric:mychannel`, block height 68 → **69** |
| Read-back `getAnchor(batch)` | `anchored: true`, `merkleRoot` matches, `blockchainTxId` = the tx id above |
| Read-back `verifyMerkleRoot(batch, root)` | `verified: true`, `storedRoot == expectedRoot` |
| Bridge `verify_anchor` query | `{"verified": true}` |
| Originated through Render production API | **No** — blocked by DNS + Render env (see Blockers) |
| Local/simulated fallback involved | **No** — `internal_fabric` refuses any non-Fabric adapter; all state read from the real chain |

## Fresh real domain event (submitEvent)

| Field | Value |
|---|---|
| Event id | `evt-e2e-custody-170040` |
| Domain type → chaincode type | `custody_transfer` → `CUSTODY_TRANSFERRED` (accepted) |
| **Fabric tx id** | `3cb7322d250156985bc049b5dcfd487aa4140e4e702f909d99a5858c037af9ed` |
| Commit | confirmed; block height 69 → **70** |
| `getEvent(evt-e2e-custody-170040)` read-back | exact match: type, entityId, metadata, `payloadHash`, `status: RECORDED` |
| Invalid type `made_up_type` | refused: `FABRIC_TRANSACTION_FAILED: no chaincode event type ...` (HTTP 503) |

## Bridge security matrix (verified live on the bridge host)

| Request | Result |
|---|---|
| `GET /internal/fabric/health`, no token | **401** |
| `GET /internal/fabric/health`, wrong token | **401** |
| `GET /internal/fabric/health`, correct token | **200** + real chain facts (`connected`, `mychannel`, `honeychain`, `2.0`, seq `6`, `Org1MSP`, live `getAnchor` probe) |
| `POST /internal/fabric/anchor`, correct token | real tx id (above) |
| `POST /internal/fabric/query`, unknown op | **404** |
| `/api/v1/*` and any other path | **404** (Caddy deny) |
| `kind` other than `anchor`/`event` | **422** (pydantic allowlist) |
| Unset `FABRIC_BRIDGE_TOKEN` on bridge host | endpoints fail closed (**503**) |

Gateway `/health` is a REAL chaincode read: it calls
`evaluateTransaction(getAnchor, "health-check-probe")` and only reports
`connected` when the peer answers; a chaincode failure returns 503 `unavailable`.

## Test suite classification (this session)

- **UNIT / INTEGRATION** (local, mocked transport): `tests/test_fabric_bridge.py` (22), `tests/test_fabric_adapter.py` (21) → all green. Full backend suite: **305 passed, 4 skipped, 7 failed** — the 7 failures are **pre-existing** (identical set fails at clean HEAD without this session's changes; verified by stash + re-run).
- **LIVE_RUNTIME / BRIDGE_E2E** (this document): health, anchor, verify, event, read-back, block heights — all against the real Fabric network over the real bridge stack.
- **PRODUCTION_E2E (Render origin)**: **NOT YET RUN** — blocked (below).

## Blockers (exact manual actions)

1. **DNS** — `ledger.honeychain.in` does not exist (NXDOMAIN; the Let's Encrypt challenge fails on DNS, not on config).
   - Where: GoDaddy DNS console for `honeychain.in` (NS `ns77/ns78.domaincontrol.com`).
   - Action: add record **Type A, Name `ledger`, Value `13.127.118.165`, TTL 300**.
   - Expected: `Resolve-DnsName ledger.honeychain.in` returns `13.127.118.165`; within ~1–10 min Caddy obtains the Let's Encrypt certificate (TLS-ALPN-01 on the already-open port 443; port 80 is NOT required).
2. **Render environment** — production currently reports `{"adapter":"local"}`.
   - Where: Render dashboard → service `honeychain-api` → Environment.
   - Action: set **`FABRIC_BRIDGE_TOKEN`** to the value stored locally at `C:\Users\Admin\.honeychain_bridge_token` (same value as EC2 `backend/.env`; never a `VITE_*` var), and confirm `BLOCKCHAIN_ADAPTER=remote_fabric`, `FABRIC_BRIDGE_URL=https://ledger.honeychain.in`, `FABRIC_CHANNEL=mychannel`, `FABRIC_CHAINCODE=honeychain` (declared in `render.yaml`, applied on the next blueprint sync/deploy).
   - Expected: `GET https://honeychain-api.onrender.com/api/v1/blockchain/health` returns `"adapter":"fabric"` with `channel: mychannel`, `chaincode: honeychain`.

After both actions, the remaining production checks are: Render health → `fabric`,
a Render-originated anchor with a real tx id, and passport/provenance showing that
same tx id.

## Observed transient failure (reported honestly)

The first write attempt of this session through the bridge returned
`502 / 10 ABORTED: failed to endorse transaction` before any write had ever hit
the current gateway process (started Sep 25). The identical `createBatch`
submitted directly 90 seconds later committed normally, and every write since
has committed. No code or configuration was changed in response; treat the first
write after a long-idle gateway as possibly needing one retry.

