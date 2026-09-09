-- Evidence bundles, offline event ledger, lab certificates.
--
-- Offline-first ordering: evidence and certificates may arrive before the
-- referenced batch row has synced, so entity_ref / batch_id are plain `text`
-- references (no FK) — the backend validates scope when the batch is created.
-- All statements are idempotent (drop-if-exists + create-if-not-exists).

-- Evidence bundles -----------------------------------------------------------
create table if not exists evidence_bundles (
  bundle_id text primary key,
  entity_type text not null check (entity_type in ('harvest','batch')),
  entity_ref text not null,
  operator text,
  device_id text,
  created_at timestamptz not null default now(),
  leaf_count integer not null default 0,
  root_hash text not null,
  evidence jsonb not null default '[]',
  anchor jsonb not null default '{}'
);

create index if not exists idx_evidence_bundles_entity
  on evidence_bundles(entity_type, entity_ref);

-- Offline event ledger (append-only hash chain) ------------------------------
create table if not exists ledger_events (
  id uuid primary key default gen_random_uuid(),
  chain_id text not null,
  index integer not null,
  event_type text not null,
  entity_ref text not null default '',
  payload jsonb not null default '{}',
  prev_hash text not null default '',
  hash text not null default '',
  ts timestamptz not null default now(),
  device_id text not null default '',
  fork_of text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists idx_ledger_events_chain on ledger_events(chain_id, index);
-- A hash is unique within its chain unless it is a fork marker (empty hash).
create unique index if not exists uq_ledger_events_chain_hash
  on ledger_events(chain_id, hash) where hash <> '';

-- Lab certificates ------------------------------------------------------------
create table if not exists certificates (
  certificate_id text primary key,
  batch_id text not null,
  lab_id text not null,
  certificate_type text not null default 'analysis',
  issued_at timestamptz not null default now(),
  valid_until timestamptz,
  content_hash text not null,
  issuer_name text not null default '',
  status text not null default 'active' check (status in ('active','revoked')),
  revoked_at timestamptz,
  revocation_reason text not null default '',
  anchor jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists certificates_set_updated_at on certificates;
create trigger certificates_set_updated_at before update on certificates
  for each row execute function set_updated_at();

create index if not exists idx_certificates_batch on certificates(batch_id);
create index if not exists idx_certificates_status on certificates(status);

-- RLS ------------------------------------------------------------------------
alter table evidence_bundles enable row level security;
drop policy if exists evidence_bundles_select_own on evidence_bundles;
create policy evidence_bundles_select_own on evidence_bundles for select using (
  entity_ref::uuid in (
    select id from public.batches
    where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid())
       or organization_id = public.auth_user_org_id()
  )
);

alter table ledger_events enable row level security;
drop policy if exists ledger_events_select_org on ledger_events;
create policy ledger_events_select_org on ledger_events for select to authenticated using (true);

alter table certificates enable row level security;
drop policy if exists certificates_select_org on certificates;
drop policy if exists certificates_insert_lab on certificates;
drop policy if exists certificates_update_lab on certificates;
create policy certificates_select_org on certificates for select using (
  batch_id::uuid in (
    select id from public.batches
    where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid())
       or organization_id = public.auth_user_org_id()
  )
);
create policy certificates_insert_lab on certificates for insert to authenticated
  with check (public.auth_user_role() = 'lab');
create policy certificates_update_lab on certificates for update to authenticated
  using (public.auth_user_role() = 'lab');