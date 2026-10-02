-- Market linkage, package identity, and mobile processing van.
--
-- These three tables are the persistence behind capabilities that live INSIDE
-- existing surfaces rather than as portals of their own:
--
--   market_listings / purchase_orders -> FPO Market Linkage + Buyer Procurement
--   packages / qr_scans                -> QR package identity & reuse detection
--   van_visits / van_samples          -> KVIC Field Officer mobile processing van
--
-- Every row here is a real transaction. Nothing is derived on read except the
-- reuse signals, which are computed by QrService from these persisted rows.

-- ---------------------------------------------------------------------------
-- Market linkage
-- ---------------------------------------------------------------------------
create table if not exists market_listings (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references batches(id) on delete cascade,
  seller_org_id text not null,
  quantity_kg numeric(12,3) not null check (quantity_kg > 0),
  -- Remaining quantity. Listing decrements as orders are accepted, so a buyer can
  -- never request kilograms the seller has already committed.
  remaining_kg numeric(12,3) not null check (remaining_kg >= 0),
  price_per_kg numeric(12,2) not null check (price_per_kg > 0),
  currency text not null default 'INR',
  -- OPEN | RESERVED | SOLD | WITHDRAWN
  status text not null default 'OPEN',
  notes text,
  listed_at timestamptz not null default now(),
  closed_at timestamptz,
  client_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_market_listings_batch_id on market_listings(batch_id);
create index if not exists idx_market_listings_seller_org on market_listings(seller_org_id);
create index if not exists idx_market_listings_status on market_listings(status);
create unique index if not exists idx_market_listings_client_id
  on market_listings(client_id) where client_id is not null;

create table if not exists purchase_orders (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references market_listings(id) on delete cascade,
  batch_id uuid not null references batches(id) on delete cascade,
  buyer_org_id text not null,
  buyer_user_id text not null,
  quantity_kg numeric(12,3) not null check (quantity_kg > 0),
  price_per_kg numeric(12,2) not null check (price_per_kg > 0),
  -- Persisted, not recomputed on read, so a price change can never retroactively
  -- alter what a buyer agreed to pay.
  total_amount numeric(14,2) not null,
  currency text not null default 'INR',
  -- REQUESTED | ACCEPTED | REJECTED | FULFILLED | CANCELLED
  status text not null default 'REQUESTED',
  buyer_notes text,
  seller_notes text,
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by text,
  fulfilled_at timestamptz,
  client_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_purchase_orders_listing_id on purchase_orders(listing_id);
create index if not exists idx_purchase_orders_buyer_org on purchase_orders(buyer_org_id);
create index if not exists idx_purchase_orders_status on purchase_orders(status);
create unique index if not exists idx_purchase_orders_client_id
  on purchase_orders(client_id) where client_id is not null;

-- ---------------------------------------------------------------------------
-- QR package identity and reuse detection
-- ---------------------------------------------------------------------------
create table if not exists packages (
  id uuid primary key default gen_random_uuid(),
  -- The printed code. Unique: two packages may never share an identity, which is
  -- exactly what makes a duplicated print detectable rather than ambiguous.
  package_code text not null unique,
  batch_id uuid not null references batches(id) on delete cascade,
  organization_id text not null,
  quantity_kg numeric(12,3) not null check (quantity_kg > 0),
  -- ACTIVE | SCANNED | RECALLED
  status text not null default 'ACTIVE',
  -- First successful scan. A second scan from a different organization is then a
  -- reuse signal rather than an unknown state.
  first_scan_org text,
  first_scan_at timestamptz,
  scan_count integer not null default 0,
  issued_at timestamptz not null default now(),
  client_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_packages_batch_id on packages(batch_id);
create index if not exists idx_packages_org on packages(organization_id);
create unique index if not exists idx_packages_client_id
  on packages(client_id) where client_id is not null;

create table if not exists qr_scans (
  id uuid primary key default gen_random_uuid(),
  package_code text not null,
  batch_id uuid,
  scanner_user_id text not null,
  scanner_role text,
  organization_id text,
  -- CLEAR | SUSPICIOUS
  result text not null default 'CLEAR',
  -- JSON array of the signals that produced [result]. Persisted so an auditor
  -- sees WHY a scan was flagged, and the detector is explainable after the fact.
  signals jsonb not null default '[]'::jsonb,
  scanned_at timestamptz not null default now()
);

create index if not exists idx_qr_scans_package_code on qr_scans(package_code);
create index if not exists idx_qr_scans_scanned_at on qr_scans(scanned_at desc);
create index if not exists idx_qr_scans_result on qr_scans(result);
-- ---------------------------------------------------------------------------
-- Mobile processing van (KVIC Field Officer)
-- ---------------------------------------------------------------------------
create table if not exists van_visits (
  id uuid primary key default gen_random_uuid(),
  van_code text not null,
  officer_user_id text not null,
  organization_id text not null,
  -- The FPO / apiary the van is visiting.
  target_org_id text,
  target_name text,
  -- SCHEDULED | ARRIVED | SAMPLE_COLLECTED | COMPLETED | CANCELLED
  status text not null default 'SCHEDULED',
  scheduled_for timestamptz not null default now(),
  arrived_at timestamptz,
  completed_at timestamptz,
  notes text,
  client_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_van_visits_officer on van_visits(officer_user_id);
create index if not exists idx_van_visits_org on van_visits(organization_id);
create index if not exists idx_van_visits_status on van_visits(status);
create unique index if not exists idx_van_visits_client_id
  on van_visits(client_id) where client_id is not null;

create table if not exists van_samples (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null references van_visits(id) on delete cascade,
  batch_id uuid references batches(id) on delete set null,
  sample_code text not null,
  quantity_kg numeric(12,3) check (quantity_kg > 0),
  -- PENDING | PASS | FAIL
  result text not null default 'PENDING',
  moisture_percent numeric(5,2),
  notes text,
  collected_at timestamptz not null default now(),
  client_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_van_samples_visit_id on van_samples(visit_id);
create unique index if not exists idx_van_samples_sample_code on van_samples(sample_code);
create unique index if not exists idx_van_samples_client_id
  on van_samples(client_id) where client_id is not null;