# Architecture Decisions (ADRs)

Short ADRs for the significant choices. See docs/ASSUMPTIONS.md for the
decision list; THIS file records the concrete architectural contracts.

## ADR-001 — BlockchainGateway single boundary

**Status:** accepted.

**Context:** the old code had `BlockchainAdapter` (anchor/verify) plus a
simulated adapter and a Fabric placeholder that raised `NotImplementedError`.

**Decision:** one `BlockchainGateway` facade owns every ledger operation.
It delegates to exactly one `LedgerAdapter` subclass chosen by config:
`LocalLedgerAdapter` / `EVMBlockchainAdapter` / `FabricBlockchainAdapter`.
Transactions are tracked with an explicit state machine independent of the DB.

**Consequences:** swapping real infrastructure never touches the API layer;
honesty is centralized (no path can fake a confirmation).

## ADR-002 — Merkle root anchoring over per-item anchoring

**Status:** accepted.

**Context:** evidence bundles can contain many photos/GPS/notes.

**Decision:** the bundle builds a Merkle tree; only the root is anchored. A
per-item proof path allows verifying a single evidence byte against that root.

**Consequences:** O(1) anchors per bundle; per-item verification is O(log n)
proofs. Tampering any item changes the root → `evidence_intact: false`.

## ADR-003 — Offline event ledger preserves forks

**Status:** accepted.

**Context:** multiple devices can append to the same head while offline.

**Decision:** the ledger never deletes/merges a "losing" record. A divergent
append creates a fork marker and both branches persist (`chain_heads > 1`).

**Consequences:** no data loss; reconciliation logic must handle forks
(recorded, not hidden).

## ADR-004 — Trust-tier weakest-link merge

**Status:** accepted.

**Context:** merging batches could let someone launder low-trust honey.

**Decision:** a merged lot's `trust_tier` = weakest tier among sources;
`blockchain_anchored` requires evidence the source actually anchored.

**Consequences:** UI/UX must show the tier drop (or forbid the merge).

## ADR-005 — Certificates reference batches by `text`, not FK

**Status:** accepted.

**Context:** offline-first means certificate/evidence rows can arrive before
the referenced batch row syncs.

**Decision:** `certificates.batch_id` and `evidence_bundles.entity_ref` are
`text` columns validated at linking time, not by a DB foreign key.

**Consequences:** referential integrity is application-enforced on sync; DB
doesn't reject out-of-order inserts.

## ADR-006 — Tamper endpoints under DEMO_MODE toggle

**Status:** accepted.

**Context:** the demo must show tamper-evidence (corrupt an event → chain
detection).

**Decision:** `/api/v1/admin/tamper/*` requires `demo.tamper` permission AND
non-production `api_env`. Production returns 403 by construction.

**Consequences:** the demo remains credible; production cannot self-tamper.

## ADR-007 — `simulated` renamed to `local`

**Status:** accepted.

**Context:** "simulated blockchain" sounded like a fake success path.

**Decision:** the in-process ledger is `LocalLedgerAdapter`, reported as
`ledger_name = "local"` in every response.

**Consequences:** consumers never confuse dev ledger with real anchoring.

## ADR-008 — Honest status codes are returned, not exceptions

**Status:** accepted.

**Context:** external ledger absence is a routine state, not an exceptional
crash.

**Decision:** `LedgerNotConfigured` / `LedgerUnavailable` are caught by the
gateway and surfaced as `FABRIC_NOT_CONFIGURED`, `BLOCKCHAIN_NOT_CONFIGURED`,
`FABRIC_UNAVAILABLE` states with the transaction still visible in the tracker.

**Consequences:** dashboards can render the truth; unit tests can assert it.