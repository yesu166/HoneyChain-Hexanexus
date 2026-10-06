# HoneyChain — Access & Permission Audit

Audit date: 2026-09-10
Environment: Windows 11, PowerShell 5.1, working dir `HoneyChain-main`

Purpose: classify every capability the agent may (or may not) use before
modifying the project. Classifications:

- GRANTED — verified available and usable now.
- DENIED — explicitly refused by user/host policy.
- NOT_AVAILABLE — not present/installed/detected in this environment.
- NOT_REQUIRED — not needed for the current task or PVC.
- BLOCKED — present in principle but a dependency prevents use.

| # | Capability                 | Status        | Evidence / Notes |
|---|----------------------------|---------------|------------------|
| 1 | Local repository           | GRANTED       | Git repo on branch `main`, clean tree, commit `f319697`. |
| 2 | Terminal                   | GRANTED       | PowerShell 5.1 shell available. |
| 3 | Filesystem                 | GRANTED       | Full read/write on project tree. |
| 4 | Git                        | GRANTED       | `git 2.55.0`, local commits possible. |
| 5 | GitHub                     | NOT_AVAILABLE | Repo `yesu166/HoneyChain` is private; no `gh` auth token detected. No push/pull performed in this session. |
| 6 | AWS (EC2 ap-south-1)       | BLOCKED       | `~/.aws` has no credentials files. EC2 deployment explicitly planned "tomorrow" by user; DO NOT claim live. |
| 7 | SSH                        | BLOCKED       | `~/.ssh` contains only `known_hosts` — no private key for the `Honeychain` EC2 instance. |
| 8 | Docker                     | BLOCKED       | `docker version` hangs (daemon not running). Attempt made 2026-09-10; will retry before claiming Fabric local run. |
| 9 | Flutter                    | GRANTED       | `flutter 3.47.1` / Dart 3.13.1 reported. |
| 10 | Android build              | PARTIAL       | `releases/HoneyChain-v2.0.2.apk` exists; release build previously reached `assembleRelease`. No physical device attached for runtime verification. |
| 11 | Supabase project           | GRANTED       | Project `hhxwhopaazqjdlreqhkf` (URL + DB URL + service-role key + publishable key authorized by user for this session). Credentials server-side/`.env` only. |
| 12 | PostgreSQL                 | GRANTED       | `SUPABASE_DB_URL` present in root `.env` + `supabase/scripts/.env`; migrations run via `node supabase/scripts/apply_migrations.js`. |
| 13 | Network access             | PARTIAL       | Needs live verify against Supabase REST + DB endpoints (performed later in this run, see `REAL` evidence). |
| 14 | Hyperledger Fabric         | NOT_CONFIGURED| No running network. `fabric/` contains deployment definition only (chaincode, docker-compose, configtx, crypto). |
| 15 | Fabric Gateway             | NOT_CONFIGURED| Backend `FabricBlockchainAdapter` is an honest boundary stub; no `fabric-gateway` SDK wired. |
| 16 | Chaincode                  | PARTIAL       | `fabric/chaincode/tracer` source present and structurally valid; `node_modules` never installed (`npm start` fails without deps). |
| 17 | Camera                     | NOT_AVAILABLE | No physical device; `mobile_scanner` wired but runtime camera scan not hardware-verified. |
| 18 | Device storage             | GRANTED       | Flutter `shared_preferences` offline-first persistence in use. |
| 19 | Environment variables      | GRANTED       | `.env` files gitignored; only `.env.example` tracked (placeholders). |
| 20 | External APIs (EVM/AI/weather) | NOT_CONFIGURED| EVM adapter boundary-only; AI = rule-based `risk_engine`; weather absent. |

## Secret handling rules (active)

- Real values live ONLY in gitignored `.env` files on this machine.
- `.env.example` files contain variable names and safe placeholders only.
- Supabase service-role key & DB password never enter: Flutter source, Git,
  logs, screenshots, README, `.env.example`, or this document.
- Fabric MSP private keys are gitignored; never committed.

## Interrupt / approval gates

Per the master prompt: no further permission prompts for granted items. Agent
interrupts only for: genuinely missing essential secrets, destructive ops,
explicit security-boundary approvals, or the final Fabric deployment gate.