-- HoneyChain v3 — Supabase production schema (idempotent).

create or replace function set_updated_at()
returns trigger as $$
begin new.updated_at = now(); return new; end; $$ language plpgsql;

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role text not null check (role in ('beekeeper','organization','lab','processor','admin','consumer')),
  organization_id uuid,
  madhukranti_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists profiles_set_updated_at on profiles;
create trigger profiles_set_updated_at before update on profiles for each row execute function set_updated_at();

create table if not exists clusters (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  district text,
  state text,
  institution_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists clusters_set_updated_at on clusters;
create trigger clusters_set_updated_at before update on clusters for each row execute function set_updated_at();

create table if not exists organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text not null check (type in ('KVIC','NBB','FPO','COOPERATIVE','COLLECTION_CENTER','PROCESSOR','LAB')),
  cluster_id uuid references clusters(id) on delete set null,
  location text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists organizations_set_updated_at on organizations;
create trigger organizations_set_updated_at before update on organizations for each row execute function set_updated_at();

alter table profiles
  drop constraint if exists profiles_organization_id_fk;
alter table profiles
  add constraint profiles_organization_id_fk
  foreign key (organization_id) references organizations(id) on delete set null;

create table if not exists beekeepers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade,
  organization_id uuid references organizations(id) on delete set null,
  name text not null,
  phone text,
  location text,
  madhukranti_id text,
  is_independent boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists beekeepers_set_updated_at on beekeepers;
create trigger beekeepers_set_updated_at before update on beekeepers for each row execute function set_updated_at();

create table if not exists hives (
  id uuid primary key default gen_random_uuid(),
  beekeeper_id uuid not null references beekeepers(id) on delete cascade,
  hive_code text not null,
  hive_type text,
  latitude numeric,
  longitude numeric,
  install_date date,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists hives_set_updated_at on hives;
create trigger hives_set_updated_at before update on hives for each row execute function set_updated_at();

create table if not exists hive_readings (
  id uuid primary key default gen_random_uuid(),
  hive_id uuid not null references hives(id) on delete cascade,
  recorded_at timestamptz not null,
  temperature numeric,
  humidity numeric,
  weight_kg numeric,
  source text not null check (source in ('manual','iot','simulation')),
  created_at timestamptz not null default now()
);

create table if not exists health_scores (
  id uuid primary key default gen_random_uuid(),
  hive_id uuid not null references hives(id) on delete cascade,
  created_at timestamptz not null default now(),
  score numeric not null,
  risk_level text not null check (risk_level in ('LOW','MEDIUM','HIGH')),
  factors jsonb,
  recommended_action text,
  model_version text
);

create table if not exists harvest_events (
  id uuid primary key default gen_random_uuid(),
  hive_id uuid references hives(id) on delete set null,
  beekeeper_id uuid not null references beekeepers(id) on delete cascade,
  harvested_at timestamptz not null,
  quantity_kg numeric not null,
  honey_type text,
  location text,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists batches (
  id uuid primary key default gen_random_uuid(),
  batch_code text unique not null,
  status text not null default 'created' check (status in ('created','processing','listed','archived')),
  honey_type text,
  quantity_kg numeric,
  beekeeper_id uuid references beekeepers(id) on delete set null,
  organization_id uuid references organizations(id) on delete set null,
  trust_tier text not null default 'self_declared' check (trust_tier in ('self_declared','organization_verified','lab_verified','blockchain_anchored')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists batches_set_updated_at on batches;
create trigger batches_set_updated_at before update on batches for each row execute function set_updated_at();

create table if not exists batch_harvest_links (
  batch_id uuid not null references batches(id) on delete cascade,
  harvest_event_id uuid not null references harvest_events(id) on delete cascade,
  quantity_kg numeric,
  primary key (batch_id, harvest_event_id)
);

create table if not exists batch_genealogy (
  id uuid primary key default gen_random_uuid(),
  parent_batch_id uuid not null references batches(id) on delete cascade,
  child_batch_id uuid not null references batches(id) on delete cascade,
  relationship_type text not null check (relationship_type in ('split','merge')),
  quantity_kg numeric,
  created_at timestamptz not null default now()
);

create table if not exists custody_events (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references batches(id) on delete cascade,
  actor_id uuid,
  actor_role text,
  event_type text not null check (event_type in ('HARVEST','COLLECTION','QUALITY_TEST','PROCESSING','PACKAGING','TRANSFER','DISTRIBUTION','SALE','CORRECTION')),
  timestamp timestamptz not null,
  location text,
  quantity_kg numeric,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create table if not exists lab_tests (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references batches(id) on delete cascade,
  lab_id uuid,
  result text not null check (result in ('PASS','FAIL','NEEDS_FURTHER_TESTING')),
  test_date date,
  verified_at timestamptz,
  report_path text,
  report_hash text,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create table if not exists blockchain_anchors (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references batches(id) on delete cascade,
  event_id uuid,
  data_hash text not null,
  transaction_hash text,
  network text,
  status text not null default 'pending' check (status in ('pending','confirmed','failed')),
  anchored_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists qr_codes (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references batches(id) on delete cascade,
  product_code text unique not null,
  passport_path text,
  created_at timestamptz not null default now()
);

create index if not exists idx_hive_readings_hive_id on hive_readings(hive_id);
create index if not exists idx_health_scores_hive_id on health_scores(hive_id);
create index if not exists idx_harvest_events_hive_id on harvest_events(hive_id);
create index if not exists idx_harvest_events_beekeeper_id on harvest_events(beekeeper_id);
create index if not exists idx_batches_beekeeper_id on batches(beekeeper_id);
create index if not exists idx_batches_organization_id on batches(organization_id);
create index if not exists idx_batch_harvest_links_batch_id on batch_harvest_links(batch_id);
create index if not exists idx_batch_genealogy_parent on batch_genealogy(parent_batch_id);
create index if not exists idx_batch_genealogy_child on batch_genealogy(child_batch_id);
create index if not exists idx_custody_events_batch_id on custody_events(batch_id);
create index if not exists idx_lab_tests_batch_id on lab_tests(batch_id);
create index if not exists idx_blockchain_anchors_batch_id on blockchain_anchors(batch_id);
create index if not exists idx_qr_codes_product_code on qr_codes(product_code);