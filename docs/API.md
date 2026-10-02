# API (HTTP)

Base: `/api/v1`. Auth: `Authorization: Bearer <jwt>`. Health endpoints also
expose `/health/*`.

## Health
- `GET /health` — liveness + DB status
- `GET /health/live`
- `GET /health/ready`

## Evidence
- `POST /evidence/bundles` — create HEB `{entity_type, entity_ref, operator,
  device_id, anchor, evidence:[{kind, value, captured_at, latitude, longitude,
  content_hash}]}` → bundle incl. `root_hash`, `anchor.state`
- `GET /evidence/bundles/{bundle_id}`
- `POST /evidence/bundles/{bundle_id}/verify` → `{evidence_intact,
  anchor_state, anchored, recomputed_root}`
- `POST /evidence/proof/{bundle_id}/{evidence_id}` → per-item Merkle proof
- `POST /evidence/verify-proof` `{leaf_hash, root_hash, proof:[{hash, side}]}`

## Certificates
- `POST /certificates/issue` (lab/admin)
- `POST /certificates/{id}/revoke` `{reason}` (lab/admin)
- `GET /certificates/verify/{id}` → `{verified, status, reasons}`
- `GET /batches/{batch_id}/certificates`

## Lineage / batch state
- `POST /batches/transition` `{batch_id, to_state, note}` (fpo/processor/admin)
- `GET /batches/{id}/state` → `{status, trust_tier, holder}`
- `GET /batches/{id}/lineage` → `{genealogy, ledger:{integrity_ok,...}}`
- `GET /batches/{id}/provenance` → aggregated material + operational provenance
  `{batch, harvest_sources, hive_sources, relations, custody, lab_tests,
  certificates, anchor, mass_balance:{batch_quantity_kg, allocated_kg,
  unallocated_kg, balanced}, timeline, genealogy}`. Aggregates records that
  already exist — a missing stage stays missing.

## Laboratory workflow
- `POST /batches/{batch_id}/lab-test` (fpo/admin) → creates a test in
  `requested` and emits `LAB_REQUESTED`
- `GET /batches/{batch_id}/lab-tests` → tests on one batch
- `GET /labs/{lab_id}/queue` (lab/admin/institution, lab limited to its own org)
- `GET /labs` (fpo/lab/admin/institution/processor) → real laboratory directory
  (`{id, organization_key, name, type, state, district, status}[]`) for the
  test-request selector. Driven by organization rows, never a hardcoded list.
- `POST /labs/tests/{test_id}/start` (lab, own tests only) → `requested` to
  `in_progress`, emits `LAB_STARTED`
- `POST /labs/tests/{test_id}/result` `{result: PASS|FAIL, tested_by?, notes?}`
  (lab, own tests only) → final state, emits `LAB_PASS` / `LAB_FAIL`

## Market linkage (FPO Market Linkage + Buyer Procurement)

Capabilities of the FPO and Buyer surfaces — there is no "Market Linkage"
portal, and none may be added.

- `GET /market/listings[?status=]` → listings visible to the caller (a buyer
  sees open lots from other organizations; a seller sees its own)
- `POST /market/listings` `{batch_id, quantity_kg, price_per_kg, notes?}`
  (fpo/processor/admin) → emits `MARKET_LISTED`. The seller is taken from the
  batch's `organization_id`, never from the request body. A batch that has not
  passed the laboratory may not be listed (400), and a batch outside the
  caller's scope is 404 rather than 403.
- `POST /market/listings/{id}/withdraw` (selling organization only)
- `GET /market/marketplace` → `{listings, orders}` in one call (Buyer surface)
- `GET /market/orders` → the caller's purchases, or the requests on its listings
- `POST /market/orders` `{listing_id, quantity_kg}` (buyer/admin) →
  emits `BUYER_REQUESTED` to the SELLER
- `POST /market/orders/{id}/decide` `{accept, seller_notes?}` (selling org) →
  decrements `remaining_kg` on acceptance, emits `BUYER_ACCEPTED` to the buyer.
  Accepting more kilograms than remain is 409, and the stock is left untouched.
- `POST /market/orders/{id}/fulfil` → writes a real `SALE` custody event on the
  batch through `CustodyService` (anchored when a gateway is configured), then
  marks the order `FULFILLED`. Only an `ACCEPTED` order can be fulfilled.
- `POST /market/orders/{id}/cancel` → a `REQUESTED` order only. An accepted
  order is committed stock and must be declined by the seller instead.

## QR package identity and reuse detection

- `GET /qr/packages[?batch_id=]` (fpo/processor/admin)
- `POST /qr/packages` `{batch_id, quantity_kg, package_code?}` → the issuer is
  the batch's owning organization. An explicitly supplied `package_code` that
  already exists resolves to the package that already owns that identity, which
  is what makes a duplicated print detectable rather than producing two
  indistinguishable packages.
- `POST /qr/packages/{code}/recall` (issuing organization only)
- `POST /qr/scan` `{package_code}` (any authenticated role) → always persists a
  `qr_scans` row, including for a code that was never issued. Returns
  `{package, result: CLEAR|SUSPICIOUS, signals[], prior_scan_count, scan}`.
  Signals are computed from recorded rows only: `UNKNOWN_CODE`,
  `DUPLICATE_PRINT`, `REUSE_BY_OTHER_ORG`, `EXCESSIVE_SCANS`, `RECALLED`. A
  clean first scan carries no signals — the detector never manufactures a
  suspicion. Flagged scans emit `QR_SUSPICIOUS` to the issuing organization.
- `GET /qr/scans` and `GET /qr/packages/{code}/scans` → the recorded history

The public consumer surface remains `GET /passport/{code}`; `/qr/scan` is
authenticated so an anonymous caller cannot flood the scan ledger.

## Ledger / provenance anchoring

`BLOCKCHAIN_ADAPTER` selects the ledger:

- `local` (aliases `simulated`, `memory`) — in-process development/test ledger.
  **Refused in production.**
- `remote_fabric` (aliases `fabric_bridge`, `fabric_remote`) — the real
  Hyperledger Fabric network, reached through the Fabric bridge on EC2. This is
  the production setting.
- `fabric` — direct Fabric gateway client.
- `evm` — EVM chain via `BLOCKCHAIN_RPC_URL`.

### Production fails closed

Production **must** run `remote_fabric`. If `BLOCKCHAIN_ADAPTER` names the local
ledger, names an unknown adapter, or selects `remote_fabric` without
`FABRIC_BRIDGE_URL` / `FABRIC_BRIDGE_TOKEN` / `FABRIC_CHANNEL` /
`FABRIC_CHAINCODE`, startup raises rather than falling back:

```
BLOCKCHAIN_ADAPTER is the local in-process ledger, which is a
development/test device and must never be the production ledger...
```

There is no silent fallback. This is deliberate: a local ledger holds
commitments in memory, so a public host serving it would report provenance
anchors that exist in no chain while labelling them as if they did — the same
failure mode `build_repository` already prevents by requiring Supabase.

When the bridge is configured but unreachable, the adapter reports
`FABRIC_UNAVAILABLE` with the transport cause. It does **not** degrade to local.

The adapter identity is exposed through `GET /blockchain/status` as `ledger`
(`fabric`, `evm`, or `local`) and through the health endpoint, and the portal
maps this to `FABRIC` / `EVM` / `LOCAL` — the UI never labels local state as
Fabric.

## Live QR package identity

A printed label carries a structured package identity, derived from the batch's
own record (e.g. `HC-TN-NLG-001-J0001`: HoneyChain prefix, origin initials,
batch sequence, package sequence). Uniqueness is enforced by a unique index.

- `POST /qr/packages` returns `passport_path`, the live public route this label
  should encode.
- `GET /api/v1/passport/package/{package_code}` — public, unauthenticated,
  PII-free, rate limited. Resolves the package identity to its batch and builds
  the **current** passport, so a consumer scanning a jar always reads live
  provenance rather than a static copy. An unissued code is a 404.

Reuse detection is based on persisted package/scan records only: the first scan
by one organization is `CLEAR`; a later scan by a different organization is
flagged `REUSE_BY_OTHER_ORG`; a re-printed code is `DUPLICATE_PRINT`; a code the
platform never issued is `UNKNOWN_CODE`; a recalled label is `RECALLED`.

## Mobile processing van (KVIC Field Officer)

A submodule of the KVIC Field Officer surface — there is no "Mobile Processing
Van" portal. Requires `institution` or `admin`.

- `GET /van/dashboard` → `{visits, counts}`
- `GET /van/visits[?status=]` / `GET /van/visits/{id}`
- `POST /van/visits` `{van_code, target_name?, notes?}` → emits
  `VAN_VISIT_SCHEDULED`
- `POST /van/visits/{id}/advance` → the next state only
  (`SCHEDULED → ARRIVED → SAMPLE_COLLECTED → COMPLETED`); skipping a step is 409
- `POST /van/visits/{id}/samples` `{batch_id, sample_code, quantity_kg?}` →
  requires the van to be on site (409 otherwise), requires a batch that exists,
  and advances the visit because a sample genuinely exists. Emits
  `VAN_SAMPLE_RECEIVED`
- `POST /van/samples/{id}/result` `{result: PASS|FAIL, notes?}` → emits
  `VAN_TEST_COMPLETED`. A van result is a FIELD OBSERVATION: it never changes a
  batch's `trust_tier`, and the response carries
  `is_laboratory_certificate: false` plus the unchanged tier so no caller can
  mistake one for the other.

## Notifications
- `GET /notifications` → `{items, unread_count}`, scoped by role
- `POST /notifications/{notification_id}/read`
- `POST /notifications/stale-check` (device staleness sweep)

Rows with `source: "workflow"` are emitted from the SAME write that changed
state, so an inbox can never advertise a step the database did not record.
`category` is one of `HARVEST_CREATED`, `COLLECTION_ACCEPTED`, `BATCH_CREATED`,
`LAB_REQUESTED`, `LAB_STARTED`, `LAB_PASS`, `LAB_FAIL`, `PROCESSING_STARTED`,
`PACKAGED`, `CUSTODY_TRANSFER`, `CUSTODY_RECEIVED`, `MARKET_LISTED`,
`BUYER_REQUESTED`, `BUYER_ACCEPTED`, `HIGH_RISK_HIVE`, `VAN_VISIT_SCHEDULED`,
`VAN_SAMPLE_RECEIVED`, `VAN_TEST_COMPLETED`, `QR_SUSPICIOUS`.

## Blockchain
- `GET /blockchain/status` → `{ledger, transactions:[...]}`
- `GET /blockchain/transactions/{tx_ref}`
- `POST /blockchain/transactions/{tx_ref}/retry`

## Admin/demo
- `POST /admin/tamper/ledger/{chain_id}/{index}` (admin + non-prod) — corrupt
  an event; returns chain verification
- `POST /admin/tamper/evidence/{bundle_id}` (admin + non-prod)

## Legacy (still live)
`auth`, `hives`, `harvests`, `batches` (+ split/merge/genealogy),
`custody`, `passport/{code}`, `sync`.

## Error model
`{"detail": "..."}` with standard HTTP codes. 403 for RBAC denial, 404 for
missing rows, 400 for rejected transition/validation, 429 for rate limit.

A request that is well formed but conflicts with current state is 409 (more
kilograms requested than remain, an order already decided, a van not yet on
site). A batch outside the caller's scope is 404, not 403: a 403 would confirm
the record exists.

## Honesty contract
- `anchor.state` is `CONFIRMED` only when the local/EVM/Fabric adapter
  actually confirmed it.
- A Fabric/EVM response may carry `FABRIC_NOT_CONFIGURED` / `UNKNOWN` /
  `FAILED`; clients must render those verbatim rather than assume success.