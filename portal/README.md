# HoneyChain HC-3.0 Live Operations Portal

This folder is an additive web operations portal for the existing HC-3.0 repository.

## Design rules

- The existing Flutter application, backend, Fabric network and Supabase layout are not replaced.
- The portal is served by the existing FastAPI process at `/portal/`.
- The browser never decides its own authorization role. After sign-in, `/api/v1/auth/me` is the source of truth.
- The role switcher only changes presentation. It does not grant permissions.
- Live data comes from HC-3.0 API endpoints. Errors are shown as errors.
- The portal has an authenticated request console so newly added API endpoints can be exercised without creating a second API layer.

## Run

Start the HC-3.0 FastAPI service from `backend/`, then open:

`http://127.0.0.1:8001/portal/`

The API base defaults to the current origin. The Connect dialog can point at another HC-3.0 API during local development.

## Live path

`Portal -> FastAPI -> RBAC -> service -> SupabaseRepository -> Supabase/PostgreSQL`

Blockchain health is read through the existing HC-3.0 blockchain adapter. When Fabric is selected and configured, the existing Python Fabric adapter continues through the existing Node.js Fabric Gateway.

This portal intentionally does not create a parallel database, blockchain client, mock repository or duplicate endpoint namespace.
