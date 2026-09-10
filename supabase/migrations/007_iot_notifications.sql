-- IoT device registry, telemetry ingestion, derived notifications.
--
-- IoT devices authenticate by ECDSA signature (server-side ingest via the
-- service role). RLS below only guards browser/anon reads: admins see all,
-- beekeepers see their own hives/organizations, other roles see their org.
-- All statements are idempotent.
--
-- NOTE: device private keys are stored only so the *in-app simulator* can sign
-- events. Physical devices hold their own keys and never expose them here.

-- IoT devices ----------------------------------------------------------------
create table if not exists iot_devices (
  device_id text primary key,
  device_name text not null,
  device_type text not null default 'hive-sensor',
  firmware_version text not null default '1.0.0',
  device_status text not null default 'ONLINE'
    check (device_status in ('ONLINE','OFFLINE','SYNCING','ERROR','DISABLED')),
  assigned_hive_id text,
  assigned_apiary_id text,
  organization_id text not null default '',
  device_public_key_pem text not null,
  device_private_key_pem text not null default '',
  created_at text not null,
  sequence integer not null default 0,
  event_count integer not null default 0,
  battery_percent double precision,
  signal_strength double precision,
  mode text not null default 'STOPPED',
  is_simulated boolean not null default true,
  interval_seconds integer not null default 300,
  configuration jsonb not null default '{}'
);

create index if not exists idx_iot_devices_org on iot_devices(organization_id);
create index if not exists idx_iot_devices_hive on iot_devices(assigned_hive_id);

-- Telemetry events (append-only; duplicates rejected by the backend) ----------
create table if not exists telemetry_events (
  event_id text primary key,
  device_id text not null,
  sequence integer not null,
  timestamp timestamptz not null,
  payload jsonb not null default '{}',
  payload_hash text not null,
  previous_event_hash text not null default '',
  signature text not null default '',
  hive_id text,
  organization_id text not null default '',
  is_simulated boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists idx_telemetry_device_seq on telemetry_events(device_id, sequence desc);
create index if not exists idx_telemetry_hive on telemetry_events(hive_id, timestamp desc);
create unique index if not exists uq_telemetry_device_sequence
  on telemetry_events(device_id, sequence);

-- Notifications / alerts (derived state, never client-invented) --------------
create table if not exists notifications (
  notification_id text primary key,
  title text not null,
  body text not null,
  category text not null default 'telemetry',
  severity text not null default 'info',
  reason text not null default '',
  recommended_action text not null default '',
  source text not null default 'iot',
  hive_id text,
  batch_id text,
  device_id text,
  organization_id text not null default '',
  is_simulated boolean not null default true,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_org on notifications(organization_id, created_at desc);
create index if not exists idx_notifications_hive on notifications(hive_id, created_at desc);

-- RLS ------------------------------------------------------------------------
alter table iot_devices enable row level security;
drop policy if exists iot_devices_select_org on iot_devices;
create policy iot_devices_select_org on iot_devices for select using (
  organization_id = public.auth_user_org_id()::text
  or public.auth_user_role() in ('admin','institution')
  or assigned_hive_id in (
    select id::text from public.hives
    where beekeeper_id in (
      select id from public.beekeepers where organization_id = public.auth_user_org_id()
    )
  )
);

alter table telemetry_events enable row level security;
drop policy if exists telemetry_events_select_scoped on telemetry_events;
create policy telemetry_events_select_scoped on telemetry_events for select using (
  organization_id = public.auth_user_org_id()::text
  or public.auth_user_role() in ('admin','institution')
  or hive_id in (
    select id::text from public.hives
    where beekeeper_id in (
      select id from public.beekeepers where organization_id = public.auth_user_org_id()
    )
  )
);

alter table notifications enable row level security;
drop policy if exists notifications_select_scoped on notifications;
create policy notifications_select_scoped on notifications for select using (
  organization_id = public.auth_user_org_id()::text
  or public.auth_user_role() in ('admin','institution')
  or hive_id in (
    select id::text from public.hives
    where beekeeper_id in (
      select id from public.beekeepers where organization_id = public.auth_user_org_id()
    )
  )
);