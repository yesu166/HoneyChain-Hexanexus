# Blockers (current, with unblock path)

These are the current gaps between the verified HoneyChain prototype and a repeatable, externally reachable production deployment. A real Hyperledger Fabric network is already running and has recorded/read-back transactions; the remaining blockers are deployment hardening, field validation and production operations.

| # | Blocker | Impact | Unblock path |
|---|---|---|---|
| B1 | No `SUPABASE_SERVICE_ROLE_KEY` | backend cannot write to hosted Supabase (works on in-memory repo) | user provides the key to `.env` (`SUPABASE_SERVICE_ROLE_KEY`) and sets `API_ENV=production` |
| B2 | Public Fabric gateway exposure is not complete | The verified Fabric gateway is reachable through the EC2 host/tunnel, but the deployed API/portal cannot yet use it as a normal public HTTPS service | Put the gateway behind authenticated HTTPS or controlled co-location with the API; configure CORS and matching production auth |
| B3 | Fabric gateway authentication is not ready for public exposure | The current gateway is firewalled and reached through the EC2 path/tunnel; public exposure without an auth boundary is unsafe | Add gateway authentication before public exposure |
| B4 | Docker daemon not running | no container builds (`docker build`, compose) | start Docker Desktop in the host before `docker compose up` |
| B5 | `supabase` CLI not installed | cloud-native `db push`/`link` workflow unavailable | use `node supabase/scripts/apply_migrations.js` (works today) |
| B6 | No physical-device Android E2E in the documented audit | Camera/QR scanning, network transitions and field UX are not yet proven on hardware | Test the release build on a real Android device and record the result |
| B7 | Public passport rate limiting is in-memory | Safe for a single instance, but not a shared limiter across multiple backend instances | Move shared rate limiting to Redis or another distributed store when scaling horizontally |

## What is NOT a blocker

- A real Hyperledger Fabric network is already running on EC2 and has recorded/read-back transactions.
- The Fabric adapter and backend-to-gateway path have documented live-runtime proof.
- The Supabase schema migrations are documented as applied to the hosted project.
- Server-side RBAC, authentication, evidence hashing and offline-first sync are implemented/tested.
- EVM anchoring is optional; it is not required for the current Fabric-based provenance path.

## Evidence

See `docs/evidence/live-fabric-backend-proof.md`, `docs/TEST_RESULTS.md`, and `docs/FINAL_TRUTH_REPORT.md` for the recorded transaction IDs, read-back verification and block-height evidence.

**Important:** live Fabric proof is not the same claim as public 24/7 Fabric service. The former is verified; the latter still requires secure external exposure and deployment integration.