# Auth & Session Model — HoneyChain Flutter app

**Scope:** how a user session works in the mobile app, how it survives restarts, and how the
app stays honest about its connection state. Companion docs: `ROLE_UX_MAP.md` (workspaces),
`QR_HONEY_PASSPORT.md` & `PROVENANCE_MODEL.md` (passport/provenance), `MOBILE_LIVE_FLOW.md`
(end-to-end live flows).

Source of truth: `lib/data/auth.dart` (enums), `lib/data/honeychain_store.dart`
(`ensureStarted`, `authState`, workspace getters), `lib/services/api_token_store.dart` (JWT
persistence), `lib/services/local_store.dart` (session workspace persistence).

## 1. One source of truth, not scattered booleans

Before this pass the app tracked auth with separate flags (`_loggedIn`, `_fpoRole`,
`_beekeeperChosen`). That made "what is my session really doing?" ambiguous. The store now
derives a single, honest state:

```dart
enum AuthState {
  unknown,                 // app still starting
  signedOut,               // no active session → first-launch gate
  authenticated,           // session + backend health probe OK
  offlineAuthenticated,    // session live but no reachable backend
}
```

`HoneyChainStore.authState` is computed from three inputs:

1. the persisted login flag,
2. whether an `API_BASE_URL` was compiled in (`ApiConfig.isConfigured`),
3. live connectivity / backend health.

Because `ApiConfig.isConfigured` is a build-time constant, a locally-compiled app can *never*
report "authenticated" — the honest label is displayed instead.

## 2. Durable session

- `lib/services/api_token_store.dart` keeps the backend JWT + identity
  (`token / id / email / name / role / organizationId`) in `SharedPreferences`.
- **Fix in this pass:** `ApiTokenStore.instance.init()` is now invoked inside
  `HoneyChainStore.ensureStarted()` (previously the token store was never initialized from the
  app, so a backend sign-in evaporated on restart). On startup the store restores
  `_backendSignedIn` / `_backendRole` from the persisted identity.
- `init()` re-reads the persisted identity each time (safe: the store is a long-lived
  singleton), so restarts and tests always mirror disk.
- The `loggedIn` flag and the selected workspace are persisted in `LocalStore`.

## 3. Session state map

| State | Meaning | What the UI shows |
|---|---|---|
| `signedOut` | `loggedIn == false` | First-launch role gate → login |
| `authenticated` | signed in, backend configured and healthy | Normal shell + "Signed in to the backend" |
| `offlineAuthenticated` (device offline) | signed in, no network | Shell works on local data; queued sync drains later |
| `offlineAuthenticated` (backend down) | signed in, backend unreachable | "Offline — using saved account"; honest error cards |
| `offlineAuthenticated` (no backend built) | signed in, no `API_BASE_URL` | "No backend configured — using saved account" |

## 4. Logout is non-destructive

`HoneyChainStore.logout()` and `beekeeperSignOut()` only clear the **session** flag and (for
backend sign-out) the JWT. They never delete hives, harvests, batches, custody, jars,
passports, or the pending-sync queue. Covered by `test/auth_session_test.dart`
("logout returns to signed-out but keeps domain data").

## 5. Deliberately NOT implemented

- **No password manager / social login / phone verification against Supabase Auth.** The demo
  uses a local OTP-style login; backend sessions use the FastAPI JWT endpoint.
- **No multi-tenant data separation per workspace** — the store is one shared local dataset
  that the beekeeper and organization viewpoints read. This is honest for the demo data model;
  see `ROLE_UX_MAP.md`.