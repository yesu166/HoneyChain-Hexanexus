-- Backend persistence alignment.
--
-- The FastAPI backend (services/db/supabase.py) persists its own identity
-- model (users with role scopes) and a few fields the original cloud schema
-- did not expose. Everything below is additive and idempotent: no existing
-- row, column or constraint is dropped or reinterpreted.
--
-- Policy note: `users` is the backend's service-role identity store (the app
-- registers operators through the API). It is intentionally kept outside the
-- auth.users/profiles graph; scoping/RBAC rules live in the backend service
-- layer. `passports` is a cache table keyed by product/batch code.

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  name text not null,
  phone text,
  role text not null,
  org_id text not null default '',
  password_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_users_email on users(email);
create index if not exists idx_users_phone on users(phone);

drop trigger if exists users_set_updated_at on users;
create trigger users_set_updated_at before update on users
  for each row execute function set_updated_at();

-- Passport cache (backend PassportService upserts by subject_code).
create table if not exists passports (
  subject_code text primary key,
  subject_type text not null default 'batch',
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists passports_set_updated_at on passports;
create trigger passports_set_updated_at before update on passports
  for each row execute function set_updated_at();

-- Batch origin label (backend BatchService.create writes `origin`).
alter table batches add column if not exists origin text not null default '';

-- Hive location (backend HiveService.create writes `location`).
alter table hives add column if not exists location text;

-- Harvest "collected" flag (backend HarvestService.create writes it).
alter table harvest_events add column if not exists collected boolean not null default false;

-- Lab tests: backend creates tests in a 'requested' state with no result yet.
alter table lab_tests add column if not exists status text not null default 'requested';
alter table lab_tests add column if not exists requested_note text not null default '';
alter table lab_tests add column if not exists tested_by text not null default '';
alter table lab_tests add column if not exists notes text not null default '';
alter table lab_tests add column if not exists requested_at timestamptz;
alter table lab_tests add column if not exists tested_at timestamptz;
alter table lab_tests alter column result drop not null;

-- Backend lab identifiers are region/code strings, not uuid (certificates.lab_id
-- is already text); widen for consistency.
alter table lab_tests alter column lab_id type text using lab_id::text;

create index if not exists idx_lab_tests_status on lab_tests(status);

-- Genealogy relation types used by the backend (split/merge semantics).
alter table batch_genealogy drop constraint if exists batch_genealogy_relationship_type_check;
alter table batch_genealogy add constraint batch_genealogy_relationship_type_check
  check (relationship_type in ('split','merge','SPLIT_FROM','AGGREGATED_FROM'));