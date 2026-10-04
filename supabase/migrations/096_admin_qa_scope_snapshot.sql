-- Scope-aware QA load-lab snapshot for Adminexpress.
-- Keeps Preview/sandbox and Production views isolated when both have data.

create or replace function public.admin_audit_load_snapshot_v2(
  p_scope text,
  p_city_key text default null
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_scope text := lower(coalesce(trim(p_scope), ''));
  v_city_key text := nullif(lower(coalesce(trim(p_city_key), '')), '');
  v_run public.audit_load_test_runs%rowtype;
  v_drivers jsonb := '[]'::jsonb;
  v_requests jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if v_scope in ('preview', 'sandbox', 'qa', 'test') then
    v_scope := 'sandbox';
  elsif v_scope in ('production', 'prod') then
    v_scope := 'production';
  else
    raise exception 'Entorno QA inválido: %', p_scope;
  end if;

  select r.*
  into v_run
  from public.audit_load_test_runs r
  where r.status='active'
    and coalesce(
      nullif(lower(r.metrics->>'scope_mode'), ''),
      case
        when r.label like '[PROD] %' then 'production'
        when r.label like '[QA] %' then 'sandbox'
        else 'sandbox'
      end
    ) = v_scope
    and (
      v_city_key is null
      or coalesce(
        nullif(lower(r.metrics->>'city_key'), ''),
        case
          when lower(r.label) like '%iquique%' then 'iquique'
          when lower(r.label) like '%trinidad%' then 'trinidad'
          else null
        end
      ) = v_city_key
    )
  order by r.created_at desc
  limit 1;

  if v_run.id is null then
    return jsonb_build_object(
      'scope', v_scope,
      'city_key', v_city_key,
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
      dp.vehicle_summary,
      (
        select dv.vehicle_type
        from public.driver_vehicles dv
        where dv.driver_id=dp.id
          and dv.is_active=true
        order by dv.updated_at desc nulls last
        limit 1
      ) as vehicle_type
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
      r.currency,
      r.payment_method,
      r.category,
      r.channel,
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
    'scope', v_scope,
    'city_key', v_city_key,
    'run', to_jsonb(v_run),
    'drivers', v_drivers,
    'requests', v_requests
  );
end;
$$;

revoke all on function public.admin_audit_load_snapshot_v2(text,text)
from public,anon;
grant execute on function public.admin_audit_load_snapshot_v2(text,text)
to authenticated;
