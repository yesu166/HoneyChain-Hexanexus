-- Beekeeper HoneyChain Producer ID.
--
-- Every beekeeper identity carries a persistent, sequential Producer ID
-- (HC-BK-XXXXXX) created server-side at registration. It is distinct from the
-- login user id, the FPO/org id and the optional government madhukranti_id;
-- `producer_id` must never be interpreted as a government or NBB identifier.
-- Additive and idempotent.

alter table beekeepers add column if not exists producer_id text;

create index if not exists idx_beekeepers_producer_id on beekeepers(producer_id);