-- Minimal reproducible demo data for development + consumer passport demos.
-- Idempotent: safe to re-run.
-- Creates a demo auth user so RLS-owned seed rows exist and the app can log in.

do $$
declare
  v_beekeeper uuid := '11111111-1111-4111-8111-111111111111';
  v_orgadmin uuid := '22222222-2222-4222-8222-222222222222';
begin
  if not exists (select 1 from auth.users where id = v_beekeeper) then
    insert into auth.users (
      instance_id, id, aud, role, email,
      encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token,
      email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', v_beekeeper, 'authenticated', 'authenticated',
      'demo@honeychain.in',
      crypt('HoneyChainDemo!1', gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      '', '', '', ''
    );
  end if;
  if not exists (select 1 from auth.users where id = v_orgadmin) then
    insert into auth.users (
      instance_id, id, aud, role, email,
      encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token,
      email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', v_orgadmin, 'authenticated', 'authenticated',
      'org@honeychain.in',
      crypt('HoneyChainDemo!1', gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      '', '', '', ''
    );
  end if;
end $$;

with cluster as (
  insert into clusters (id, name, district, state)
  values (gen_random_uuid(), 'Nilgiris Cluster', 'Nilgiris', 'Tamil Nadu')
  on conflict do nothing
  returning id
),
profile_beekeeper as (
  insert into profiles (id, full_name, phone, role, madhukranti_id)
  values ('11111111-1111-4111-8111-111111111111', 'Demo Beekeeper', '+910000000001', 'beekeeper', 'MK-DEMO-001')
  on conflict (id) do nothing
  returning id
),
profile_org as (
  insert into profiles (id, full_name, phone, role)
  values ('22222222-2222-4222-8222-222222222222', 'Demo FPO Admin', '+910000000002', 'organization')
  on conflict (id) do nothing
  returning id
),
org as (
  insert into organizations (id, name, type, cluster_id, location)
  select gen_random_uuid(), 'Nilgiris Honey FPO', 'FPO',
         (select id from cluster), 'Nilgiris, TN'
  where exists (select 1 from cluster)
  returning id
),
beekeeper as (
  insert into beekeepers (id, profile_id, organization_id, name, phone, location, is_independent)
  select gen_random_uuid(), '11111111-1111-4111-8111-111111111111',
         (select id from org), 'Kumar Beekeeper', '+910000000001', 'Nilgiris, TN', false
  where exists (select 1 from org)
  returning id
),
hive1 as (
  insert into hives (beekeeper_id, hive_code, hive_type, status)
  select (select id from beekeeper), 'HIVE-001', 'standard', 'active'
  where exists (select 1 from beekeeper)
  returning id
),
hive2 as (
  insert into hives (beekeeper_id, hive_code, hive_type, status)
  select (select id from beekeeper), 'HIVE-002', 'standard', 'active'
  where exists (select 1 from beekeeper)
  returning id
),
harvest1 as (
  insert into harvest_events (hive_id, beekeeper_id, harvested_at, quantity_kg, honey_type, location)
  select (select id from hive1), (select id from beekeeper), now() - interval '3 days',
         5.0, 'Wild Forest', 'Nilgiris, TN'
  where exists (select 1 from hive1)
  returning id
),
batch1 as (
  insert into batches (batch_code, status, honey_type, quantity_kg, beekeeper_id, organization_id, trust_tier)
  select 'HC-2026-DEMO-001', 'listed', 'Wild Forest', 5.0,
         (select id from beekeeper), (select id from org), 'lab_verified'
  where exists (select 1 from beekeeper)
  on conflict (batch_code) do nothing
  returning id
),
link1 as (
  insert into batch_harvest_links (batch_id, harvest_event_id, quantity_kg)
  select (select id from batch1), (select id from harvest1), 5.0
  where exists (select 1 from batch1)
  returning batch_id
),
custody1 as (
  insert into custody_events (batch_id, actor_id, actor_role, event_type, timestamp, location)
  select (select id from batch1), (select id from beekeeper), 'beekeeper', 'HARVEST',
         now() - interval '3 days', 'Nilgiris, TN'
  where exists (select 1 from batch1)
  returning id
),
custody2 as (
  insert into custody_events (batch_id, actor_id, actor_role, event_type, timestamp, location, metadata)
  select (select id from batch1), (select id from org), 'organization', 'COLLECTION',
         now() - interval '2 days', 'Nilgiris, TN', '{"source":"demo"}'::jsonb
  where exists (select 1 from batch1)
  returning id
),
lab1 as (
  insert into lab_tests (batch_id, lab_id, result, test_date, verified_at, metadata)
  select (select id from batch1), null, 'PASS', current_date - interval '1 day',
         now() - interval '1 day', '{"source":"demo"}'::jsonb
  where exists (select 1 from batch1)
  returning id
),
anchor1 as (
  insert into blockchain_anchors (batch_id, data_hash, network, status, anchored_at)
  select (select id from batch1), 'demo-data-hash-2026', 'simulated', 'confirmed',
         now() - interval '12 hours'
  where exists (select 1 from batch1)
  returning id
),
qr1 as (
  insert into qr_codes (batch_id, product_code, passport_path)
  select (select id from batch1), 'HC-2026-DEMO-001', '/trace/HC-2026-DEMO-001'
  where exists (select 1 from batch1)
  on conflict (product_code) do nothing
  returning id
)
select 'seed complete' as status;