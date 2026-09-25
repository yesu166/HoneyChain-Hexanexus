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
FABRIC_CHANNEL=mychannel / FABRIC_CHAINCODE=honeychain / FABRIC_GATEWAY_URL=http://<gateway-host>:9446
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
flutter run --dart-define=API_BASE_URL=https://honeychain-api.onrender.com
flutter test
```

### Backend URL policy (build flags)

The app never hardcodes a backend or secrets. `API_BASE_URL` is injected at build
time; production/staging must be `https://`:

```bash
flutter build apk --dart-define=API_BASE_URL=https://honeychain-api.onrender.com
```

Plain `http://` is accepted only for local development — `localhost`,
`127.0.0.1`, or the Android emulator host alias `10.0.2.2` (app → host machine):

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8000                 # desktop
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000                   # Android emulator
```

If a compiled URL is rejected by the gate, the app aborts at startup with an
explicit error (`ApiConfig.startUpIssue` in `lib/main.dart`) rather than silently
running without a backend. With no flag, the app runs standalone offline/demo mode.

### Android builds (2026-09-11)

- Debug: `flutter build apk --debug --dart-define=API_BASE_URL=https://honeychain-api.onrender.com`
  → copy from `build/app/outputs/flutter-apk/app-debug.apk`.
- Release: `flutter build apk --release --dart-define=API_BASE_URL=https://honeychain-api.onrender.com`
  builds, but the template still signs
  with the **debug key** — provision a real keystore + Play signing before
  distribution.

## Docker / compose

- `docker-compose.yml` is NOT provided in this repo; the Docker daemon is not
  running on this machine either. Container packaging is **pending** (not
  faked) — see docs/BLOCKERS.md.

## Health endpoints

- `GET /health/live` — process is up.
- `GET /health/ready` — repo reachable + report ledger type; returns
  `not_ready` when the DB layer is unavailable.