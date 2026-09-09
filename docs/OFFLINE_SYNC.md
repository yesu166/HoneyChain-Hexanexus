# Offline-first Sync Model

The mobile app writes locally first; the backend accepts idempotent pushes.

## Why it's safe

- Every synchronous mutation carries a stable `client_id`.
- `find_by_client_id(table, client_id)` returns the already-stored row for a
  retried push → no duplicates.
- The hash-chained **event ledger** (see `EventLedger`) is append-only with
  fork preservation: two devices editing offline can both record; neither
  record is silently discarded.

## Entities synced

`hive`, `harvest`, `batch`, `reading`, `custody` are handled by the existing
`SyncService`. New this session:
- **evidence bundles** arrive via `/evidence/bundles` (offline-first, so the
  batch row may not exist yet).
- **ledger events** append through `EventLedger` (records the same facts the
  DB stores, plus hash-chain integrity).
- **certificates** issue/revoke via `/certificates/*`.

## Conflict handling (fork example)

Device A and Device B are offline with chain head `H`.

1. A appends `eA` (prev `H`).
2. B appends `eB` (prev `H`).
3. When B syncs, the ledger sees a sibling with the same `prev_hash` and
   creates a `fork` marker; both `eA` and `eB` survive as two chain heads.

The UI/API exposes both heads; reconciliation is explicit and recorded, never
a silent "last-writer-wins".

## Ordering

- Evidence/certs before batch row: allowed (text reference, validated on
  batch creation/linking).
- Nano-second timestamps + `index` keep a deterministic sort for chain
  verification.

## Sync statuses

`accepted: true | false` per item; errors are returned per entity so one bad
item never kills the batch. `pull` returns `hive/harvest/batch` in dependency
order so the client can materialize the graph.