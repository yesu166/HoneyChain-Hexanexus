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
`custody`, `labs`, `passport/{code}`, `sync`.

## Error model
`{"detail": "..."}` with standard HTTP codes. 403 for RBAC denial, 404 for
missing rows, 400 for rejected transition/validation, 429 for rate limit.

## Honesty contract
- `anchor.state` is `CONFIRMED` only when the local/EVM/Fabric adapter
  actually confirmed it.
- A Fabric/EVM response may carry `FABRIC_NOT_CONFIGURED` / `UNKNOWN` /
  `FAILED`; clients must render those verbatim rather than assume success.