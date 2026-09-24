-- Ask My Bee — inspection & treatment records.
--
-- The Gemini assistant records what a beekeeper observed (inspections) and
-- what they applied (treatments) through the validated tool registry. Both are
-- scoped to beekeepers + hives like harvest_events; every row belongs to the
-- beekeeper who performed it.

create table if not exists hive_inspections (
  id uuid primary key default gen_random_uuid(),
  hive_id uuid not null references hives(id) on delete cascade,
  beekeeper_id uuid not null references beekeepers(id) on delete cascade,
  inspected_at timestamptz not null default now(),
  activity_level text,
  queen_seen boolean,
  brood_seen boolean,
  food_stores text,
  pests_seen text,
  dead_bees_seen boolean,
  hive_condition text,
  observations text,
  client_id text,
  created_at timestamptz not null default now()
);

create unique index if not exists idx_hive_inspections_client_id
  on hive_inspections(client_id) where client_id is not null;
create index if not exists idx_hive_inspections_hive_id
  on hive_inspections(hive_id);
create index if not exists idx_hive_inspections_beekeeper_id
  on hive_inspections(beekeeper_id);

create table if not exists hive_treatments (
  id uuid primary key default gen_random_uuid(),
  hive_id uuid not null references hives(id) on delete cascade,
  beekeeper_id uuid not null references beekeepers(id) on delete cascade,
  treated_at timestamptz not null default now(),
  treatment_name text not null,
  active_ingredient text,
  dosage text,
  observation text,
  status text not null default 'applied',
  client_id text,
  created_at timestamptz not null default now()
);

create unique index if not exists idx_hive_treatments_client_id
  on hive_treatments(client_id) where client_id is not null;
create index if not exists idx_hive_treatments_hive_id
  on hive_treatments(hive_id);
create index if not exists idx_hive_treatments_beekeeper_id
  on hive_treatments(beekeeper_id);