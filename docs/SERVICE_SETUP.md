# Service Setup Guide

## Supabase project (already reached)

- Project ref: `hhxwhopaazqjdlreqhkf`
- Host: `https://hhxwhopaazqjdlreqhkf.supabase.co`
- DB host: `db.hhxwhopaazqjdlreqhkf.supabase.co:5432`
- Migrations 001–006 are **applied** (verified this session).

To re-apply / confirm:
```bash
cd supabase/scripts
# export SUPABASE_DB_URL=postgresql://postgres:<url-encoded-password>@db.<ref>.supabase.co:5432/postgres
npm run apply
```

To enable backend writes (currently blocked):
```bash
# in backend/.env
SUPABASE_SERVICE_ROLE_KEY=<from project Settings → API → service_role>
```

## Backend

```bash
cd backend
python -m venv ..\.venv_backend
..\.venv_backend\Scripts\pip install fastapi "uvicorn[standard]" pydantic supabase cryptography PyJWT
..\.venv_backend\Scripts\uvicorn app.main:app --reload
```

## Test run (single command)

```bash
cd backend && ..\.venv_backend\Scripts\python.exe -m pytest -q
cd .. && flutter test
```

## New external integrations (not yet wired)

- **EVM**: needs `BLOCKCHAIN_RPC_URL`, `BLOCKCHAIN_CHAIN_ID`,
  `BLOCKCHAIN_CONTRACT`, `BLOCKCHAIN_PRIVATE_KEY`, plus provider SDK wiring in
  `EVMBlockchainAdapter`.
- **Fabric**: needs a running network + connection profile; then implement
  `FabricBlockchainAdapter` with the Gateway SDK.
- **Object storage for photo bytes**: decide (e.g. Supabase Storage); currently
  only `content_hash` + metadata are stored.