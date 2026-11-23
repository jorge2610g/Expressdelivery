-- Ranking completo de un campeonato para el administrador (cualquier estado), con
-- filtro opcional por servicio. Mismas reglas de elegibilidad que el ranking del conductor.
create or replace function public.admin_driver_championship_ranking(
  p_championship_id uuid, p_service_key text default null)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_champ public.driver_championships%rowtype;
  v_context jsonb;
  v_service text;
  v_rows jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Acceso a campeonatos no autorizado';
  end if;
  select * into v_champ from public.driver_championships where id = p_championship_id;
  if v_champ.id is null then raise exception 'Campeonato no encontrado'; end if;
  if v_champ.channel not in ('preview','production')
     or not public.admin_environment_allowed(v_champ.channel) then
    raise exception 'Acceso a campeonatos no autorizado';
  end if;
  v_context := public.admin_access_context();
  if v_context->>'zone_id' is not null
     and (v_context->>'zone_id')::uuid <> v_champ.zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  -- Un campeonato de «todos los servicios» se puede ver por servicio; uno de un solo
  -- servicio siempre se calcula para ese servicio.
  v_service := case when v_champ.service_key = '*'
                    then coalesce(nullif(p_service_key, ''), '*')
                    else v_champ.service_key end;

  with eligible as (
    select dp.id, u.full_name
    from public.driver_profiles dp
    join public.users u on u.id = dp.id
    join public.account_runtime_bindings arb
      on arb.user_id = dp.id and arb.environment = v_champ.channel
    where dp.zone_id = v_champ.zone_id and dp.approval_status = 'approved'
      and u.account_status = 'active'
      and (v_champ.channel <> 'preview' or exists (
        select 1 from public.audit_test_group_members mem
        join public.audit_test_groups grp on grp.id = mem.group_id
        where mem.user_id = dp.id and mem.enabled = true and grp.active = true))
  ), counts as (
    select e.id, e.full_name, count(t.id)::integer as rides
    from eligible e left join public.trips t on t.driver_id = e.id
      and t.status = 'completed' and t.channel = v_champ.channel
      and t.completed_at >= v_champ.starts_at and t.completed_at < v_champ.ends_at
      and exists (select 1 from public.ride_requests r where r.id = t.ride_request_id
          and r.zone_id = v_champ.zone_id and r.channel = v_champ.channel
          and (v_service = '*' or r.category = v_service))
    group by e.id, e.full_name
  ), ordered as (
    select id, full_name, rides,
           row_number() over (order by rides desc, full_name asc, id)::integer as pos
    from counts
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'position', o.pos,
           'driver_id', o.id,
           'name', coalesce(nullif(trim(o.full_name), ''), 'Conductor'),
           'rides', o.rides) order by o.pos), '[]'::jsonb)
    into v_rows
  from ordered o where o.pos <= 100;

  return jsonb_build_object(
    'championship_id', v_champ.id, 'title', v_champ.title,
    'service_key', v_service, 'championship_service_key', v_champ.service_key,
    'state', v_champ.state, 'starts_at', v_champ.starts_at, 'ends_at', v_champ.ends_at,
    'rows', v_rows);
end $function$;

revoke all on function public.admin_driver_championship_ranking(uuid, text) from public, anon;
grant execute on function public.admin_driver_championship_ranking(uuid, text) to authenticated;
