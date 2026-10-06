# HoneyChain Security Audit

**Scope:** backend, database policy, web portal, authentication, QR/Honey Passport, deployment configuration and role enforcement.

**Method:** source-level inspection of the two integrated repositories and the current HoneyChain branch state. This is a code audit, not a penetration test. Findings are stated only where the inspected code supports them.

## Executive assessment

HoneyChain has several strong security foundations: server-side RBAC, resource-scope checks, PBKDF2 password hashing, environment-only secrets, production JWT-secret enforcement, a separately authenticated Fabric bridge, public-passport rate limiting, production-disabled tamper endpoints, explicit CORS and a deliberate separation between live data and portal demo preview.

There are also several issues that should be treated before a production government deployment. The most important are **Supabase row-level policies that are broader than the application's server-side role model**, **JWT storage in browser localStorage**, **lack of login rate limiting**, and **long-lived access tokens**.

One application-level authorization issue was fixed during this integration: the backend's `require_roles()` helper previously checked only the primary role even though the platform supports multi-role accounts. It now grants access when any authenticated role matches the required role, while server-side permission/scope checks remain authoritative.

## Findings

### S1 — HIGH: Direct Supabase RLS can permit arbitrary health-score insertion

**Location:** `supabase/migrations/002_rls_policies.sql`

The policy `health_scores_insert_auth` uses:

```sql
create policy health_scores_insert_auth
on health_scores
for insert to authenticated
with check (true);
```

This means any authenticated Supabase client that can reach the table directly can insert a health-score row without an ownership, hive or organisation condition.

**Impact**

A compromised or deliberately modified client could write health scores for unrelated hives. That undermines trust in health evidence.

**Current mitigating architecture**

The inspected application routes domain operations through the FastAPI backend, which uses the server-side repository/service layer. No direct `supabase.from(...)` client path was found by the repository search used in this audit. That lowers immediate exploitability through the shipped application but does not make the database policy safe as a standalone boundary.

**Recommended remediation**

Remove the broad authenticated INSERT policy and allow writes only through the trusted server/service-role path, or replace it with an explicit hive/org ownership condition if direct authenticated writes are genuinely required.

**Priority:** before production.

---

### S2 — HIGH: Laboratory RLS is not sufficiently resource-scoped

**Location:** `supabase/migrations/002_rls_policies.sql`

The laboratory policies currently use role-only checks such as:

```sql
with check (public.auth_user_role() = 'lab')
```

and:

```sql
using (public.auth_user_role() = 'lab')
```

These conditions do not additionally bind the lab test to the authenticated laboratory's organisation or to a batch within that organisation.

**Impact**

If direct Supabase database access is available to an authenticated laboratory client, a lab identity could potentially create or modify records outside its intended organisation scope.

**Current mitigating architecture**

The FastAPI route layer additionally enforces authenticated roles and laboratory scope. The repository uses the backend service boundary for application operations.

**Recommended remediation**

Make the RLS policy enforce the same organisation/batch relationship as the backend, or remove direct authenticated write capability and keep laboratory writes server-mediated.

**Priority:** before production.

---

### S3 — MEDIUM/HIGH: Organisation and cluster reads are globally open to authenticated DB clients

**Location:** `supabase/migrations/002_rls_policies.sql`

The inspected policies include:

```sql
clusters ... using (true)
organizations ... using (true)
```

for authenticated readers.

**Impact**

An authenticated direct database client can potentially enumerate organisations/clusters beyond the user's operational scope.

**Recommended remediation**

Use explicit organisation membership/oversight rules in RLS. Government/platform roles can have broader read scope; producer/business roles should receive only the organisation/cluster data necessary for their workflow.

**Priority:** high before exposing direct Supabase access.

---

### S4 — MEDIUM: HoneyChain JWT is stored in browser localStorage

**Location:** `web-portal/src/lib/hc/client.ts`

The HoneyChain API access token is stored under:

```text
honeychain.jwt
```

in `localStorage`.

**Impact**

If an XSS vulnerability ever exists in the portal or a third-party script can execute in the origin, JavaScript can read the bearer token and replay it until expiry.

This is different from the portal's server-side Better Auth cookies, which are configured with secure cookie protections. The separate REST bearer token remains the concern.

**Recommended remediation**

Preferred architecture:

1. keep API authentication in an HttpOnly, Secure, SameSite cookie;
2. or proxy API calls through the portal server and keep the backend token server-side;
3. use short-lived access tokens plus refresh-token rotation if bearer storage must remain.

**Priority:** medium for current demo; high before sensitive government deployment.

---

### S5 — MEDIUM: Login has no visible abuse/rate limiter

**Location:** `backend/app/api/routes/auth.py` and `backend/app/services/auth_service.py`

The repository contains a reusable in-memory rate limiter and uses it for public passport/other protected surfaces, but the inspected login route does not call it.

**Impact**

Repeated credential guesses can be attempted against the public login endpoint.

**Recommended remediation**

Rate-limit failed login attempts using a combination of client IP and account identifier, with a sensible lockout/backoff policy. For multi-instance production, use a shared limiter such as Redis rather than process-local memory.

**Priority:** before production.

---

### S6 — MEDIUM: Access tokens default to seven days

**Location:** `backend/app/core/config.py` and `backend/.env.example`

Default:

```text
ACCESS_TOKEN_EXPIRE_MINUTES=10080
```

10080 minutes is seven days.

**Impact**

If a bearer token is stolen, the replay window is long.

**Recommended remediation**

Use short-lived access tokens and a secure refresh mechanism. If a seven-day session is required for rural workflows, make the long-lived artifact a rotating refresh token rather than the access token itself.

**Priority:** before production.

---

### S7 — MEDIUM: Public passport enumeration depends on identifier strength

**Location:** `backend/app/api/routes/passport.py`, `services/passport_service.py`, `web-portal/src/lib/hc/passport.ts`

Public passport lookup accepts batch/package-style codes. The package generator uses high-entropy random material for new generated package codes, but the generic passport endpoint also accepts bare codes and historically structured batch identifiers can be predictable.

The public endpoint is rate-limited, which is good, but rate limiting does not remove enumeration risk when identifiers are predictable.

**Impact**

A third party who can guess valid public identifiers may retrieve whatever PII-free passport information is intentionally exposed.

**Recommended remediation**

Use high-entropy public verification identifiers for consumer scans, keep batch IDs internal, or require an explicit public-token/code separate from operational batch identifiers.

**Priority:** medium.

---

### S8 — MEDIUM: Blockchain transaction retry lacks a dedicated permission

**Location:** `backend/app/api/routes/blockchain.py`

The route:

```text
POST /api/v1/blockchain/transactions/{tx_ref}/retry
```

requires authentication but the inspected implementation does not require a dedicated blockchain-management permission.

**Impact**

Any authenticated user who obtains a transaction reference may be able to trigger retry behavior intended for operational/admin workflows.

**Recommended remediation**

Add a specific permission such as `blockchain.retry` and grant it only to admin/platform-oversight roles or to the smallest operational role that actually needs it.

**Priority:** medium.

---

### S9 — LOW/MEDIUM: Public blockchain health can reveal infrastructure details

**Location:** `backend/app/api/routes/blockchain.py`

The public blockchain health route is intentionally unauthenticated and can return adapter/ledger health information. When a Fabric adapter is active, the response can contain network/channel/chaincode/peer-related fields.

**Impact**

This is mostly information disclosure rather than direct compromise, but detailed infrastructure metadata helps reconnaissance.

**Recommended remediation**

Keep the public endpoint to a minimal status such as `healthy/unavailable`. Put detailed channel/peer/chaincode diagnostics behind authenticated admin access.

**Priority:** hardening.

---

### S10 — LOW/MEDIUM: Current rate limiter is process-local

**Location:** `backend/app/api/rate_limit.py`

The rate limiter keeps counters in an in-memory dictionary.

**Impact**

With multiple backend instances, each instance has its own view of the limit. An attacker can potentially bypass an intended global limit by spreading requests across instances.

**Recommended remediation**

Use a shared store such as Redis for production multi-instance deployments.

**Priority:** scale-out hardening.

---

### S11 — MEDIUM: CORS and public-origin configuration must remain explicit after portal rename

The integrated repository now uses the new HoneyChain web-portal naming in the backend CORS fallback/regex and in the portal deployment example.

The production rule remains:

> **Prefer explicit `CORS_ORIGINS` in deployment configuration over broad origin patterns.**

Never solve deployment problems with `allow_origins=["*"]` while allowing credentials.

## Controls that are already good

### Password handling

Passwords use PBKDF2-HMAC-SHA256 with a per-password random salt and a high iteration count.

### JWT signing

Production refuses to start without a configured JWT secret, and production secrets are validated for minimum length.

### Role enforcement

The permission matrix lives in the backend. UI visibility is not treated as an authorization boundary.

### Resource scoping

Beekeeper and organisation ownership checks are implemented in the backend/service layer.

### Fabric bridge

The internal Fabric bridge uses a server-side shared token and constant-time comparison, rejects an unset credential, constrains operations and is intended to sit behind a narrow proxy allowlist.

### Demo tamper routes

Tamper endpoints are blocked in production.

### Honey Passport privacy

The public passport service deliberately excludes PII such as phones, emails and KYC information.

### QR design

The QR identifies a record; it is not treated as cryptographic proof itself. The public passport resolves against live backend data and reports blockchain state honestly.

### Portal request isolation

The web portal includes server-side request-origin/Fetch Metadata isolation and protected route gates.

### Demo/live separation

The portal does not silently switch from failed live API requests to synthetic data.

## Authorization issue fixed during this integration

The backend previously implemented:

```python
if user.role == "admin" or user.role in roles:
```

inside `require_roles()`.

Because HoneyChain supports multi-role identities, an account with a permitted secondary role could be denied even though the permission matrix correctly granted that role.

The implementation now checks all authenticated roles:

```python
if user.role == "admin" or any(r in roles for r in user.roles):
```

and a regression test has been added to `backend/tests/test_rbac.py`.

## QR / branding changes included

The product-facing naming is now:

**HoneyChain** → overall platform  
**Honey Yatra QR** → QR capability  
**Honey Passport** → public verification view

The old product/version labels were removed from the integrated documentation and key runtime branding. Internal compatibility directories such as `src/lib/hc` were intentionally not renamed because they are implementation namespaces rather than product branding.

## Recommended remediation order

### P0 — Production security boundary

- tighten Supabase RLS write policies
- bind lab writes to organisation/batch scope
- review organisation/cluster read visibility
- keep all privileged writes server-mediated

### P1 — Authentication hardening

- move API bearer credentials away from localStorage
- add login rate limiting and exponential backoff
- shorten access-token lifetime
- introduce secure refresh-token rotation

### P2 — Operational hardening

- restrict blockchain retry by permission
- minimise public blockchain-health information
- move rate limiting to a shared production store
- use high-entropy public passport identifiers

### P3 — Continuous assurance

- run dependency vulnerability scans in CI
- add secret scanning to CI
- add negative authorization tests for every role/resource pair
- periodically review CORS, public endpoints and audit logs

## Audit limitation

This document is a source-code security audit, not a penetration test, threat-model workshop, cloud configuration audit or independent cryptographic review. Production infrastructure, Supabase dashboard policies, Render settings, AWS security groups and secret-manager configuration should be separately verified before any government-scale deployment.

**Security principle:** the browser is a user interface, not a trust boundary. The backend, database policies and provenance layer must independently enforce what can be written, by whom, and within which scope.
