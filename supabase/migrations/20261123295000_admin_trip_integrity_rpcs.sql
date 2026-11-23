-- RPC del panel para revisar viajes marcados por irregularidades.
create or replace function public.admin_trip_integrity_list(
  p_zone_id uuid, p_channel text, p_status text default 'open')
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_context jsonb;
begin
  if auth.uid() is null or not public.is_admin()
     or p_channel not in ('preview','production')
     or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso a viajes sospechosos no autorizado';
  end if;
  v_context := public.admin_access_context();
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid <> p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  return (
    select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', f.id, 'trip_id', f.trip_id, 'severity', f.severity,
        'reasons', f.reasons, 'metrics', f.metrics,
        'review_status', f.review_status, 'review_note', f.review_note,
        'created_at', f.created_at, 'reviewed_at', f.reviewed_at,
        'driver_id', f.driver_id,
        'driver_name', coalesce(nullif(trim(du.full_name), ''), 'Conductor'),
        'passenger_name', coalesce(nullif(trim(pu.full_name), ''), 'Pasajero'),
        'service_key', r.category, 'pickup', r.pickup_address,
        'destination', r.destination_address, 'fare', t.final_fare,
        'currency', r.currency, 'completed_at', t.completed_at,
        'open_flags_driver', (select count(*) from public.trip_integrity_flags o
                               where o.driver_id = f.driver_id and o.review_status = 'open')
      ) as x
      from public.trip_integrity_flags f
      join public.trips t on t.id = f.trip_id
      join public.ride_requests r on r.id = t.ride_request_id
      left join public.users du on du.id = f.driver_id
      left join public.users pu on pu.id = f.passenger_id
      where f.zone_id = p_zone_id and f.channel = p_channel
        and (p_status is null or p_status = 'all' or f.review_status = p_status)
      order by f.created_at desc
      limit 200
    ) q
  );
end $function$;

create or replace function public.admin_trip_integrity_trail(p_flag_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  f public.trip_integrity_flags%rowtype; v_context jsonb; r public.ride_requests%rowtype;
  t public.trips%rowtype; v_points jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Acceso a viajes sospechosos no autorizado';
  end if;
  select * into f from public.trip_integrity_flags where id = p_flag_id;
  if f.id is null then raise exception 'Viaje marcado no encontrado'; end if;
  if f.channel not in ('preview','production') or not public.admin_environment_allowed(f.channel) then
    raise exception 'Acceso a viajes sospechosos no autorizado';
  end if;
  v_context := public.admin_access_context();
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid <> f.zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  select * into t from public.trips where id = f.trip_id;
  select * into r from public.ride_requests where id = t.ride_request_id;
  select coalesce(jsonb_agg(jsonb_build_object(
           'lat', p.latitude, 'lng', p.longitude, 'status', p.trip_status, 'at', p.recorded_at)
           order by p.recorded_at), '[]'::jsonb)
    into v_points
  from (select * from public.trip_location_points where trip_id = f.trip_id
         order by recorded_at limit 3000) p;
  return jsonb_build_object(
    'flag_id', f.id, 'trip_id', f.trip_id, 'severity', f.severity, 'reasons', f.reasons,
    'metrics', f.metrics, 'review_status', f.review_status, 'review_note', f.review_note,
    'pickup', jsonb_build_object('lat', r.pickup_latitude, 'lng', r.pickup_longitude, 'address', r.pickup_address),
    'destination', jsonb_build_object('lat', r.destination_latitude, 'lng', r.destination_longitude, 'address', r.destination_address),
    'completed_at', t.completed_at, 'points', v_points);
end $function$;

create or replace function public.admin_trip_integrity_review(
  p_flag_id uuid, p_decision text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare f public.trip_integrity_flags%rowtype; v_context jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Acceso a viajes sospechosos no autorizado';
  end if;
  if p_decision not in ('cleared','confirmed') then
    raise exception 'Decisión no válida';
  end if;
  select * into f from public.trip_integrity_flags where id = p_flag_id for update;
  if f.id is null then raise exception 'Viaje marcado no encontrado'; end if;
  if f.channel not in ('preview','production') or not public.admin_environment_allowed(f.channel) then
    raise exception 'Acceso a viajes sospechosos no autorizado';
  end if;
  v_context := public.admin_access_context();
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid <> f.zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  update public.trip_integrity_flags
     set review_status = p_decision, reviewed_by = auth.uid(), reviewed_at = now(),
         review_note = nullif(trim(coalesce(p_note, '')), '')
   where id = f.id;
  return jsonb_build_object('ok', true, 'review_status', p_decision);
end $function$;

revoke all on function public.admin_trip_integrity_list(uuid, text, text) from public, anon;
revoke all on function public.admin_trip_integrity_trail(uuid) from public, anon;
revoke all on function public.admin_trip_integrity_review(uuid, text, text) from public, anon;
grant execute on function public.admin_trip_integrity_list(uuid, text, text) to authenticated;
grant execute on function public.admin_trip_integrity_trail(uuid) to authenticated;
grant execute on function public.admin_trip_integrity_review(uuid, text, text) to authenticated;
