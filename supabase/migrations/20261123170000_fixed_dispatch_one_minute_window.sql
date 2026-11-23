-- Precio fijo: búsqueda de 1 minuto, sin repetir conductor y con espera automática.
-- Cada búsqueda dura 60 s. Dentro de ese minuto el viaje se ofrece, uno por vez
-- (15 s cada uno), al conductor más cercano que NUNCA haya recibido ese viaje
-- (ni en búsquedas anteriores). Si no queda ninguno, se espera y se ofrece al
-- que se conecte. Al terminar el minuto el pasajero decide: seguir o cancelar.
alter table public.ride_requests add column if not exists dispatch_window_ends_at timestamptz;

create or replace function public.fixed_dispatch_advance_v1(p_ride_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ride public.ride_requests%rowtype; v_seconds integer; v_max numeric; v_next record;
  v_rank integer; v_attempt uuid; v_amount text;
begin
  select * into v_ride from public.ride_requests where id = p_ride_request_id for update;
  if not found or v_ride.dispatch_style <> 'sequential' or v_ride.status not in ('searching','offers_received')
     or v_ride.expires_at is null or v_ride.expires_at <= now() then
    return jsonb_build_object('state','closed');
  end if;
  update public.ride_dispatch_attempts set status = 'expired', responded_at = now()
   where ride_request_id = v_ride.id and status = 'pending' and expires_at <= now();
  if exists (select 1 from public.ride_dispatch_attempts where ride_request_id = v_ride.id and status = 'pending') then
    return jsonb_build_object('state','waiting');
  end if;
  -- Se acabó el minuto y nadie lo tomó: el pasajero decide si sigue buscando.
  if v_ride.dispatch_exhausted_at is not null
     or (v_ride.dispatch_window_ends_at is not null and v_ride.dispatch_window_ends_at <= now()) then
    update public.ride_requests set dispatch_exhausted_at = coalesce(dispatch_exhausted_at, now()) where id = v_ride.id;
    return jsonb_build_object('state','exhausted');
  end if;
  select greatest(coalesce(fixed_dispatch_seconds, 15), 5), coalesce(max_driver_request_radius_km, 15)
    into v_seconds, v_max from public.app_settings where id = true;
  select c.driver_id, c.distance_km into v_next
  from public.ride_dispatch_candidates(v_ride, 0, v_max) c
  where not exists (select 1 from public.ride_dispatch_attempts a where a.ride_request_id = v_ride.id and a.driver_id = c.driver_id)
    and not public.driver_has_active_trip(c.driver_id)
    and not exists (select 1 from public.ride_dispatch_attempts a2 where a2.driver_id = c.driver_id and a2.status = 'pending' and a2.expires_at > now())
    and public.fixed_dispatch_vehicle_ok(c.driver_id, v_ride.category)
  order by c.distance_km asc
  limit 1;
  if v_next.driver_id is null then
    -- Nadie disponible por ahora: se sigue esperando a que se conecte alguien.
    return jsonb_build_object('state','searching');
  end if;
  select coalesce(max(rank), 0) + 1 into v_rank from public.ride_dispatch_attempts where ride_request_id = v_ride.id;
  insert into public.ride_dispatch_attempts(ride_request_id, driver_id, round, rank, distance_km, expires_at)
  values (v_ride.id, v_next.driver_id, v_ride.dispatch_round, v_rank, v_next.distance_km, now() + make_interval(secs => v_seconds))
  returning id into v_attempt;
  v_amount := trim(to_char(v_ride.proposed_fare, 'FM999999990.00'));
  perform set_config('app.runtime_channel', v_ride.channel, true);
  insert into public.notifications(user_id, title, body, type, metadata)
  values (v_next.driver_id, 'Nueva solicitud de viaje',
    'Viaje con precio fijo de ' || public.express_push_currency_label(v_ride.currency) || v_amount || '. Tienes ' || v_seconds || ' segundos para aceptar.',
    'ride_request',
    jsonb_build_object('ride_request_id', v_ride.id, 'zone_id', v_ride.zone_id, 'mode', 'driver', 'service_mode', v_ride.service_mode, 'deep_link', 'ride_request', 'dispatch_style', 'sequential'));
  return jsonb_build_object('state','offered','attempt_id',v_attempt,'driver_id',v_next.driver_id,'seconds',v_seconds);
end; $$;
revoke all on function public.fixed_dispatch_advance_v1(uuid) from public, anon, authenticated;

create or replace function public.start_fixed_dispatch()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.dispatch_style = 'sequential' then
    update public.ride_requests set dispatch_window_ends_at = now() + interval '60 seconds' where id = new.id;
    perform public.fixed_dispatch_advance_v1(new.id);
  end if;
  return new;
end;
$$;

create or replace function public.passenger_fixed_dispatch_restart_v1(p_ride_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_ride public.ride_requests%rowtype;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  select * into v_ride from public.ride_requests
   where id = p_ride_request_id and passenger_id = v_uid for update;
  if not found or v_ride.dispatch_style <> 'sequential' then raise exception 'No autorizado'; end if;
  if v_ride.status not in ('searching','offers_received') then
    raise exception 'Esta solicitud ya no está buscando conductor';
  end if;
  update public.ride_dispatch_attempts set status = 'cancelled', responded_at = now()
   where ride_request_id = v_ride.id and status = 'pending';
  -- Otro minuto de búsqueda. Los conductores que ya recibieron este viaje no se repiten.
  update public.ride_requests
     set dispatch_round = dispatch_round + 1, dispatch_exhausted_at = null,
         dispatch_window_ends_at = now() + interval '60 seconds',
         expires_at = greatest(expires_at, now() + interval '3 minutes'), updated_at = now()
   where id = v_ride.id;
  return public.fixed_dispatch_advance_v1(v_ride.id);
end;
$$;

create or replace function public.passenger_fixed_dispatch_state_v1(p_ride_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid(); v_ride public.ride_requests%rowtype; v_tick jsonb;
  v_cur record; v_last record; v_nearby integer; v_max numeric; v_tried integer;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  select * into v_ride from public.ride_requests where id = p_ride_request_id and passenger_id = v_uid;
  if not found then raise exception 'No autorizado'; end if;
  if v_ride.dispatch_style <> 'sequential' then return jsonb_build_object('mode','bidding'); end if;
  v_tick := public.fixed_dispatch_advance_v1(v_ride.id);
  select * into v_ride from public.ride_requests where id = v_ride.id;
  select coalesce(max_driver_request_radius_km, 15) into v_max from public.app_settings where id = true;
  select count(*) into v_nearby from public.ride_dispatch_candidates(v_ride, 0, v_max) c
   where not public.driver_has_active_trip(c.driver_id) and public.fixed_dispatch_vehicle_ok(c.driver_id, v_ride.category);
  select count(*) into v_tried from public.ride_dispatch_attempts where ride_request_id = v_ride.id;
  select a.id, a.driver_id, a.rank, a.expires_at, u.full_name, u.avatar_url, dp.rating, dp.vehicle_summary, dp.completed_trips,
         case when public.can_view_driver_profile_photo(dp.id, dp.profile_photo_path) then dp.profile_photo_path else null end as profile_photo_path
    into v_cur
  from public.ride_dispatch_attempts a
  join public.users u on u.id = a.driver_id
  left join public.driver_profiles dp on dp.id = a.driver_id
  where a.ride_request_id = v_ride.id and a.status = 'pending' and a.expires_at > now()
  limit 1;
  select a.status, u.full_name, a.rank into v_last
  from public.ride_dispatch_attempts a join public.users u on u.id = a.driver_id
  where a.ride_request_id = v_ride.id and a.status in ('declined','expired')
  order by a.rank desc limit 1;
  return jsonb_build_object(
    'mode', 'sequential', 'ride_status', v_ride.status, 'proposed_fare', v_ride.proposed_fare, 'currency', v_ride.currency,
    'nearby_drivers', v_nearby, 'tried_drivers', v_tried,
    'exhausted', v_ride.dispatch_exhausted_at is not null, 'round', v_ride.dispatch_round,
    'window_seconds_left', case when v_ride.dispatch_window_ends_at is null then null
       else greatest(0, ceil(extract(epoch from (v_ride.dispatch_window_ends_at - now())))) end,
    'current', case when v_cur.id is null then null else jsonb_build_object(
      'driver_id', v_cur.driver_id, 'full_name', v_cur.full_name, 'avatar_url', v_cur.avatar_url, 'rating', v_cur.rating,
      'vehicle_summary', v_cur.vehicle_summary, 'completed_trips', v_cur.completed_trips, 'profile_photo_path', v_cur.profile_photo_path,
      'rank', v_cur.rank, 'expires_at', v_cur.expires_at, 'seconds_left', greatest(0, ceil(extract(epoch from (v_cur.expires_at - now()))))) end,
    'previous', case when v_last.status is null then null else jsonb_build_object('status', v_last.status, 'full_name', v_last.full_name, 'rank', v_last.rank) end,
    'server_now', now());
end; $$;
