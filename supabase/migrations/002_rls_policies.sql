-- Row Level Security — idempotent (drop + recreate).

create or replace function public.auth_user_org_id()
returns uuid language sql security definer stable as $$
  select organization_id from public.profiles where id = auth.uid() limit 1;
$$;

create or replace function public.auth_user_role()
returns text language sql security definer stable as $$
  select role from public.profiles where id = auth.uid() limit 1;
$$;

-- profiles
alter table profiles enable row level security;
drop policy if exists profiles_select_own on profiles;
drop policy if exists profiles_update_own on profiles;
drop policy if exists profiles_insert_own on profiles;
drop policy if exists profiles_select_org on profiles;
create policy profiles_select_own on profiles for select using (id = auth.uid());
create policy profiles_update_own on profiles for update using (id = auth.uid());
create policy profiles_insert_own on profiles for insert with check (id = auth.uid());
create policy profiles_select_org on profiles for select using (organization_id is not null and organization_id = public.auth_user_org_id());

-- clusters
alter table clusters enable row level security;
drop policy if exists clusters_select_auth on clusters;
create policy clusters_select_auth on clusters for select to authenticated using (true);

-- organizations
alter table organizations enable row level security;
drop policy if exists organizations_select_auth on organizations;
drop policy if exists organizations_insert_admin on organizations;
create policy organizations_select_auth on organizations for select to authenticated using (true);
create policy organizations_insert_admin on organizations for insert to authenticated with check (public.auth_user_role() in ('admin','processor','lab'));

-- beekeepers
alter table beekeepers enable row level security;
drop policy if exists beekeepers_select_own on beekeepers;
drop policy if exists beekeepers_insert_own on beekeepers;
drop policy if exists beekeepers_select_org on beekeepers;
drop policy if exists beekeepers_update_org on beekeepers;
create policy beekeepers_select_own on beekeepers for select using (profile_id = auth.uid());
create policy beekeepers_insert_own on beekeepers for insert with check (profile_id = auth.uid());
create policy beekeepers_select_org on beekeepers for select using (organization_id is not null and organization_id = public.auth_user_org_id());
create policy beekeepers_update_org on beekeepers for update using (organization_id is not null and organization_id = public.auth_user_org_id());

-- hives
alter table hives enable row level security;
drop policy if exists hives_select_own on hives;
drop policy if exists hives_insert_own on hives;
drop policy if exists hives_update_own on hives;
drop policy if exists hives_select_org on hives;
create policy hives_select_own on hives for select using (beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()));
create policy hives_insert_own on hives for insert with check (beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()));
create policy hives_update_own on hives for update using (beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()));
create policy hives_select_org on hives for select using (beekeeper_id in (select id from public.beekeepers where organization_id is not null and organization_id = public.auth_user_org_id()));

-- hive_readings
alter table hive_readings enable row level security;
drop policy if exists hive_readings_select_own on hive_readings;
drop policy if exists hive_readings_insert_own on hive_readings;
drop policy if exists hive_readings_select_org on hive_readings;
create policy hive_readings_select_own on hive_readings for select using (hive_id in (select h.id from public.hives h join public.beekeepers b on h.beekeeper_id = b.id where b.profile_id = auth.uid()));
create policy hive_readings_insert_own on hive_readings for insert with check (hive_id in (select h.id from public.hives h join public.beekeepers b on h.beekeeper_id = b.id where b.profile_id = auth.uid()));
create policy hive_readings_select_org on hive_readings for select using (hive_id in (select h.id from public.hives h join public.beekeepers b on h.beekeeper_id = b.id where b.organization_id is not null and b.organization_id = public.auth_user_org_id()));

-- health_scores
alter table health_scores enable row level security;
drop policy if exists health_scores_select_own on health_scores;
drop policy if exists health_scores_insert_auth on health_scores;
drop policy if exists health_scores_select_org on health_scores;
create policy health_scores_select_own on health_scores for select using (hive_id in (select h.id from public.hives h join public.beekeepers b on h.beekeeper_id = b.id where b.profile_id = auth.uid()));
create policy health_scores_insert_auth on health_scores for insert to authenticated with check (true);
create policy health_scores_select_org on health_scores for select using (hive_id in (select h.id from public.hives h join public.beekeepers b on h.beekeeper_id = b.id where b.organization_id is not null and b.organization_id = public.auth_user_org_id()));

-- harvest_events
alter table harvest_events enable row level security;
drop policy if exists harvest_events_select_own on harvest_events;
drop policy if exists harvest_events_insert_own on harvest_events;
drop policy if exists harvest_events_select_org on harvest_events;
create policy harvest_events_select_own on harvest_events for select using (beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()));
create policy harvest_events_insert_own on harvest_events for insert with check (beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()));
create policy harvest_events_select_org on harvest_events for select using (beekeeper_id in (select id from public.beekeepers where organization_id is not null and organization_id = public.auth_user_org_id()));

-- batches
alter table batches enable row level security;
drop policy if exists batches_select_own on batches;
drop policy if exists batches_insert_own on batches;
drop policy if exists batches_update_own on batches;
create policy batches_select_own on batches for select using (beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id());
create policy batches_insert_own on batches for insert with check (beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id());
create policy batches_update_own on batches for update using (beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id());

-- batch_harvest_links
alter table batch_harvest_links enable row level security;
drop policy if exists batch_harvest_links_select_own on batch_harvest_links;
drop policy if exists batch_harvest_links_insert_own on batch_harvest_links;
create policy batch_harvest_links_select_own on batch_harvest_links for select using (batch_id in (select id from public.batches where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id()));
create policy batch_harvest_links_insert_own on batch_harvest_links for insert with check (batch_id in (select id from public.batches where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id()));

-- batch_genealogy
alter table batch_genealogy enable row level security;
drop policy if exists batch_genealogy_select_own on batch_genealogy;
drop policy if exists batch_genealogy_insert_own on batch_genealogy;
create policy batch_genealogy_select_own on batch_genealogy for select using (parent_batch_id in (select id from public.batches where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id()) or child_batch_id in (select id from public.batches where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id()));
create policy batch_genealogy_insert_own on batch_genealogy for insert with check (parent_batch_id in (select id from public.batches where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id()));

-- custody_events
alter table custody_events enable row level security;
drop policy if exists custody_events_select_own on custody_events;
drop policy if exists custody_events_insert_org on custody_events;
create policy custody_events_select_own on custody_events for select using (batch_id in (select id from public.batches where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id()));
create policy custody_events_insert_org on custody_events for insert to authenticated with check (batch_id in (select id from public.batches where organization_id = public.auth_user_org_id()));

-- lab_tests
alter table lab_tests enable row level security;
drop policy if exists lab_tests_select_own on lab_tests;
drop policy if exists lab_tests_insert_lab on lab_tests;
drop policy if exists lab_tests_update_lab on lab_tests;
create policy lab_tests_select_own on lab_tests for select using (batch_id in (select id from public.batches where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id()));
create policy lab_tests_insert_lab on lab_tests for insert to authenticated with check (public.auth_user_role() = 'lab');
create policy lab_tests_update_lab on lab_tests for update to authenticated using (public.auth_user_role() = 'lab');

-- blockchain_anchors
alter table blockchain_anchors enable row level security;
drop policy if exists blockchain_anchors_select_own on blockchain_anchors;
drop policy if exists blockchain_anchors_insert_org on blockchain_anchors;
create policy blockchain_anchors_select_own on blockchain_anchors for select using (batch_id in (select id from public.batches where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id()));
create policy blockchain_anchors_insert_org on blockchain_anchors for insert to authenticated with check (batch_id in (select id from public.batches where organization_id = public.auth_user_org_id()));

-- qr_codes
alter table qr_codes enable row level security;
drop policy if exists qr_codes_select_own on qr_codes;
drop policy if exists qr_codes_insert_org on qr_codes;
create policy qr_codes_select_own on qr_codes for select using (batch_id in (select id from public.batches where beekeeper_id in (select id from public.beekeepers where profile_id = auth.uid()) or organization_id = public.auth_user_org_id()));
create policy qr_codes_insert_org on qr_codes for insert to authenticated with check (batch_id in (select id from public.batches where organization_id = public.auth_user_org_id()));