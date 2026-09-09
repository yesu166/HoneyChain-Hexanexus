# Deployment

## Modes

- **development** (current, working): in-memory repo + local ledger, `/docs`
  on, demo identities seeded, tamper endpoints enabled.
- **production**: requires `JWT_SECRET`, uses `SUPABASE_SERVICE_ROLE_KEY`,
  `/docs` off, tamper endpoints 403.

## Backend

```
cd backend
python -m venv .venv_backend
.\.venv_backend\Scripts\pip install -r requirements.txt   # if present
.\.venv_backend\Scripts\uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Env vars (see `.env.example`):

```
API_ENV=development|production
JWT_SECRET=...
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_ANON_KEY=
BLOCKCHAIN_ADAPTER=local|evm|fabric
BLOCKCHAIN_RPC_URL= / BLOCKCHAIN_CHAIN_ID / BLOCKCHAIN_CONTRACT / BLOCKCHAIN_PRIVATE_KEY=
FABRIC_CHANNEL=honeychain / FABRIC_CHAINCODE=tracer
AI_ADAPTER=risk_engine
PASSPORT_RATE_LIMIT_PER_MINUTE=60
```

## Database migrations (works today)

```
cd supabase/scripts
# SUPABASE_DB_URL set in env
npm run apply
```

Verified this session: 001–006 all applied to
`db.hhxwhopaazqjdlreqhkf.supabase.co`.

## Flutter

```bash
flutter pub get
flutter run            # or flutter build apk
flutter test           # 64 tests
```

## Docker / compose

- `docker-compose.yml` is NOT provided in this repo; the Docker daemon is not
  running on this machine either. Container packaging is **pending** (not
  faked) — see docs/BLOCKERS.md.

## Health endpoints

- `GET /health/live` — process is up.
- `GET /health/ready` — repo reachable + report ledger type; returns
  `not_ready` when the DB layer is unavailable.