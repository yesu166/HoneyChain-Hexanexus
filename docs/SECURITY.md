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

- Credentials are env-only, gitignored. `.env` holds `SUPABASE_DB_URL` and
  backend secrets and is never committed (`.gitignore`). `.env.example` has
  placeholders only.
- `GEMINI_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `JWT_SECRET`,
  `BLOCKCHAIN_PRIVATE_KEY`, `FABRIC_BRIDGE_TOKEN`, and database credentials
  are server-side secrets. They must never be placed in Flutter, Vite
  `VITE_*` variables, source code, or committed files.
- `DEMO_PASSWORD` is also environment-only. Demo identities are for local
  demonstration/testing and must not be treated as production credentials.
- `BLOCKCHAIN_PRIVATE_KEY` is read from env, never logged, never serialized
  into API responses.
- Backend JWTs are stored in Flutter platform secure storage. A one-time
  migration removes JWTs left in legacy SharedPreferences by older builds.
- If a real secret has ever existed in a developer `.env`, treat it as
  compromised before sharing that folder and rotate it in the owning service.
- The public Supabase publishable/anon key is not a substitute for the
  service-role key; service-role and database credentials remain server-only.

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