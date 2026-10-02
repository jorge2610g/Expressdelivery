-- Admin snapshot for QA load lab visualization.
create or replace function public.admin_audit_load_snapshot()
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_run public.audit_load_test_runs%rowtype;
  v_drivers jsonb := '[]'::jsonb;
  v_requests jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select *
  into v_run
  from public.audit_load_test_runs
  where status='active'
  order by created_at desc
  limit 1;

  if v_run.id is null then
    return jsonb_build_object(
      'run', null,
      'drivers', '[]'::jsonb,
      'requests', '[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]'::jsonb)
  into v_drivers
  from (
    select
      u.full_name as name,
      dp.id,
      dp.latitude,
      dp.longitude,
      dp.online_status,
      dp.vehicle_summary
    from public.audit_load_test_entities e
    join public.driver_profiles dp on dp.id=e.user_id
    left join public.users u on u.id=dp.id
    where e.run_id=v_run.id
      and e.entity_type='driver'
    limit 500
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at),'[]'::jsonb)
  into v_requests
  from (
    select
      r.id,
      r.pickup_address,
      r.pickup_latitude,
      r.pickup_longitude,
      r.destination_address,
      r.destination_latitude,
      r.destination_longitude,
      r.proposed_fare,
      r.status,
      r.created_at,
      r.expires_at
    from public.audit_load_test_entities e
    join public.ride_requests r on r.id=e.ride_request_id
    where e.run_id=v_run.id
      and e.entity_type='ride_request'
    limit 500
  ) x;

  return jsonb_build_object(
    'run', to_jsonb(v_run),
    'drivers', v_drivers,
    'requests', v_requests
  );
end;
$$;

revoke all on function public.admin_audit_load_snapshot() from public, anon;
grant execute on function public.admin_audit_load_snapshot() to authenticated;
