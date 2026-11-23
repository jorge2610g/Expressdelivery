-- Precio fijo con asignación al conductor más cercano (uno a uno).
-- Es un modo de cada servicio por zona (zone_service_catalog.price_mode).
-- Apagado por defecto: 'offer' conserva el comportamiento actual.

alter table public.zone_service_catalog
  add column if not exists price_mode text not null default 'offer';
alter table public.zone_service_catalog
  drop constraint if exists zone_service_catalog_price_mode_check;
alter table public.zone_service_catalog
  add constraint zone_service_catalog_price_mode_check
  check (price_mode in ('offer','fixed'));

alter table public.ride_requests
  add column if not exists dispatch_style text not null default 'bidding',
  add column if not exists dispatch_round integer not null default 1,
  add column if not exists dispatch_exhausted_at timestamptz;
alter table public.ride_requests
  drop constraint if exists ride_requests_dispatch_style_check;
alter table public.ride_requests
  add constraint ride_requests_dispatch_style_check
  check (dispatch_style in ('bidding','sequential'));

alter table public.app_settings
  add column if not exists fixed_dispatch_seconds integer not null default 15;

create table if not exists public.ride_dispatch_attempts (
  id uuid primary key default gen_random_uuid(),
  ride_request_id uuid not null references public.ride_requests(id) on delete cascade,
  driver_id uuid not null references public.users(id) on delete cascade,
  round integer not null default 1,
  rank integer not null default 1,
  distance_km numeric,
  status text not null default 'pending'
    check (status in ('pending','accepted','declined','expired','cancelled')),
  offered_at timestamptz not null default now(),
  expires_at timestamptz not null,
  responded_at timestamptz
);
create unique index if not exists ride_dispatch_attempts_one_pending_per_ride
  on public.ride_dispatch_attempts (ride_request_id) where status = 'pending';
create index if not exists ride_dispatch_attempts_driver_idx
  on public.ride_dispatch_attempts (driver_id, status, expires_at);
create index if not exists ride_dispatch_attempts_ride_idx
  on public.ride_dispatch_attempts (ride_request_id, round, rank);
alter table public.ride_dispatch_attempts enable row level security;
revoke all on public.ride_dispatch_attempts from anon, authenticated;

-- ---------------------------------------------------------------- precio
create or replace function public.apply_service_fixed_price()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_mode text;
  v_quote jsonb;
  v_increment numeric;
  v_fare numeric;
begin
  if new.service_mode = 'parcel' or new.zone_id is null or new.scheduled_for is not null then
    return new;
  end if;
  select zs.price_mode into v_mode
  from public.zone_service_catalog zs
  where zs.zone_id = new.zone_id and zs.service_key = new.category;
  if coalesce(v_mode, 'offer') <> 'fixed' then
    return new;
  end if;
  if new.pickup_latitude is null or new.pickup_longitude is null
     or coalesce(new.route_distance_km, 0) <= 0 then
    raise exception 'Faltan los datos de la ruta para calcular el precio fijo';
  end if;
  v_quote := public.dynamic_pricing_quote_internal(
    new.category, new.route_distance_km, coalesce(new.route_duration_minutes, 0),
    new.pickup_latitude, new.pickup_longitude, new.channel);
  v_increment := public.fare_rounding_increment(
    coalesce(v_quote->>'currency', new.currency), new.channel);
  v_fare := public.fare_round_value(
    coalesce((v_quote->>'minimum_allowed_fare')::numeric,
             (v_quote->>'amount')::numeric), v_increment);
  if v_fare is null or v_fare <= 0 then
    raise exception 'No se pudo calcular el precio fijo';
  end if;
  new.proposed_fare := v_fare;
  new.base_fare := v_fare;
  new.pricing_mode := 'fixed';
  new.dispatch_style := 'sequential';
  new.currency := coalesce(v_quote->>'currency', new.currency);
  new.fare_rounding_increment := v_increment;
  new.demand_multiplier := coalesce((v_quote->>'demand_multiplier')::numeric, 1);
  new.demand_level := coalesce(v_quote->>'demand_level', 'normal');
  return new;
end;
$$;
drop trigger if exists zy_apply_service_fixed_price on public.ride_requests;
create trigger zy_apply_service_fixed_price
  before insert on public.ride_requests
  for each row execute function public.apply_service_fixed_price();

-- Sin anillos ni avisos masivos para los viajes de asignación uno a uno.
create or replace function public.set_ride_dispatch_ring()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_mode text; v_first numeric; v_max numeric;
begin
  if new.dispatch_style = 'sequential' then return new; end if;
  select dispatch_mode, coalesce(dispatch_radius_km, 1), coalesce(max_driver_request_radius_km, 15)
    into v_mode, v_first, v_max from public.app_settings where id = true;
  if v_mode = 'progressive'
     and new.scheduled_for is null
     and new.pickup_latitude is not null
     and new.pickup_longitude is not null then
    new.dispatch_ring_km := least(greatest(v_first, 0.5), v_max);
    new.dispatch_ring_started_at := now();
  end if;
  return new;
end;
$$;
-- El disparador de anillos debe ejecutarse después del de precio fijo.
drop trigger if exists zz_set_ride_dispatch_ring on public.ride_requests;
create trigger zz_set_ride_dispatch_ring
  before insert on public.ride_requests
  for each row execute function public.set_ride_dispatch_ring();

create or replace function public.notify_available_ride_to_drivers()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_max numeric;
begin
  if new.status <> 'searching' then return new; end if;
  if new.dispatch_style = 'sequential' then return new; end if;
  if left(coalesce(new.pickup_address, ''), 9) = '[LOADTEST' then return new; end if;
  if new.zone_id is null then return new; end if;
  if tg_op = 'UPDATE' then
    if old.status = 'searching'
       and old.expires_at is not distinct from new.expires_at
       and old.proposed_fare is not distinct from new.proposed_fare then
      return new;
    end if;
  end if;
  if new.scheduled_for is not null
     and new.scheduled_for > now() + interval '30 minutes' then
    return new;
  end if;
  if new.pickup_latitude is null or new.pickup_longitude is null then
    return new;
  end if;
  select coalesce(max_driver_request_radius_km, 15) into v_max
  from public.app_settings where id = true;
  perform public.notify_ride_candidates(
    new, 0, least(greatest(coalesce(new.dispatch_ring_km, v_max), 1), 100));
  return new;
end;
$$;

create or replace function public.advance_ride_dispatch_rings()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r public.ride_requests%rowtype;
  v_max numeric; v_step numeric; v_seconds integer; v_new numeric; v_count integer := 0;
begin
  select coalesce(max_driver_request_radius_km, 15),
         greatest(coalesce(progressive_radius_step_km, 1), 0.5),
         greatest(coalesce(dispatch_ring_seconds, 30), 10)
    into v_max, v_step, v_seconds
  from public.app_settings where id = true;
  for r in
    select * from public.ride_requests
    where status = 'searching'
      and dispatch_style = 'bidding'
      and dispatch_ring_km is not null
      and dispatch_ring_km < v_max
      and dispatch_ring_started_at <= now() - make_interval(secs => v_seconds)
      and expires_at > now()
      and scheduled_for is null
      and pickup_latitude is not null
      and pickup_longitude is not null
      and not exists (
        select 1 from public.driver_offers o
        where o.ride_request_id = ride_requests.id and o.status = 'pending')
    order by dispatch_ring_started_at
    for update skip locked
  loop
    v_new := least(r.dispatch_ring_km + v_step, v_max);
    update public.ride_requests
       set dispatch_ring_km = v_new, dispatch_ring_started_at = now()
     where id = r.id;
    perform public.notify_ride_candidates(r, r.dispatch_ring_km, v_new);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- --------------------------------------------------------- asignación
-- Ofrece el viaje al siguiente conductor más cercano. Interna: no se concede.
create or replace function public.fixed_dispatch_advance_v1(p_ride_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ride public.ride_requests%rowtype;
  v_seconds integer;
  v_max numeric;
  v_next record;
  v_rank integer;
  v_attempt uuid;
  v_amount text;
begin
  select * into v_ride from public.ride_requests
   where id = p_ride_request_id for update;
  if not found or v_ride.dispatch_style <> 'sequential'
     or v_ride.status not in ('searching','offers_received')
     or v_ride.expires_at is null or v_ride.expires_at <= now() then
    return jsonb_build_object('state','closed');
  end if;

  update public.ride_dispatch_attempts
     set status = 'expired', responded_at = now()
   where ride_request_id = v_ride.id and status = 'pending' and expires_at <= now();

  if exists (select 1 from public.ride_dispatch_attempts
              where ride_request_id = v_ride.id and status = 'pending') then
    return jsonb_build_object('state','waiting');
  end if;

  select greatest(coalesce(fixed_dispatch_seconds, 15), 5),
         coalesce(max_driver_request_radius_km, 15)
    into v_seconds, v_max from public.app_settings where id = true;

  select c.driver_id, c.distance_km into v_next
  from public.ride_dispatch_candidates(v_ride, 0, v_max) c
  where not exists (
          select 1 from public.ride_dispatch_attempts a
           where a.ride_request_id = v_ride.id and a.round = v_ride.dispatch_round
             and a.driver_id = c.driver_id)
    and not public.driver_has_active_trip(c.driver_id)
    and not exists (
          select 1 from public.ride_dispatch_attempts a2
           where a2.driver_id = c.driver_id and a2.status = 'pending'
             and a2.expires_at > now())
    and public.driver_vehicle_supports_ride(c.driver_id, v_ride.id)
  order by c.distance_km asc
  limit 1;

  if v_next.driver_id is null then
    update public.ride_requests set dispatch_exhausted_at = coalesce(dispatch_exhausted_at, now())
     where id = v_ride.id;
    return jsonb_build_object('state','exhausted');
  end if;

  select coalesce(max(rank), 0) + 1 into v_rank
  from public.ride_dispatch_attempts
  where ride_request_id = v_ride.id and round = v_ride.dispatch_round;

  insert into public.ride_dispatch_attempts(
    ride_request_id, driver_id, round, rank, distance_km, expires_at)
  values (v_ride.id, v_next.driver_id, v_ride.dispatch_round, v_rank, v_next.distance_km,
          now() + make_interval(secs => v_seconds))
  returning id into v_attempt;

  update public.ride_requests set dispatch_exhausted_at = null where id = v_ride.id;

  v_amount := trim(to_char(v_ride.proposed_fare, 'FM999999990.00'));
  perform set_config('app.runtime_channel', v_ride.channel, true);
  insert into public.notifications(user_id, title, body, type, metadata)
  values (v_next.driver_id, 'Nueva solicitud de viaje',
    'Viaje con precio fijo de ' || public.express_push_currency_label(v_ride.currency) || v_amount ||
      '. Tienes ' || v_seconds || ' segundos para aceptar.',
    'ride_request',
    jsonb_build_object('ride_request_id', v_ride.id, 'zone_id', v_ride.zone_id,
      'mode', 'driver', 'service_mode', v_ride.service_mode, 'deep_link', 'ride_request',
      'dispatch_style', 'sequential'));
  return jsonb_build_object('state','offered','attempt_id',v_attempt,
    'driver_id',v_next.driver_id,'seconds',v_seconds);
end;
$$;
revoke all on function public.fixed_dispatch_advance_v1(uuid) from public, anon, authenticated;

create or replace function public.start_fixed_dispatch()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.dispatch_style = 'sequential' then
    perform public.fixed_dispatch_advance_v1(new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists trg_start_fixed_dispatch on public.ride_requests;
create trigger trg_start_fixed_dispatch
  after insert on public.ride_requests
  for each row execute function public.start_fixed_dispatch();

-- Pasa al siguiente conductor cuando vence el tiempo o el viaje se cancela.
create or replace function public.fixed_dispatch_tick_all_v1()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id uuid; v_count integer := 0;
begin
  update public.ride_dispatch_attempts a
     set status = 'cancelled', responded_at = now()
   where a.status = 'pending'
     and exists (select 1 from public.ride_requests r
                  where r.id = a.ride_request_id
                    and r.status not in ('searching','offers_received'));
  for v_id in
    select r.id from public.ride_requests r
    where r.dispatch_style = 'sequential'
      and r.status in ('searching','offers_received')
      and r.expires_at > now()
      and r.dispatch_exhausted_at is null
      and not exists (select 1 from public.ride_dispatch_attempts a
                       where a.ride_request_id = r.id and a.status = 'pending'
                         and a.expires_at > now())
    order by r.created_at
    limit 50
  loop
    perform public.fixed_dispatch_advance_v1(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.fixed_dispatch_tick_all_v1() from public, anon, authenticated;

-- ------------------------------------------------------------- conductor
create or replace function public.driver_decline_fixed_dispatch_v1(p_ride_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  update public.ride_dispatch_attempts
     set status = 'declined', responded_at = now()
   where ride_request_id = p_ride_request_id and driver_id = v_uid and status = 'pending';
  return public.fixed_dispatch_advance_v1(p_ride_request_id);
end;
$$;

create or replace function public.driver_accept_fixed_dispatch_v1(
  p_ride_request_id uuid, p_channel text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_channel text := public.normalize_runtime_channel(p_channel);
  v_ride public.ride_requests%rowtype;
  v_attempt public.ride_dispatch_attempts%rowtype;
  v_offer_id uuid; v_trip_id uuid; v_pin text; v_driver_name text; v_amount text;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  select * into v_ride from public.ride_requests where id = p_ride_request_id for update;
  if not found then raise exception 'Solicitud no disponible'; end if;
  if v_ride.channel is distinct from v_channel then
    raise exception 'Solicitud fuera del entorno seleccionado';
  end if;
  if v_ride.dispatch_style <> 'sequential' then
    raise exception 'Esta solicitud no es de precio fijo';
  end if;
  if v_ride.status not in ('searching','offers_received')
     or v_ride.expires_at is null or v_ride.expires_at <= now() then
    raise exception 'Solicitud vencida o no disponible';
  end if;
  select * into v_attempt from public.ride_dispatch_attempts a
   where a.ride_request_id = v_ride.id and a.driver_id = v_uid
     and a.status = 'pending' and a.expires_at > now() for update;
  if not found then raise exception 'Se acabó el tiempo para aceptar este viaje'; end if;
  if not exists (
    select 1 from public.driver_profiles dp
     where dp.id = v_uid and dp.online_status = 'online'
       and dp.approval_status = 'approved' and dp.zone_id = v_ride.zone_id) then
    raise exception 'Solicitud no disponible para tu estado en línea o tu zona';
  end if;
  perform pg_advisory_xact_lock(hashtext('driver_trip:' || v_uid::text));
  if public.driver_has_active_trip(v_uid) then
    raise exception 'Tienes un viaje activo. Termínalo antes de aceptar otro.';
  end if;
  perform set_config('app.runtime_channel', v_channel, true);
  perform set_config('app.fixed_dispatch_accept', 'on', true);

  insert into public.driver_offers(
    ride_request_id, driver_id, channel, proposed_fare, eta_minutes, status, created_at, expires_at)
  values (v_ride.id, v_uid, v_channel, v_ride.proposed_fare, null, 'selected', now(), now() + interval '1 minute')
  on conflict (ride_request_id, driver_id) do update set
    status = 'selected', proposed_fare = excluded.proposed_fare, channel = excluded.channel,
    eta_minutes = null, created_at = excluded.created_at, expires_at = excluded.expires_at
  returning id into v_offer_id;

  update public.ride_dispatch_attempts
     set status = 'accepted', responded_at = now() where id = v_attempt.id;
  update public.ride_requests set status = 'driver_selected', updated_at = now() where id = v_ride.id;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');
  insert into public.trips(ride_request_id, passenger_id, driver_id, status, final_fare, payment_status, boarding_pin)
  values (v_ride.id, v_ride.passenger_id, v_uid, 'driver_arriving', v_ride.proposed_fare, 'pending', v_pin)
  returning id into v_trip_id;
  insert into public.trip_status_history(trip_id, status, changed_by)
  values (v_trip_id, 'driver_arriving', v_uid);
  update public.driver_profiles set online_status = 'busy', updated_at = now() where id = v_uid;

  select nullif(trim(u.full_name), '') into v_driver_name from public.users u where u.id = v_uid;
  v_amount := trim(to_char(v_ride.proposed_fare, 'FM999999990.00'));
  insert into public.notifications(user_id, title, body, type)
  values
    (v_uid, '¡Viaje confirmado!',
     'Viaje con precio fijo de ' || public.express_push_currency_label(v_ride.currency) || v_amount ||
       '. Ya estás en camino al punto de recogida.', 'ride_assigned'),
    (v_ride.passenger_id, 'Conductor confirmado',
     coalesce(v_driver_name, 'Tu conductor') ||
       ' fue asignado y ya va en camino. Sigue su llegada en el mapa.', 'ride_assigned');
  return v_trip_id;
end;
$$;

-- Los conductores no pueden contraofertar en viajes de precio fijo.
create or replace function public.block_bidding_on_fixed_dispatch()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if coalesce(current_setting('app.fixed_dispatch_accept', true), '') = 'on' then
    return new;
  end if;
  if exists (select 1 from public.ride_requests r
              where r.id = new.ride_request_id and r.dispatch_style = 'sequential') then
    raise exception 'Este viaje es de precio fijo: solo se puede aceptar o rechazar';
  end if;
  return new;
end;
$$;
drop trigger if exists aa_block_bidding_on_fixed_dispatch on public.driver_offers;
create trigger aa_block_bidding_on_fixed_dispatch
  before insert on public.driver_offers
  for each row execute function public.block_bidding_on_fixed_dispatch();

-- ------------------------------------------------------------- pasajero
create or replace function public.passenger_fixed_dispatch_state_v1(p_ride_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_ride public.ride_requests%rowtype;
  v_tick jsonb;
  v_cur record;
  v_last record;
  v_nearby integer;
  v_max numeric;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  select * into v_ride from public.ride_requests
   where id = p_ride_request_id and passenger_id = v_uid;
  if not found then raise exception 'No autorizado'; end if;
  if v_ride.dispatch_style <> 'sequential' then
    return jsonb_build_object('mode','bidding');
  end if;
  v_tick := public.fixed_dispatch_advance_v1(v_ride.id);
  select * into v_ride from public.ride_requests where id = v_ride.id;
  select coalesce(max_driver_request_radius_km, 15) into v_max from public.app_settings where id = true;
  select count(*) into v_nearby
  from public.ride_dispatch_candidates(v_ride, 0, v_max) c
  where not public.driver_has_active_trip(c.driver_id);

  select a.id, a.driver_id, a.rank, a.expires_at, u.full_name, u.avatar_url,
         dp.rating, dp.vehicle_summary, dp.completed_trips,
         case when public.can_view_driver_profile_photo(dp.id, dp.profile_photo_path)
              then dp.profile_photo_path else null end as profile_photo_path
    into v_cur
  from public.ride_dispatch_attempts a
  join public.users u on u.id = a.driver_id
  left join public.driver_profiles dp on dp.id = a.driver_id
  where a.ride_request_id = v_ride.id and a.status = 'pending' and a.expires_at > now()
  limit 1;

  select a.status, u.full_name, a.rank into v_last
  from public.ride_dispatch_attempts a
  join public.users u on u.id = a.driver_id
  where a.ride_request_id = v_ride.id and a.round = v_ride.dispatch_round
    and a.status in ('declined','expired')
  order by a.rank desc limit 1;

  return jsonb_build_object(
    'mode', 'sequential',
    'ride_status', v_ride.status,
    'proposed_fare', v_ride.proposed_fare,
    'currency', v_ride.currency,
    'nearby_drivers', v_nearby,
    'exhausted', v_ride.dispatch_exhausted_at is not null,
    'round', v_ride.dispatch_round,
    'current', case when v_cur.id is null then null else jsonb_build_object(
      'driver_id', v_cur.driver_id, 'full_name', v_cur.full_name,
      'avatar_url', v_cur.avatar_url, 'rating', v_cur.rating,
      'vehicle_summary', v_cur.vehicle_summary, 'completed_trips', v_cur.completed_trips,
      'profile_photo_path', v_cur.profile_photo_path,
      'rank', v_cur.rank, 'expires_at', v_cur.expires_at,
      'seconds_left', greatest(0, ceil(extract(epoch from (v_cur.expires_at - now()))))) end,
    'previous', case when v_last.status is null then null else jsonb_build_object(
      'status', v_last.status, 'full_name', v_last.full_name, 'rank', v_last.rank) end,
    'server_now', now());
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
  update public.ride_requests
     set dispatch_round = dispatch_round + 1, dispatch_exhausted_at = null,
         expires_at = greatest(expires_at, now() + interval '3 minutes'), updated_at = now()
   where id = v_ride.id;
  return public.fixed_dispatch_advance_v1(v_ride.id);
end;
$$;

-- El pasajero puede ver la foto del conductor al que se le ofrece su viaje.
create or replace function public.can_view_driver_profile_photo(p_driver_id uuid, p_path text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select auth.uid() is not null and public.is_account_active()
    and p_path is not null
    and p_path like p_driver_id::text||'/%'
    and exists(
      select 1 from public.driver_profiles dp
      where dp.id=p_driver_id and dp.profile_photo_path=p_path
        and (
          dp.id=auth.uid()
          or public.is_admin()
          or (
            dp.approval_status='approved'
            and coalesce((select b.environment from public.account_runtime_bindings b where b.user_id=auth.uid()),'production')=
                coalesce((select b.environment from public.account_runtime_bindings b where b.user_id=p_driver_id),'production')
            and (
              exists(select 1 from public.trips t where t.driver_id=p_driver_id and t.passenger_id=auth.uid() and t.status not in ('completed','cancelled')
                and t.channel=coalesce((select b.environment from public.account_runtime_bindings b where b.user_id=auth.uid()),'production'))
              or exists(select 1 from public.driver_offers o join public.ride_requests r on r.id=o.ride_request_id
                where o.driver_id=p_driver_id and r.passenger_id=auth.uid() and o.status in ('pending','selected')
                  and r.status in ('searching','offers_received','driver_selected') and (o.expires_at is null or o.expires_at>now())
                  and r.channel=o.channel and r.channel=coalesce((select b.environment from public.account_runtime_bindings b where b.user_id=auth.uid()),'production'))
              or exists(select 1 from public.ride_request_views v join public.ride_requests r on r.id=v.ride_request_id
                where v.driver_id=p_driver_id and r.passenger_id=auth.uid() and r.status in ('searching','offers_received')
                  and (r.expires_at is null or r.expires_at>now())
                  and r.channel=coalesce((select b.environment from public.account_runtime_bindings b where b.user_id=auth.uid()),'production'))
              or exists(select 1 from public.ride_dispatch_attempts a join public.ride_requests r on r.id=a.ride_request_id
                where a.driver_id=p_driver_id and r.passenger_id=auth.uid()
                  and r.status in ('searching','offers_received','driver_selected')
                  and a.offered_at > now() - interval '15 minutes'
                  and r.channel=coalesce((select b.environment from public.account_runtime_bindings b where b.user_id=auth.uid()),'production'))
            )
          )
        )
    );
$$;

-- ---------------------------------------------------------------- permisos
do $$
declare f text;
begin
  foreach f in array array[
    'driver_decline_fixed_dispatch_v1(uuid)',
    'driver_accept_fixed_dispatch_v1(uuid,text)',
    'passenger_fixed_dispatch_state_v1(uuid)',
    'passenger_fixed_dispatch_restart_v1(uuid)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ------------------------------------------- lista de solicitudes del conductor
-- Los viajes de precio fijo solo aparecen para el conductor al que se le ofrecen.
create or replace function public.available_ride_requests_for_driver()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_scheduled_before integer := 30;
  v_visible_seconds integer := 180;
  v_max_visible integer := 20;
  v_radius numeric := 15;
  v_lat numeric;
  v_lng numeric;
  v_zone_id uuid;
  v_audit boolean := false;
  v_limit integer := 20;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if not (
    public.driver_work_permission_allowed(v_uid,'ride',public.admin_user_runtime_environment(v_uid))
    or public.driver_work_permission_allowed(v_uid,'parcel',public.admin_user_runtime_environment(v_uid))
  ) then return '[]'::jsonb; end if;
  if not public.is_approved_online_driver(v_uid) then
    return '[]'::jsonb;
  end if;

  select
    coalesce(scheduled_publish_before_minutes,30),
    coalesce(request_visible_seconds,180),
    coalesce(max_visible_requests_driver,20),
    coalesce(max_driver_request_radius_km,15)
  into v_scheduled_before, v_visible_seconds, v_max_visible, v_radius
  from public.app_settings where id=true;

  select exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid and m.enabled=true and g.active=true
  ) into v_audit;

  v_limit := case
    when v_audit then 250
    else least(greatest(v_max_visible,1),100)
  end;

  select latitude, longitude, zone_id
    into v_lat, v_lng, v_zone_id
  from public.driver_profiles
  where id=v_uid
  limit 1;

  if v_zone_id is null
     or not public.driver_subscription_allows_dispatch(v_uid) then
    return '[]'::jsonb;
  end if;

  if v_lat is null or v_lng is null then
    return '[]'::jsonb;
  end if;

  select coalesce(
    jsonb_agg((
      to_jsonb(x)
      - 'parcel_sender_name' - 'parcel_sender_phone'
      - 'parcel_recipient_name' - 'parcel_recipient_phone'
      - 'parcel_photo_paths'
    ) order by x.pickup_distance_sort asc, x.created_at asc),
    '[]'::jsonb
  )
  into v_result
  from (
    select
      r.*,
      public.geo_distance_km(v_lat,v_lng,r.pickup_latitude,r.pickup_longitude) as pickup_distance_sort,
      (select a.expires_at from public.ride_dispatch_attempts a
        where a.ride_request_id=r.id and a.driver_id=v_uid
          and a.status='pending' and a.expires_at>now()
        limit 1) as fixed_attempt_expires_at
    from public.ride_requests r
    where r.status in ('searching','offers_received')
      and r.expires_at > now()
      and r.passenger_id <> v_uid
      and r.zone_id = v_zone_id
      and public.same_operational_scope(r.passenger_id,v_uid)
      and (r.service_mode <> 'parcel' or public.parcel_driver_can_carry(v_uid,r.id))
      and public.driver_vehicle_supports_ride(v_uid,r.id)
      and (
        r.dispatch_style = 'bidding'
        or exists(
          select 1 from public.ride_dispatch_attempts a
          where a.ride_request_id=r.id and a.driver_id=v_uid
            and a.status='pending' and a.expires_at>now())
      )
      and (
        r.scheduled_for is null
        or r.scheduled_for <=
          now()+make_interval(
            mins=>least(greatest(v_scheduled_before,5),1440)
          )
      )
      and (
        r.scheduled_for is not null
        or r.dispatch_ring_km is not null
        or r.dispatch_style = 'sequential'
        or r.created_at >
          now()-make_interval(
            secs=>least(greatest(v_visible_seconds,30),1800)
          )
      )
      and exists(
        select 1
        from public.zone_service_catalog zs
        where zs.zone_id=v_zone_id
          and zs.service_key=r.category
          and zs.enabled=true
          and zs.driver_visible=true
      )
      and case when r.service_mode='parcel' then
        public.driver_work_permission_allowed(
          v_uid,'parcel',public.admin_user_runtime_environment(v_uid))
        and public.express_parcel_zone_available(v_zone_id,r.channel,'driver')
      else
        public.driver_work_permission_allowed(
          v_uid,'ride',public.admin_user_runtime_environment(v_uid))
      end
      and r.pickup_latitude is not null
      and r.pickup_longitude is not null
      and public.geo_distance_km(v_lat,v_lng,r.pickup_latitude,r.pickup_longitude)
          <= least(greatest(coalesce(r.dispatch_ring_km, v_radius),1),100)
    order by pickup_distance_sort asc, r.created_at asc
    limit v_limit
  ) x;

  return v_result;
end
$$;

-- Revisión cada 5 segundos: pasa al siguiente conductor si venció el tiempo.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'fixed-dispatch-tick') then
    perform cron.unschedule('fixed-dispatch-tick');
  end if;
  perform cron.schedule('fixed-dispatch-tick', '5 seconds', 'select public.fixed_dispatch_tick_all_v1()');
end $$;
