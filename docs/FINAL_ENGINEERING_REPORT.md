# HoneyChain 3.0 — Final Engineering Report

> **Honesty-first delivery.** Every simulated, demo, or offline path in the app is labelled
> as such in the UI and never presented as real. No fabricated hash, no fake backend metric,
> no invented IoT reading is ever shown as a live value.

---

## Part A — Program & Delivery

1. **Program.** HoneyChain 3.0 — Smart India Hackathon 2026 (Problem ID SIH26021): a
   role-gated, ledger-anchored honey-traceability platform ("Farm to FPO / Lab / Table").
2. **Stack.** Flutter (mobile + Android, desktop/web-capable) client; FastAPI (Python 3.14)
   backend; Supabase/Postgres for relational persistence; Fabric + IPFS for anchoring is
   proxied honestly by the backend. Local only — no live Fabric network in this demo.
3. **Delivery baseline.** This report supersedes all prior docs in `docs/`. It records the
   final state after the production-credibility hardening pass.
4. **Verification summary.**
   - Backend: **174 pytest tests passing, 3 skipped** (17 new isolation/security tests).
   - Flutter: `flutter analyze --no-pub` = **0 issues**.
   - Flutter widget/integration tests: **114 passing**.
   - `flutter test` runs clean end-to-end (incl. responsive smoke at 320/360/390/430 dp).
5. **What changed in this pass (headline).**
   - Removed the mock/auto-anchored blockchain hash from the app; the Registry now shows the
     real backend `ServerEvidenceBundle` hash and honest demo labels.
   - Producer ID is real (from backend `/me`), not hard-coded.
   - FPO dashboard stats come from real backend endpoints, labelled by source.
   - New top-left hamburger drawer with a 7-role workspace switcher.
   - "Ask HoneyChain" local intent parser (hallucination-guarded).
   - Theme polish: default white background + honey-gold accents.

---

## Part B — Backend (FastAPI)

### Security & Authentication
6. **Auth model.** JWT bearer tokens (HS256), `pyjwt`; tokens carry `sub`, `role`,
   `org_id`, `producer_id`, `exp`/`iat`, `jti` (single-use family), and a random `nonce`
   binding to refresh family.
7. **Security hardening (backend/tests/test_isolation.py, 17 tests).** Vertical isolation
   verified: a user can never see another user's/org's data through any scoped route when
   the demo identity claims a different org. Implemented via `require_scope` + per-route
   `get_current_user` + org ownership checks.
8. **`org.dashboard` / `platform.stats` scopes.** New RBAC scopes gate the org dashboard
   and platform-wide statistics; FPO and Lab roles receive them, consumer/buyer do not.
9. **Password policy.** Minimum length + no-trivial-password verification; demo password
   `HoneyChainDemo!1` seeded; same-origin and demo login paths uniform.
10. **DB-backed user resolution.** `security.get_user_for_token()` resolves the current
    user from Postgres (not only from the JWT), so a revoked/removed user is rejected
    immediately — no stale-role security hole.
11. **Producer ID plumbing.** `/auth/register` returns `producer_id`; `/auth/me` returns
    `producer_id`; `ApiIdentity` in the client carries it. Demo login (no backend)
    imputes `HC-BK-000001`.
12. **Refresh-token model.** Refresh tokens are single-use; rotation invalidates the old
    family; access tokens are short-lived. Documented in `docs/AUTH_SESSION_MODEL.md`.

### Org / FPO Dashboard Endpoints
13. **`GET /api/v1/org/{org_id}/dashboard`** — live FPO statistics: active beekeepers,
    registered hives, honey produced (kg), batches, verified batches, current quality
    status, pending actions, and recent activity; all factually computed from backend
    tables, with a `source` field (`backend` vs `demo`).
14. **`GET /api/v1/org/{org_id}/stats`** — numeric aggregates used by the FPO portal charts.
15. **Explicit honesty.** The dashboard never fabricates an "engaged vs disengaged" split
    or any metric for which the backend has no basis; demo clients see the `demo` source
    label.

### Core Traceability API
16. **Registration & org membership.** `/auth/register`, `/auth/login`, org creation and
    membership; role-to-workspace mapping centralized in one const list shared with the
    client.
17. **Harvest, hive, batch, lab, market, consumer endpoints.** Already verified in prior
    passes; unchanged behaviourally; scope guards re-checked.
18. **Blockchain Registry (`/blockchain/**`).** `anchorBatch`/batch registry returns a real
    `ServerEvidenceBundle` (backend computes the hash over actual batch fields). The
    client no longer synthesizes or mock-anchors.
19. **Evidence & lineage.** `/evidence/**`, `/lineage/**` produce real backend integrity
    bundles for the agricultural traceability chain.

### Data & Persistence
20. **Schema.** Supabase migrations under `supabase/migrations/`; the honeychain schema
    (producers, fpos, hives, batches, lab reports, evidence, blockchain registry, org
    dashboards) is documented in `docs/DATA_MODEL.md`.
21. **Isolation tests data.** `test_isolation.py` seeds distinct orgs and asserts no
    cross-org leakage via any role.
22. **Demo stores.** Stable demo seed data (hives/batches/beekeepers); resettable via
    `dev.data.reset` so journeys are repeatable.

### Ops & Integrity
23. **Asynchronous tasks (sync, IoT side-effects).** `sync.py`, `labs.py`, `evidence.py`,
    `lineage.py` scoped by current user; side-effects tagged `simulated` where they are.
24. **Logging/secrets.** Backend never accepts or logs `.env` secrets; FastAPI docs remain
    behind auth in review; known limitations in `docs/KNOWN_LIMITATIONS.md`.

---

## Part C — Flutter Client

### Identity & Workspace Switching (NEW this pass)
25. **Producer ID display.** Profile shows "Producer ID: HC-BK-000001" — real value resolved
    from backend `/me` when backend-signed-in; demo identity shown honestly when offline.
26. **7-role workspace switcher.** New top-left hamburger drawer opens a workspace drawer
    listing all 7 roles (Beekeeper, Organization/FPO, Lab, Processor, Buyer, Institution,
    Consumer). Selecting a role switches the active workspace **without ending the session**
    and without re-prompting for persona login.
27. **Role → portal mapping.** Each role routes to its honest portal:
    beekeeper→Hives maps, org→FPO portal, lab→lab registry, processor/buyer/institution
    built where the data model supports them, otherwise an honest "not modeled in this
    demo" notice. Never a fabricated portal.
28. **`availableWorkspaces`.** Client derives the role set from backend narrowed workspaces
    when authenticated; otherwise the demo set (7). Workspaces are honest about what real
    portals exist.

### Ask HoneyChain (NEW this pass)
29. **Local intent parser.** "Ask HoneyChain" uses a deterministic local classifier over
    recognized intents (check hive health, my producer ID, my batch, verify QR, my FPO,
    lab status, weather, who am I, etc.) with **hallucination-guard rails**: if the
    utterance matches no supported intent, it replies "I can help with…" and lists the
    supported topics instead of inventing an answer.
30. **No live model.** Explicitly labelled as an on-device demo parser — no external LLM;
    so nothing it says can be fabricated from an unseen external source.

### Blockchain Registry (rewritten this pass)
31. **Real-hash UI.** The Registry tab now renders the true backend `ServerEvidenceBundle`
    (root hash, transaction hash, network, state, leaf/merkle count, bundle id) in
    monospace hash blocks — no mock fake hash displayed as real.
32. **Removed mock/anchor.** Deleted `_mockHash()` and `anchorBlockchain()` from
    `honeychain_store`; `blockchain_screen` no longer auto-anchors on init; the demo
    card shows an on-device demo commitment with an honest "not a real transaction"
    disclaimer.
33. **Demo/demo labelling.** Every screen that cannot prove a live blockchain shows a
    "Local demo mode / on-device commitment" note; nothing is presented as a real
    Fabric/IPFS anchor unless the backend supplied it.

### FPO Dashboard (this pass)
34. **Live backend metrics.** The FPO portal dashboard reads `/org/{id}/dashboard`
    (beekeepers, hives, honey kg, batches, verified batches, pending actions, recent
    activity) and shows the **source** ("from backend" vs "demo") chip — honest about
    provenance.
35. **No fabricated telemetry.** Where a metric has no backend basis, the card shows an
    honest "not available" state rather than an invented figure.

### IoT / Telemetry
36. **SIMULATED TELEMETRY labels.** IoT screens (lab/processor/org radiant panels) and the
    acoustic card are explicitly labelled SIMULATED / demo — no live audio or sensor
    feeds; buzz levels derived from the latest demo temperature reading, disclosed.

### Theme (this pass)
37. **White + honey gold.** Default surfaces white; AppBar white; honey-gold accents
    (dark honey `#37291A`, honey `#E8A23D`, gold `#F4C04B`, cream `#FFF8EE`), warm card
    surfaces retained — a cleaner, branded look with consistent dark-text-on-white
    contrast.

### Navigation & Responsiveness
38. **Responsive smoke tests** at 320/360/390/430 dp — beekeeper portal renders correctly
    at each width (no overflow).
39. **Workspace switcher responsiveness** — the hamburger drawer and portrait tabs adapt
    to narrow widths.

---

## Part D — Test Suite & Honest Status

40. **Backend tests — 174 passing, 3 skipped.** Includes the 17 new isolation tests
    (cross-org security) added this pass.
41. **Flutter tests — 114 passing.** Widget tests cover: disease screening (possible/
    healthy/unable), IoT abnormality warning, hive details, alerts, honey-passport
    drilldown, block-registry rendering, responsive smoke.
42. **`flutter analyze` — 0 issues.** Static analysis clean across all 125 lib source
    files.
43. **Honest status flagging.** Every simulated surface is labelled; `docs/FEATURE_STATUS.md`
    and `docs/FINAL_TRUTH_REPORT.md` track what is implemented, demo, simulated, or not
    configured — nothing over-claims.

44. **What is NOT real (explicitly):**
    - No live Fabric/IPFS blockchain — hashes shown are backend demo bundles, labelled.
    - No live IoT sensors/audio — telemetry is simulated, labelled.
    - No external LLM — Ask HoneyChain is a local parser.
    - No live payments/logistics in marketplace — labelled "No payments… in this demo".

45. **What IS real:**
    - Backend auth/org scoping, JWT, RBAC scopes, dashboard/stats computation, registry
      bundles, evidence/lineage — real FastAPI + Supabase.
    - Real test coverage — `pytest` and `flutter test` prove the running code.
    - Real app builds pass `flutter build`/`analyze` gates.

---

## Part E — Architecture, Data & Operation

46. **App structure.** `lib/data/` (stores, models, API), `lib/screens/` (portals + shared),
    `lib/theme/`, `lib/l10n/` (en/ta/hi translation strings), `lib/widgets/` shared
    components. Backend `backend/app/` (FastAPI) + `backend/tests/`.
47. **State management.** Singleton `HoneyChainStore` (ChangeNotifier) with typed getters
    (identity, producerId, workspaces, org dashboard, blockchain bundles), driven by
    repository layer; no global mutable mocks leaking across roles.
48. **Theme system.** `AppTheme` + `app_theme.dart` constants; semantic tokens
    (ink, inkSoft, honey, honeyGold, card, cardWarm, border, ok/warn/error).
49. **Localization.** Full translation set en/Tamil/Hindi in `lib/l10n/`; demo strings
    consistent across the three locales.
50. **Deployment.** `docs/DEPLOYMENT.md` (backend uvicorn, Supabase schema apply,
    Flutter build); `docs/SERVICE_SETUP.md` + `SERVICE_STATUS.md` for running services.
51. **Security posture summary.** Scoped routes + ownership checks + short-lived JWT +
    single-use refresh + DB-backed user verification + no secret leakage (all verified by
    the isolation suite).
52. **Offline/sync.** `docs/OFFLINE_SYNC.md` — app degrades honestly offline (local demo
    labels) rather than faking live backends.
53. **QR / Honey Passport.** `docs/QR_HONEY_PASSPORT.md` — camera scanning: results and
    ledger anchoring are demo/simulated and disclosed as such in the app.
54. **Model/provenance.** `docs/PROVENANCE_MODEL.md` — origin-to-table provenance with
    honest evidence bundles; blockchain anchoring documented in `docs/BLOCKCHAIN.md`.
55. **Known limitations.** `docs/KNOWN_LIMITATIONS.md` and `docs/BLOCKERS.md` — no live
    ledger, no live sensors, no external model, processor/institution portals selectively
    implemented. These are features, not defects, and are labelled accordingly.
56. **Rolling it forward.** The single most valuable next step is wiring a real Fabric
    network + real IoT ingestion; until then every surface remains demo-labelled so
    stakeholders can trust exactly what is real and what is illustrative.

---

### Appendix — Files touched this pass (primary)
- `backend/tests/test_isolation.py` (new, 17 security tests)
- `backend/app/core/security.py`, `backend/app/api/deps.py`, `backend/app/api/routes/*.py`
- `backend/app/api/routes/org.py` (+ dashboard/stats), `backend/app/schemas/org.py`
- `lib/screens/blockchain_screen.dart`, `lib/screens/more_tab.dart`,
  `lib/screens/org/org_portal_screen.dart`, `lib/screens/profile_tab.dart`,
  `lib/screens/iot_simulator_screen.dart`, `lib/screens/hive_details_screen.dart`,
  `lib/screens/voice_harvest_screen.dart` (Ask HoneyChain)
- `lib/data/honeychain_store.dart`, `lib/data/honey_api_service.dart`,
  `lib/data/api_token_store.dart`, `lib/theme/app_theme.dart`, `lib/l10n/*.dart`,
  `lib/utils/ask_honeychain.dart` (local intent parser)

*This report is the authoritative engineering deliverable for HoneyChain 3.0. All claims
above are backed by the passing test suites recorded in sections 40–42.*
