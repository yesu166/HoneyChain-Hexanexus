# Blockers (current, with unblock path)

These are the only things standing between the current state (prototype +
real schema + real tests) and production-anchored proving. Each is an
external dependency — no amount of local code can remove it, and we will not
fake it.

| # | Blocker | Impact | Unblock path |
|---|---|---|---|
| B1 | No `SUPABASE_SERVICE_ROLE_KEY` | backend cannot write to hosted Supabase (works on in-memory repo) | user provides the key to `.env` (`SUPABASE_SERVICE_ROLE_KEY`) and sets `API_ENV=production` |
| B2 | No EVM RPC/wallet/contract | `EVMBlockchainAdapter` boundary only; real anchoring unavailable | deploy the anchor contract, export `BLOCKCHAIN_*` env, implement provider call |
| B3 | No started Fabric network | `FabricBlockchainAdapter` boundary only; honest `FABRIC_NOT_CONFIGURED` | answer YES to the final session question to bring up the network, then wire the Gateway SDK |
| B4 | Docker daemon not running | no container builds (`docker build`, compose) | start Docker Desktop in the host before `docker compose up` |
| B5 | `supabase` CLI not installed | cloud-native `db push`/`link` workflow unavailable | use `node supabase/scripts/apply_migrations.js` (works today) |
| B6 | No physical device | camera capture and QR scanning untested on hardware | test on an Android/iOS device with the bundled app |
| B7 | `psql` not installed | ad-hoc SQL via terminal not available | pg Admin / Supabase dashboard SQL editor, or install `psql` |

## What is NOT a blocker

- The API runs testably today: 110 backend + 64 Flutter tests green.
- The schema is real and applied to the project.
- Fabric/EVM integration code is staged behind honest status codes.