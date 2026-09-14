-- Organization-key sequence + FPO onboarding invites (11).
--
-- Backend-generated organization keys come from a single Postgres sequence so
-- concurrent API workers can never collide. `next_organization_key()` is
-- exposed as a PostgREST RPC and called server-side with the service-role key.
--
-- The sequence is advanced past the highest key the 010 backfill produced.
--
-- `organization_invites` seals an invite to the `organization_key` it was
-- issued for, so the FPO register flow (invite code in, organization key out)
-- can never bind a user to an arbitrary organization.

create sequence if not exists organizations_key_seq;

select setval(
  'organizations_key_seq',
  greatest(
    coalesce(
      (select max(split_part(organization_key, '-', 2)::bigint)
         from organizations
        where organization_key ~ '^ORG-[0-9]+$'),
      0
    ),
    1
  )
);

create or replace function next_organization_key()
returns text
language sql
as $$
  select 'ORG-' || lpad(nextval('organizations_key_seq')::text, 6, '0')
$$;

grant execute on function next_organization_key() to service_role;

create table if not exists organization_invites (
  id uuid primary key default gen_random_uuid(),
  organization_key text not null references organizations(organization_key) on delete cascade,
  email text not null,
  role text not null default 'fpo',
  token text not null unique,
  status text not null default 'PENDING' check (status in ('PENDING', 'USED', 'REVOKED')),
  invited_by uuid,
  invitee_user_id uuid,
  created_at timestamptz not null default now(),
  used_at timestamptz
);

create index if not exists idx_organization_invites_token on organization_invites(token);
create index if not exists idx_organization_invites_org on organization_invites(organization_key);

alter table organization_invites enable row level security;