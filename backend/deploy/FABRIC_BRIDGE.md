# Fabric bridge deployment (EC2 AWS public hostname)

## Architecture

```
Portal / Flutter
   → https://honeychain-api.onrender.com                  (Render, public API, RemoteFabricAdapter)
   → https://ec2-13-127-118-165.ap-south-1.compute.amazonaws.com
                                                          (EC2, Caddy TLS termination, TLS-ALPN-01)
   → 127.0.0.1:8000                                       (EC2 FastAPI, internal_fabric router)
   → 127.0.0.1:9446                                       (Fabric Gateway service)
   → Hyperledger Fabric (mychannel / honeychain)
```

The bridge hostname is the **AWS-managed public hostname of the EC2 host**. No
custom domain is used: `honeychain.in` is not owned by this team, so
`ledger.honeychain.in` has been removed and must not be reintroduced. The AWS
hostname's A record is managed by AWS and already points at this host's Elastic
IP, so no DNS record has to be created.

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

## The restricted bridge app (`app.bridge_app`)

The three-path allowlist used to live **only** in the Caddy matcher in front of
the EC2 instance. The app on `:8000` has always mounted the entire HoneyChain
API alongside the bridge router (`app/main.py` includes auth, hives, batches,
passports, platform orgs, AI chat, … plus `internal_fabric.router`). Port 8000
was safe only because the Security Group never allowed inbound 8000 and Caddy
404'd everything else.

That protection is edge-dependent. Any transport that reaches the local port
directly bypasses it. `app/bridge_app.py` is a separate ASGI app that mounts
**only** `internal_fabric.router`, so the boundary is enforced by the
application:

```
uvicorn app.bridge_app:app --host 127.0.0.1 --port 8001
```

Run it as its own loopback-only service beside `honeychain-api.service` (which
keeps serving the public API on 8000, untouched). Then:

- Caddy can proxy to `:8001` instead of `:8000`, or
- a transport may target `:8001` directly.

Either way `/api/v1/*`, `/health/*` and the docs surfaces are 404 by FastAPI
default, and the bridge still requires the constant-time
`FABRIC_BRIDGE_TOKEN` bearer check. Tests: `tests/test_bridge_app.py`.

## Temporary demo transport (NOT permanent production)

If no certificate can be obtained for an owned hostname, a Cloudflare Quick
Tunnel can front the bridge for a demo:

```
cloudflared tunnel --url http://127.0.0.1:8001     # :8001, never :8000
```

Limitations, stated plainly:

- The `https://<random>.trycloudflare.com` URL is **temporary**. It changes
  whenever the tunnel process is stopped or recreated, so `FABRIC_BRIDGE_URL`
  must be updated by hand each time.
- Cloudflare documents Quick Tunnels as intended for testing and development,
  **not** permanent production infrastructure.
- It is **not** a claim of permanent production architecture. A real deployment
  needs an owned hostname with a proper certificate.

**Never** point a tunnel at `:8000`: that publishes the whole HoneyChain API,
including open self-registration at `/api/v1/auth/register`.

## Environment variables (names only — never commit values)

### Render (public API service)

| Variable                | Purpose                                              |
|-------------------------|------------------------------------------------------|
| `BLOCKCHAIN_ADAPTER`    | `remote_fabric` (selects the bridge)                 |
| `FABRIC_BRIDGE_URL`     | `https://ec2-13-127-118-165.ap-south-1.compute.amazonaws.com` |
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
4. **Certificate**: no DNS record is needed. Caddy must obtain a Let's Encrypt
   certificate for the AWS hostname via **TLS-ALPN-01** on the already-open
   `443`. Caddy serves a site block by SNI, so if no certificate exists for the
   hostname every handshake fails with `TLSV1_ALERT_INTERNAL_ERROR` and the
   bridge appears dead even though `:443` is listening. Confirm issuance before
   touching Render: `journalctl -u caddy -n 50 | grep -i acme` and
   `curl -sS https://ec2-13-127-118-165.ap-south-1.compute.amazonaws.com/internal/fabric/health`.
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
| A | `GET https://ec2-13-127-118-165.ap-south-1.compute.amazonaws.com/internal/fabric/health` + token | `FABRIC_CONNECTED`, channel/chaincode real |
| B | same, wrong/missing token                                         | `401`                                      |
| C | `POST .../anchor` + token                                         | real `tx_hash`, `CONFIRMED`                |
| D | `POST .../query` verify                                            | `verified: true/false` from chain          |
| E | `GET https://ec2-13-127-118-165.ap-south-1.compute.amazonaws.com/api/v1/auth/login` | `404`                                      |
| F | any `/api/v1/*` through the EC2 bridge host                   | `404`                                      |
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
- [ ] DNS record — **not needed any more**; the AWS hostname's A record is
      managed by AWS and already resolves to this host
- [ ] **BLOCKER**: Caddy holds a valid TLS certificate for the AWS hostname.
      Until it does, the handshake fails with `TLSV1_ALERT_INTERNAL_ERROR`, so
      row A cannot pass and Render must stay on `local`. Check
      `journalctl -u caddy | grep -i acme` on EC2.
- [ ] `FABRIC_BRIDGE_TOKEN` set in the Render dashboard (user; value generated
      2026-09-28 on EC2, stored server-side only)
- [ ] Real Fabric `tx_id` captured from a **Render-initiated** anchor

**The complete path is NOT verified yet.** Do not claim "Blockchain Verified" in
any product surface until H passes with a real transaction id.
