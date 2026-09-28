# Fabric bridge deployment (ledger.honeychain.in)

## Architecture

```
Portal / Flutter
   → https://honeychain-api.onrender.com        (Render, public API, RemoteFabricAdapter)
   → https://ledger.honeychain.in               (EC2, Caddy TLS termination, HTTP-01)
   → 127.0.0.1:8000                             (EC2 FastAPI, internal_fabric router)
   → 127.0.0.1:9446                             (Fabric Gateway service)
   → Hyperledger Fabric (mychannel / honeychain)
```

- Render holds **no** Fabric identity and **no** Fabric credentials.
- EC2 holds the Fabric identity and the real `FabricBlockchainAdapter`.
- `RemoteFabricAdapter` (`app/adapters/blockchain/bridge.py`) implements the same
  `LedgerAdapter` interface as the in-process adapter, so evidence/assertion
  services are unchanged.
- `_ensure_batch_on_ledger` runs **on EC2 only** — the real adapter performs the
  `getBatch` probe and issues `createBatch` only when the chain reports
  `NOT_FOUND`. It is never duplicated on the Render side.
- No local fallback. If EC2 is unreachable the API reports
  `FABRIC_UNAVAILABLE` / `FABRIC_TIMEOUT`; it never downgrades to the local
  development ledger.

## Environment variables (names only — never commit values)

### Render (public API service)

| Variable                | Purpose                                              |
|-------------------------|------------------------------------------------------|
| `BLOCKCHAIN_ADAPTER`    | `remote_fabric` (selects the bridge)                 |
| `FABRIC_BRIDGE_URL`     | `https://ledger.honeychain.in`                       |
| `FABRIC_BRIDGE_TOKEN`   | shared service secret (same value as on EC2)         |
| `FABRIC_BRIDGE_TIMEOUT` | seconds per bridge call (default `30`)               |
| `FABRIC_CHANNEL`        | `mychannel` (status display only)                    |
| `FABRIC_CHAINCODE`      | `honeychain` (status display only)                   |

`FABRIC_BRIDGE_TOKEN` must **never** be a `VITE_*` variable: `VITE_*` values are
inlined into the browser bundle and shipped to every visitor.

### EC2 (Fabric host)

| Variable              | Purpose                                        |
|-----------------------|------------------------------------------------|
| `FABRIC_BRIDGE_TOKEN` | shared service secret (same value as Render)   |
| `FABRIC_CHANNEL`      | `mychannel`                                    |
| `FABRIC_CHAINCODE`    | `honeychain`                                   |

Generate the secret server-side, e.g. `openssl rand -hex 32`, and store it only
in the two runtime env files. Never log it, never return it in a response.

## Wire-up

1. **EC2**: install Caddy, copy `deploy/Caddyfile.ledger` to
   `/etc/caddy/Caddyfile`, `systemctl enable --now caddy`.
2. **EC2**: add `FABRIC_BRIDGE_TOKEN` to the backend runtime env and restart
   `honeychain-api.service`.
3. **EC2 (defense in depth)**: rebind the FastAPI service from
   `--host 0.0.0.0` to `--host 127.0.0.1`. The Security Group does not allow
   `8000`, but loopback-only removes the dependency on the SG staying correct.
4. **DNS (user)**: `ledger.honeychain.in A <EC2 IP>`, TTL 300, DNS-only.
5. **SG**: nothing to do — the Security Group already exposes TCP `443`, and
   the Caddyfile now uses the **TLS-ALPN-01** challenge on that open port
   (`disable_http_challenge`), so TCP `80` is **not required** for certificate
   issuance or renewal. (Verified 2026-09-28: 443 reachable, 80 blocked.)
6. **Render**: set the env table above and deploy.

Caddy obtains the certificate automatically via TLS-ALPN-01 on the first retry
after DNS resolves (restart with `sudo systemctl restart caddy` to make it
immediate).

## Verification matrix (must all pass before claiming real anchoring)

| # | Check                                                             | Expected                                   |
|---|-------------------------------------------------------------------|--------------------------------------------|
| A | `GET https://ledger.honeychain.in/internal/fabric/health` + token | `FABRIC_CONNECTED`, channel/chaincode real |
| B | same, wrong/missing token                                         | `401`                                      |
| C | `POST .../anchor` + token                                         | real `tx_hash`, `CONFIRMED`                |
| D | `POST .../query` verify                                            | `verified: true/false` from chain          |
| E | `GET https://ledger.honeychain.in/api/v1/auth/login`              | `404`                                      |
| F | any `/api/v1/*` through ledger host                               | `404`                                      |
| G | Render `/api/v1/blockchain/health`                                | `adapter: fabric`, real channel/chaincode  |
| H | real anchor via Render, then public passport/provenance           | real `tx_id` persisted, no `LOCAL-*`       |
| I | EC2 bridge down → Render anchor attempt                           | `FABRIC_UNAVAILABLE`/`FABRIC_TIMEOUT`, no local fallback |
| J | timing                                                            | anchor within `FABRIC_BRIDGE_TIMEOUT`, else timeout |

## Status

Verified live on **2026-09-28** (see `docs/evidence/fabric-bridge-fresh-e2e-2026-09-28.md`):

- [x] `RemoteFabricAdapter` implemented + unit/integration tested (22 tests,
      including `submit_event` → bridge `kind=event`)
- [x] `/internal/fabric/*` router implemented + tested; deployed to EC2
- [x] Caddyfile written (`deploy/Caddyfile.ledger`) — TLS-ALPN-01, port 80 not needed
- [x] Caddy installed and live on EC2 (2.6.2, 80/443 listening, config validated)
- [x] Verification matrix A–F executed against the live bridge (401/401/200/real
      facts/404/404), G pending Render env, H/I/J pending DNS + Render
- [x] Real Fabric `tx_id` captured through the bridge stack:
      anchor `a105c691e3c8958d6b8938c55becc1fbce0d3b035af465c51e369e8265e5e283`
      (block 68→69), event `3cb7322d250156985bc049b5dcfd487aa4140e4e702f909d99a5858c037af9ed`
      (block 69→70), both read back from the chain
- [ ] DNS record created (user — GoDaddy, blocker for cert + Render connectivity)
- [ ] `FABRIC_BRIDGE_TOKEN` set in the Render dashboard (user; value generated
      2026-09-28 on EC2, stored server-side only)
- [ ] Real Fabric `tx_id` captured from a **Render-initiated** anchor

**The complete path is NOT verified yet.** Do not claim "Blockchain Verified" in
any product surface until H passes with a real transaction id.
