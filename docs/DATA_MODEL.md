# Data Model

Schema lives in `supabase/migrations/` (001–006, applied to the live project).
The backend repository abstracts storage; both `InMemoryRepository` and
`SupabaseRepository` implement the same contract.

## Core entities

- **profiles / orgs / clusters / beekeepers** — identity graph (001).
- **hives + hive_readings + health_scores** — Hive Intelligence source data.
- **harvest_events** — raw harvest capture.
- **batches + batch_harvest_links + batch_genealogy** — lot model with
  explicit lineage (split/merge).
- **custody_events** — supply-chain movement (explicit event labels).
- **lab_tests** — QC requests/results (PASS/FAIL).
- **blockchain_anchors** — recorded anchors (tx hash, status).
- **qr_codes + passports** — public consumer view.

## Added this session (migration 006)

### evidence_bundles
| column | type | note |
|---|---|---|
| bundle_id | text PK | server generated |
| entity_type | text | `harvest` | `batch` |
| entity_ref | text | offline-first (no FK) |
| operator / device_id | text | attribution |
| created_at | timestamptz | |
| leaf_count | int | number of evidence objects |
| root_hash | text | the Merkle root that gets anchored |
| evidence | jsonb | normalized objects incl. their `content_hash` |
| anchor | jsonb | gateway transaction snapshot |

### ledger_events
| column | type | note |
|---|---|---|
| id | uuid PK | |
| chain_id / index | text/int | logical position |
| event_type / entity_ref | text | e.g. `batch_state_transition` |
| payload | jsonb | event content (never PII intentionally) |
| prev_hash / hash | text | hash chain links |
| ts / device_id | timestamptz/text | |
| fork_of | text | set on divergent (fork) events |

Unique partial index `uq_ledger_events_chain_hash` on `(chain_id, hash)`
where `hash <> ''` prevents duplicate replay while allowing fork markers.

### certificates
| column | type | note |
|---|---|---|
| certificate_id | text PK | |
| batch_id | text | offline-first (no FK) |
| lab_id | text | issuing org |
| certificate_type | text | `analysis`, `organic`, … |
| content_hash | text | canonical SHA-256 of certificate content |
| status | text | `active` | `revoked` |
| revoked_at / revocation_reason | timestamptz/text | |
| anchor | jsonb | issuing anchor snapshot |

## Conventions

- Timestamps: `timestamptz` (now()`).
- IDs: uuid (DB) or text (client-generated bundle/certificate ids).
- Sensitive/raw media are never primary entities: only `content_hash` +
  optional metadata are stored. Real photo bytes belong to object storage
  (TODO with customer).
- `updated_at` maintained via `set_updated_at()` trigger.