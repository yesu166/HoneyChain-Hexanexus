-- Idempotent offline sync support.
--
-- Every syncable relation carries a `client_id` (the app's stable local
-- record id) with a partial unique index. The app upserts on client_id so
-- retries and re-installs can never create duplicates. Reference entities
-- (organizations / beekeepers / hives) get the same treatment so the app can
-- materialize the record graph in dependency order.

alter table organizations add column if not exists client_id text;
alter table beekeepers add column if not exists client_id text;
alter table hives add column if not exists client_id text;
alter table harvest_events add column if not exists client_id text;
alter table batches add column if not exists client_id text;

create unique index if not exists uq_organizations_client_id
  on organizations(client_id) where client_id is not null;
create unique index if not exists uq_beekeepers_client_id
  on beekeepers(client_id) where client_id is not null;
create unique index if not exists uq_hives_client_id
  on hives(client_id) where client_id is not null;
create unique index if not exists uq_harvest_events_client_id
  on harvest_events(client_id) where client_id is not null;
create unique index if not exists uq_batches_client_id
  on batches(client_id) where client_id is not null;

-- An organization's own admin must be able to materialize its org row during
-- sync; "organization" joins the allowed roles (admin/processor/lab).
drop policy if exists organizations_insert_admin on organizations;
create policy organizations_insert_admin on organizations
  for insert to authenticated
  with check (public.auth_user_role() in ('admin','processor','lab','organization'));