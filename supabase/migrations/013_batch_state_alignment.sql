-- 013_batch_state_alignment.sql
-- Aligns the `batches.status` check constraint with the API's lineage state
-- machine (backend/app/services/lineage_service.py). The original constraint
-- allowed only created/processing/listed/archived, so any transition to
-- in_harvest / packaged / in_qa / distribution / retail was rejected by the
-- database even though the API advertised it. This migration is idempotent.
alter table public.batches drop constraint if exists batches_status_check;

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'batches_status_check'
      and conrelid = 'public.batches'::regclass
  ) then
    alter table public.batches drop constraint batches_status_check;
  end if;
end $$;

alter table public.batches
  add constraint batches_status_check
  check (status in (
    'created', 'in_harvest', 'processing', 'packaged', 'in_qa',
    'distribution', 'retail', 'recalled', 'rejected'
  ));