# Security

## Authentication

- Passwords: PBKDF2-HMAC-SHA256, 480k iterations, per-user salt
  (`pbkdf2$...$salt$digest`).
- JWT: HS256 signed with `JWT_SECRET` (production refuses to boot without it).
- Roles live in the signed token; role resolution is server-side.

## Authorization (RBAC)

- `backend/app/core/rbac.py` is the single matrix (7 roles × ~24 actions).
- `require_permission(action)` dependency; scope helpers in the service layer.
- Tamper endpoints additionally require non-production `API_ENV`.

## Secrets

- Credentials are env-only, gitignored. `.env` holds `SUPABASE_DB_URL` and is
  never committed (`.gitignore`). `.env.example` has placeholders.
- `BLOCKCHAIN_PRIVATE_KEY` is read from env, never logged, never serialized
  into API responses.

## Ledger honesty guarantees

- No fake `CONFIRMED`. Confirmation only from a reachable ledger.
- `FABRIC_NOT_CONFIGURED` / `BLOCKCHAIN_NOT_CONFIGURED` / `FABRIC_UNAVAILABLE`
  states are returned verbatim.
- `local` ledger is labeled `local` in every API response.

## Data protections in the design

- Raw photos/lab sheets never reach a ledger; only canonical SHA-256 hashes.
- Passports are PII-free by construction (public consumer view).
- Evidence bundles include operator + device_id attribution for accountability.

## Known boundaries (honest limits)

- RLS policies in migrations 002/006 assume Supabase Auth identities.
  The service-role backend path bypasses RLS (by design — server code is the
  enforcement layer).
- Rate limiting exists for the public passport endpoint (per-minute/IP) but
  is in-memory; production should move it to Redis for multi-instance.