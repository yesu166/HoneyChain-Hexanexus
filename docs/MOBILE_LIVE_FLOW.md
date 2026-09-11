# Mobile Live Flow

**Scope:** the end-to-end paths a user takes with the mobile app — demo (nominal, offline),
backend-beekeeper (real Fabric), and consumer verification. Companion docs:
`AUTH_SESSION_MODEL.md`, `ROLE_UX_MAP.md`, `QR_HONEY_PASSPORT.md`, `PROVENANCE_MODEL.md`.

Build-time input: all backend wiring is gated on `--dart-define=API_BASE_URL=…`.
With no URL compiled, the app is a fully local, offline-first experience that **never fakes a
backend result**.

## 1. Demo flow (default build — no API_BASE_URL)

```
Role gate → Beekeeper login (OTP-style, local) → MainShell
  ├─ Add harvest → queued offline-first (sync badge)
  ├─ My Hives / alert drills → local records + rule-based screening
  ├─ More → Switch workspace (Organization / Buyer / Consumer) — same session
  └─ Passport → local trust tier + "Online verification not available in this build"
```

Everything is honest: sync badges reflect the offline queue, and the passport panel states
there is no backend instead of inventing verification.

## 2. Backend-beekeeper flow (built with API_BASE_URL)

1. **Sign in** — Login screen offers real FastAPI sign-in
   (`demo@honeychain.in` / `HoneyChainDemo!1`, role `beekeeper`).
2. **Session** — JWT + identity persisted (`ApiTokenStore`); restored on restart
   (`_restoreBackendSession`). `AuthState.authenticated` only when the health probe succeeds.
3. **Hives** — `GET/POST /api/v1/hives` scoped to the beekeeper.
4. **Harvests** — `POST /api/v1/harvests` (push-through keeps the local offline copy).
5. **Evidence anchor** — `POST /api/v1/evidence/bundles` with `anchor: true` submits the
   merkle root to the live EC2 Fabric gateway (port 9446 via SSH tunnel) → real `committed` tx.
6. **Chain status** — Blockchain screen: `/api/v1/blockchain/health` + `/status` (live chain
   info or honest "anchor pending" when unreachable).
7. **Logout** — `beekeeperSignOut()` clears JWT + server collections; local data and the
   pending queue stay.

> Running this end-to-end requires the SSH tunnel to the EC2 Fabric gateway to be up and the
> FastAPI server configured with the matching local repository/Fabric env. **A physical-device
> E2E of this flow was NOT TESTED in this environment** (no Android device/emulator).

## 3. Consumer verification flow

```
Open Consumer workspace → type/paste a code or scan a QR
  → local records resolve (offline-first) → Honey Passport
  → Online verification panel (needs API_BASE_URL):
      GET /api/v1/passport/{subject_code}  (public, rate-limited)
      → verified [trust tier + anchor tx] | not found | rate limited | unreachable | error
```

Offline / no backend → local passport only, honestly labelled.

## 4. Failure taxonomy (what each state means)

| UI state | Meaning |
|---|---|
| "No backend configured — using saved account" | app built **without** `API_BASE_URL` |
| "Offline — using saved account" | session live, device offline or backend unreachable |
| "anchor pending" | backend reachable but the anchor is not yet committed |
| "Online verification not available" | no backend built in; local records still valid |
| `Backend not configured` (login/dev screens) | same as #1 on those screens |

## 5. Verified vs not verified (2026-09-11)

- ✅ `flutter test` → 112 passed; `flutter analyze` clean; backend `pytest` → 157/3.
- ✅ Service-level wiring unit-tested with `MockClient` (auth, hives, harvests, evidence/Fabric,
  sync gateway, passport verification).
- ✅ Live Fabric path proven backend-side (real committed tx + read-back).
- ⚠️ `NOT TESTED`: phone E2E, on-device offline/network failure, and the full QR camera scan
  (no Android device/emulator available).
- ⚠️ `NOT VERIFIED`: Supabase writes (no service-role key).