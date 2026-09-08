-- Consumer-facing public passport lookup (safe anonymous endpoint).

create or replace function public.get_public_passport(p_product_code text)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_qr record;
  v_batch record;
  v_harvests jsonb;
  v_custody jsonb;
  v_lab jsonb;
  v_anchors jsonb;
begin
  select * into v_qr from qr_codes where product_code = p_product_code;
  if not found then
    return jsonb_build_object('error', 'unknown_product', 'message', 'No honey record found for this product code.');
  end if;

  select * into v_batch from batches where id = v_qr.batch_id;

  select coalesce(jsonb_agg(jsonb_build_object('harvested_at', h.harvested_at, 'honey_type', h.honey_type, 'quantity_kg', h.quantity_kg, 'location', h.location)), '[]'::jsonb)
  into v_harvests
  from batch_harvest_links bhl
  join harvest_events h on h.id = bhl.harvest_event_id
  where bhl.batch_id = v_batch.id;

  select coalesce(jsonb_agg(jsonb_build_object('event_type', c.event_type, 'actor_role', c.actor_role, 'timestamp', c.timestamp, 'location', c.location) order by c.timestamp), '[]'::jsonb)
  into v_custody
  from custody_events c
  where c.batch_id = v_batch.id;

  select coalesce(jsonb_agg(jsonb_build_object('result', l.result, 'test_date', l.test_date, 'verified_at', l.verified_at)), '[]'::jsonb)
  into v_lab
  from (
    select l.result, l.test_date, l.verified_at
    from lab_tests l
    where l.batch_id = v_batch.id
    order by l.test_date desc
    limit 1
  ) l;

  select coalesce(jsonb_agg(jsonb_build_object('status', a.status, 'network', a.network, 'anchored_at', a.anchored_at) order by a.anchored_at desc), '[]'::jsonb)
  into v_anchors
  from blockchain_anchors a
  where a.batch_id = v_batch.id;

  return jsonb_build_object(
    'product_code', v_qr.product_code,
    'batch_code', v_batch.batch_code,
    'honey_type', v_batch.honey_type,
    'quantity_kg', v_batch.quantity_kg,
    'trust_tier', v_batch.trust_tier,
    'created_at', v_batch.created_at,
    'harvests', v_harvests,
    'custody', v_custody,
    'lab', v_lab,
    'anchors', v_anchors
  );
end;
$$;

revoke execute on function public.get_public_passport(text) from public;
grant execute on function public.get_public_passport(text) to anon;