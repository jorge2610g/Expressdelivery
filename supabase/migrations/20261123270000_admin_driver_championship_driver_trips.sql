-- Viajes que cuentan en el campeonato de un conductor (para el administrador).
create or replace function public.admin_driver_championship_driver_trips(
  p_championship_id uuid, p_driver_id uuid, p_service_key text default null)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_champ public.driver_championships%rowtype;
  v_context jsonb;
  v_service text;
  v_name text;
  v_rows jsonb;
  v_total integer;
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
  v_service := case when v_champ.service_key = '*'
                    then coalesce(nullif(p_service_key, ''), '*')
                    else v_champ.service_key end;
  select coalesce(nullif(trim(full_name), ''), 'Conductor') into v_name
    from public.users where id = p_driver_id;

  select count(*)::integer into v_total
  from public.trips t join public.ride_requests r on r.id = t.ride_request_id
  where t.driver_id = p_driver_id and t.status = 'completed' and t.channel = v_champ.channel
    and t.completed_at >= v_champ.starts_at and t.completed_at < v_champ.ends_at
    and r.zone_id = v_champ.zone_id and r.channel = v_champ.channel
    and (v_service = '*' or r.category = v_service);

  select coalesce(jsonb_agg(x order by (x->>'completed_at') desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object(
      'trip_id', t.id, 'completed_at', t.completed_at, 'service_key', r.category,
      'pickup', r.pickup_address, 'destination', r.destination_address,
      'fare', t.final_fare, 'currency', r.currency,
      'payment_method', r.payment_method, 'distance_km', r.route_distance_km) as x
    from public.trips t join public.ride_requests r on r.id = t.ride_request_id
    where t.driver_id = p_driver_id and t.status = 'completed' and t.channel = v_champ.channel
      and t.completed_at >= v_champ.starts_at and t.completed_at < v_champ.ends_at
      and r.zone_id = v_champ.zone_id and r.channel = v_champ.channel
      and (v_service = '*' or r.category = v_service)
    order by t.completed_at desc
    limit 300
  ) q;

  return jsonb_build_object(
    'driver_name', v_name, 'service_key', v_service, 'total', v_total,
    'starts_at', v_champ.starts_at, 'ends_at', v_champ.ends_at, 'trips', v_rows);
end $function$;

revoke all on function public.admin_driver_championship_driver_trips(uuid, uuid, text) from public, anon;
grant execute on function public.admin_driver_championship_driver_trips(uuid, uuid, text) to authenticated;
