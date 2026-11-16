-- Búsqueda de conductores por anillos (1 km, 2 km, 3 km…).
--
-- Cada solicitud empieza con un anillo de radio 1 km alrededor del pasajero.
-- Solo ven la solicitud, en el pop-up y en la lista de viajes, los conductores
-- que están dentro del anillo actual. Cada anillo dura dispatch_ring_seconds
-- (30 s). Si nadie oferta en ese tiempo, un proceso cada 10 s amplía el anillo
-- en progressive_radius_step_km (1 km) hasta max_driver_request_radius_km (15 km),
-- y avisa solo a los conductores que entran en el anillo nuevo.
-- Mientras haya una oferta pendiente la búsqueda no se amplía, para que el
-- pasajero elija entre los conductores cercanos.
--
-- Cambios:
--  * app_settings: dispatch_mode 'progressive', anillo inicial 1 km, paso 1 km,
--    30 s por anillo (nueva columna dispatch_ring_seconds).
--  * ride_requests: dispatch_ring_km y dispatch_ring_started_at. Las solicitudes
--    anteriores (sin anillo) siguen con el comportamiento de antes.
--  * Aviso al crear la solicitud: solo conductores dentro del anillo inicial,
--    y sin conductores sin ubicación (antes podían recibirla sin saber dónde están).
--  * Lista del conductor: solo solicitudes de su anillo, más cercanas primero
--    (antes iban por antigüedad), y sin mostrar nada a quien no tenga ubicación.
--  * Ofertas al pasajero: ordenadas por distancia, con driver_distance_km.
--  * Oferta del conductor: solo dentro del anillo actual (con 200 m de margen
--    por el GPS). Esto se controla en la base, no solo en la app.

alter table public.app_settings
  add column if not exists dispatch_ring_seconds integer not null default 30;

update public.app_settings
   set dispatch_mode = 'progressive',
       dispatch_radius_km = 1,
       progressive_radius_step_km = 1,
       dispatch_ring_seconds = 30
 where id = true;

alter table public.ride_requests
  add column if not exists dispatch_ring_km numeric,
  add column if not exists dispatch_ring_started_at timestamptz;

-- Anillo inicial al crear la solicitud (solo en modo progresivo y con pickup).
create or replace function public.set_ride_dispatch_ring()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_mode text;
  v_first numeric;
  v_max numeric;
begin
  select dispatch_mode,
         coalesce(dispatch_radius_km, 1),
         coalesce(max_driver_request_radius_km, 15)
    into v_mode, v_first, v_max
  from public.app_settings
  where id = true;

  if v_mode = 'progressive'
     and new.pickup_latitude is not null
     and new.pickup_longitude is not null then
    new.dispatch_ring_km := least(greatest(v_first, 0.5), v_max);
    new.dispatch_ring_started_at := now();
  end if;
  return new;
end
$function$;

drop trigger if exists zz_set_ride_dispatch_ring on public.ride_requests;
create trigger zz_set_ride_dispatch_ring
  before insert on public.ride_requests
  for each row execute function public.set_ride_dispatch_ring();

-- Conductores elegibles para una solicitud a una distancia dentro de (min, max].
-- Mismas reglas de elegibilidad que el aviso anterior, más ubicación obligatoria.
create or replace function public.ride_dispatch_candidates(
  p_request public.ride_requests,
  p_min_km numeric,
  p_max_km numeric
)
returns table(driver_id uuid, distance_km numeric)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  return query
  select dp.id,
         public.geo_distance_km(
           p_request.pickup_latitude, p_request.pickup_longitude,
           dp.latitude, dp.longitude)::numeric
  from public.driver_profiles dp
  join public.users u on u.id = dp.id
  where dp.approval_status = 'approved'
    and dp.online_status = 'online'
    and u.account_status = 'active'
    and u.active_mode = 'driver'
    and dp.id <> p_request.passenger_id
    and dp.zone_id = p_request.zone_id
    and public.same_operational_scope(dp.id, p_request.passenger_id)
    and (p_request.service_mode <> 'parcel' or public.parcel_driver_can_carry(dp.id, p_request.id))
    and public.driver_subscription_allows_dispatch(dp.id)
    and (p_request.service_mode <> 'parcel' or (
      public.express_parcel_zone_available(p_request.zone_id, p_request.channel, 'driver')
      and public.admin_user_runtime_environment(dp.id) = p_request.channel
      and exists (
        select 1 from public.driver_work_permissions g
        where g.driver_id = dp.id and g.zone_id = dp.zone_id
          and g.channel = p_request.channel and g.service_key = 'parcel'
          and g.status = 'approved'
      )
    ))
    and exists (
      select 1 from public.zone_service_catalog zs
      where zs.zone_id = p_request.zone_id
        and zs.service_key = p_request.category
        and zs.enabled = true
        and zs.driver_visible = true
    )
    and dp.latitude is not null
    and dp.longitude is not null
    and (p_min_km <= 0 or public.geo_distance_km(
          p_request.pickup_latitude, p_request.pickup_longitude,
          dp.latitude, dp.longitude) > p_min_km)
    and public.geo_distance_km(
          p_request.pickup_latitude, p_request.pickup_longitude,
          dp.latitude, dp.longitude) <= p_max_km
  order by 2 asc, dp.updated_at desc nulls last;
end
$function$;

-- Envía el aviso a los candidatos de un anillo (con el mismo bloqueo de 15 s por conductor).
create or replace function public.notify_ride_candidates(
  p_request public.ride_requests,
  p_min_km numeric,
  p_max_km numeric
)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_driver record;
  v_lock_driver uuid;
  v_count integer := 0;
begin
  for v_driver in
    select c.driver_id, c.distance_km
    from public.ride_dispatch_candidates(p_request, p_min_km, p_max_km) c
  loop
    v_lock_driver := null;

    insert into public.driver_request_push_locks(driver_id, ride_request_id, locked_until, updated_at)
    values (v_driver.driver_id, p_request.id, now() + interval '15 seconds', now())
    on conflict (driver_id)
    do update set
      ride_request_id = excluded.ride_request_id,
      locked_until = excluded.locked_until,
      updated_at = now()
    where public.driver_request_push_locks.locked_until <= now()
    returning driver_id into v_lock_driver;

    if v_lock_driver is null then continue; end if;

    insert into public.notifications(user_id, title, body, type, metadata)
    values (
      v_driver.driver_id,
      'Nueva solicitud disponible',
      'Tienes una nueva solicitud cercana. Abre Express para verla.',
      'ride_request',
      jsonb_build_object(
        'ride_request_id', p_request.id,
        'zone_id', p_request.zone_id,
        'mode', 'driver',
        'service_mode', p_request.service_mode,
        'deep_link', 'ride_request'
      )
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end
$function$;

-- Aviso al crear la solicitud: solo el anillo inicial.
create or replace function public.notify_available_ride_to_drivers()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_max numeric;
begin
  if new.status <> 'searching' then return new; end if;
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

  -- Sin ubicación del pasajero no hay anillo: no se avisa a nadie.
  if new.pickup_latitude is null or new.pickup_longitude is null then
    return new;
  end if;

  select coalesce(max_driver_request_radius_km, 15) into v_max
  from public.app_settings where id = true;

  perform public.notify_ride_candidates(
    new, 0, least(greatest(coalesce(new.dispatch_ring_km, v_max), 1), 100));
  return new;
end
$function$;

-- Amplía el anillo de las solicitudes que llevan dispatch_ring_seconds sin oferta.
create or replace function public.advance_ride_dispatch_rings()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r public.ride_requests%rowtype;
  v_max numeric;
  v_step numeric;
  v_seconds integer;
  v_new numeric;
  v_count integer := 0;
begin
  select coalesce(max_driver_request_radius_km, 15),
         greatest(coalesce(progressive_radius_step_km, 1), 0.5),
         greatest(coalesce(dispatch_ring_seconds, 30), 10)
    into v_max, v_step, v_seconds
  from public.app_settings where id = true;

  for r in
    select *
    from public.ride_requests
    where status = 'searching'
      and dispatch_ring_km is not null
      and dispatch_ring_km < v_max
      and dispatch_ring_started_at <= now() - make_interval(secs => v_seconds)
      and expires_at > now()
      and scheduled_for is null
      and pickup_latitude is not null
      and pickup_longitude is not null
      and not exists (
        select 1 from public.driver_offers o
        where o.ride_request_id = ride_requests.id and o.status = 'pending'
      )
    order by dispatch_ring_started_at
    for update skip locked
  loop
    v_new := least(r.dispatch_ring_km + v_step, v_max);
    update public.ride_requests
       set dispatch_ring_km = v_new,
           dispatch_ring_started_at = now()
     where id = r.id;

    perform public.notify_ride_candidates(r, r.dispatch_ring_km, v_new);
    v_count := v_count + 1;
  end loop;
  return v_count;
end
$function$;

revoke all on function public.advance_ride_dispatch_rings() from public, anon, authenticated;

select cron.unschedule('advance-ride-dispatch-rings')
  where exists (select 1 from cron.job where jobname = 'advance-ride-dispatch-rings');
select cron.schedule(
  'advance-ride-dispatch-rings',
  '10 seconds',
  $$select public.advance_ride_dispatch_rings()$$
);

-- Lista del conductor: solo su anillo, más cercanas primero.
create or replace function public.available_ride_requests_for_driver()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_scheduled_before integer := 30;
  v_visible_seconds integer := 180;
  v_max_visible integer := 20;
  v_radius numeric := 15;
  v_ring_seconds integer := 30;
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
    coalesce(max_driver_request_radius_km,15),
    coalesce(dispatch_ring_seconds,30)
  into v_scheduled_before, v_visible_seconds, v_max_visible, v_radius, v_ring_seconds
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

  -- Sin ubicación no se sabe en qué anillo está: no se muestra nada.
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
      public.geo_distance_km(v_lat,v_lng,r.pickup_latitude,r.pickup_longitude) as pickup_distance_sort
    from public.ride_requests r
    where r.status in ('searching','offers_received')
      and r.expires_at > now()
      and r.passenger_id <> v_uid
      and r.zone_id = v_zone_id
      and public.same_operational_scope(r.passenger_id,v_uid)
      and (r.service_mode <> 'parcel' or public.parcel_driver_can_carry(v_uid,r.id))
      and public.driver_vehicle_supports_ride(v_uid,r.id)
      and (
        r.scheduled_for is null
        or r.scheduled_for <=
          now()+make_interval(
            mins=>least(greatest(v_scheduled_before,5),1440)
          )
      )
      and (
        r.scheduled_for is not null
        or (
          r.dispatch_ring_km is not null
          and r.dispatch_ring_started_at >
            now()-make_interval(secs=>least(greatest(v_ring_seconds,10)+10,600))
        )
        or (
          r.dispatch_ring_km is null
          and r.created_at >
            now()-make_interval(
              secs=>least(greatest(v_visible_seconds,30),1800)
            )
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
$function$;

-- Ofertas al pasajero: las más cercanas primero, con la distancia al pasajero.
create or replace function public.passenger_pending_ride_offers(p_ride_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists (
    select 1
    from public.ride_requests r
    where r.id = p_ride_request_id
      and r.passenger_id = v_uid
  ) then
    raise exception 'Solicitud no disponible';
  end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(o) ||
      jsonb_build_object(
        'driver_distance_km', dist.km,
        'driver_profiles',
        jsonb_build_object(
          'id', dp.id,
          'rating', dp.rating,
          'completed_trips', dp.completed_trips,
          'vehicle_summary', dp.vehicle_summary,
          'city', dp.city,
          'profile_photo_path',
            case when public.can_view_driver_profile_photo(
              dp.id, dp.profile_photo_path)
            then dp.profile_photo_path else null end
        ),
        'driver_user',
        jsonb_build_object(
          'id', u.id,
          'full_name', u.full_name,
          'avatar_url', u.avatar_url
        )
      )
      order by dist.km asc nulls last, o.created_at asc
    ),
    '[]'::jsonb
  )
  into v_result
  from public.driver_offers o
  join public.ride_requests rq on rq.id = o.ride_request_id
  left join public.driver_profiles dp on dp.id = o.driver_id
  left join public.users u on u.id = o.driver_id
  cross join lateral (
    select round(
      public.geo_distance_km(
        rq.pickup_latitude, rq.pickup_longitude,
        dp.latitude, dp.longitude)::numeric,
      1) as km
  ) dist
  where o.ride_request_id = p_ride_request_id
    and o.status = 'pending'
    and coalesce(o.expires_at, now() + interval '1 second') > now();

  return v_result;
end
$function$;

-- Una oferta solo puede venir de un conductor dentro del anillo actual.
create or replace function public.guard_driver_offer_within_ring()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_req public.ride_requests%rowtype;
  v_lat numeric;
  v_lng numeric;
  v_km numeric;
begin
  select * into v_req
  from public.ride_requests
  where id = new.ride_request_id;

  if not found or v_req.dispatch_ring_km is null then
    return new;
  end if;

  select latitude, longitude into v_lat, v_lng
  from public.driver_profiles
  where id = new.driver_id;

  if v_lat is null or v_lng is null
     or v_req.pickup_latitude is null or v_req.pickup_longitude is null then
    raise exception 'Necesitas ubicación activa para ofertar en esta solicitud.';
  end if;

  v_km := public.geo_distance_km(
    v_req.pickup_latitude, v_req.pickup_longitude, v_lat, v_lng);
  if v_km > v_req.dispatch_ring_km + 0.2 then
    raise exception 'Esta solicitud no está en tu radio actual.';
  end if;
  return new;
end
$function$;

drop trigger if exists zz_guard_driver_offer_within_ring on public.driver_offers;
create trigger zz_guard_driver_offer_within_ring
  before insert or update of proposed_fare on public.driver_offers
  for each row execute function public.guard_driver_offer_within_ring();
