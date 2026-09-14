-- Platform-governance controls (12).
--
-- Backend-only extension for PLATFORM_OVERSIGHT: account lifecycle state and
-- an append-only audit of sensitive organization/membership actions.
--
--   users.status          ACTIVE | SUSPENDED  -> login + authz gated server-side
--   platform_audit        who performed which governance action (actor, role,
--                         action, target), immutable history
--
-- Additive + idempotent. No existing rows are altered; service-role (the only
-- writer, RLS-bypassing) is unaffected, so intended backend operations keep
-- working. Memberships themselves remain the existing beekeepers.organization_id
-- / users.org_id binding — nothing is deleted when membership is revoked; the
-- persistent HoneyChain Producer ID and supply-chain history are preserved.

alter table users add column if not exists status text not null default 'ACTIVE';
alter table users add constraint chk_users_status check (status in ('ACTIVE', 'SUSPENDED'));

create table if not exists platform_audit (
  id uuid primary key default gen_random_uuid(),
  actor_user_id text not null,
  actor_role text not null,
  action text not null,
  target_type text not null,
  target_key text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_platform_audit_created on platform_audit(created_at desc);
create index if not exists idx_platform_audit_target on platform_audit(target_type, target_key);

alter table platform_audit enable row level security;