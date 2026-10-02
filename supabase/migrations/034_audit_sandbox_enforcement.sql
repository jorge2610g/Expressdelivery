-- Enforcement del sandbox de auditoría en viajes, ofertas, Realtime,
-- notificaciones push, mapa de conductores y delivery.

drop policy if exists rides_read_available_for_drivers on public.ride_requests;
create policy rides_read_available_for_drivers
on public.ride_requests
for select
to authenticated
using (
  passenger_id = (select auth.uid())
  or (
    status in ('searching','offers_received')
    and public.is_approved_online_driver((select auth.uid()))
    and public.same_operational_scope(passenger_id, (select auth.uid()))
  )
  or exists (
    select 1
    from public.trips t
    where t.ride_request_id = ride_requests.id
      and t.driver_id = (select auth.uid())
  )
);

drop policy if exists offers_insert_approved_driver on public.driver_offers;
create policy offers_insert_approved_driver
on public.driver_offers
for insert
to authenticated
with check (
  driver_id = (select auth.uid())
  and public.is_approved_online_driver((select auth.uid()))
  and public.ride_request_is_open(ride_request_id)
  and not public.is_ride_request_passenger(ride_request_id, (select auth.uid()))
  and public.ride_request_matches_user_scope(ride_request_id, (select auth.uid()))
);

drop policy if exists offers_update_driver on public.driver_offers;
create policy offers_update_driver
on public.driver_offers
for update
to authenticated
using (
  driver_id = (select auth.uid())
  and not public.is_ride_request_passenger(ride_request_id, (select auth.uid()))
  and public.ride_request_matches_user_scope(ride_request_id, (select auth.uid()))
)
with check (
  driver_id = (select auth.uid())
  and not public.is_ride_request_passenger(ride_request_id, (select auth.uid()))
  and public.ride_request_matches_user_scope(ride_request_id, (select auth.uid()))
);

drop policy if exists deliveries_read_participants_or_available on public.delivery_requests;
create policy deliveries_read_participants_or_available
on public.delivery_requests
for select
to authenticated
using (
  customer_id = (select auth.uid())
  or courier_id = (select auth.uid())
  or (
    status = 'searching'
    and public.is_approved_online_driver((select auth.uid()))
    and public.same_operational_scope(customer_id, (select auth.uid()))
  )
);

drop policy if exists deliveries_update_participants on public.delivery_requests;
create policy deliveries_update_participants
on public.delivery_requests
for update
to authenticated
using (
  customer_id = (select auth.uid())
  or courier_id = (select auth.uid())
  or (
    courier_id is null
    and status = 'searching'
    and public.is_approved_online_driver((select auth.uid()))
    and public.same_operational_scope(customer_id, (select auth.uid()))
  )
)
with check (
  (
    customer_id = (select auth.uid())
    and (courier_id is null or courier_id = (select auth.uid()))
  )
  or (
    courier_id = (select auth.uid())
    and public.same_operational_scope(customer_id, (select auth.uid()))
  )
);

create or replace function public.available_ride_requests_for_driver()
returns jsonb
language plpgsql
stable security definer
set search_path=public
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
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if not public.is_approved_online_driver(v_uid) then
    return '[]'::jsonb;
  end if;

  select
    coalesce(scheduled_publish_before_minutes,30),
    coalesce(request_visible_seconds,180),
    coalesce(max_visible_requests_driver,20),
    coalesce(max_driver_request_radius_km,15)
  into v_scheduled_before,v_visible_seconds,v_max_visible,v_radius
  from public.app_settings
  where id=true;

  select latitude,longitude into v_lat,v_lng
  from public.driver_profiles where id=v_uid limit 1;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc),'[]'::jsonb)
  into v_result
  from (
    select r.*
    from public.ride_requests r
    where r.status in ('searching','offers_received')
      and r.expires_at > now()
      and r.passenger_id <> v_uid
      and public.same_operational_scope(r.passenger_id, v_uid)
      and (
        r.scheduled_for is null
        or r.scheduled_for <=
          now() + make_interval(mins => least(greatest(v_scheduled_before,5),1440))
      )
      and (
        r.scheduled_for is not null
        or r.created_at >
          now() - make_interval(secs => least(greatest(v_visible_seconds,30),1800))
      )
      and exists (
        select 1
        from public.service_catalog c
        where c.service_key=r.category
          and c.enabled=true
          and c.driver_visible=true
      )
      and (
        v_lat is null
        or v_lng is null
        or r.pickup_latitude is null
        or r.pickup_longitude is null
        or (
          111.195 * sqrt(
            power((r.pickup_latitude - v_lat)::double precision,2) +
            power(
              ((r.pickup_longitude - v_lng)::double precision) *
              cos(radians(((r.pickup_latitude + v_lat) / 2)::double precision)),
              2
            )
          )
        ) <= least(greatest(v_radius,1),100)
      )
    order by r.created_at asc
    limit least(greatest(v_max_visible,1),100)
  ) x;

  return v_result;
end;
$$;

create or replace function public.mark_ride_requests_viewed(p_ride_request_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if not public.is_approved_online_driver(auth.uid()) then
    raise exception 'Conductor no disponible';
  end if;

  insert into public.ride_request_views (ride_request_id, driver_id, viewed_at)
  select r.id, auth.uid(), now()
  from public.ride_requests r
  where r.id = any(p_ride_request_ids)
    and r.status in ('searching','offers_received')
    and coalesce(r.expires_at, now() + interval '1 second') > now()
    and public.same_operational_scope(r.passenger_id, auth.uid())
  on conflict (ride_request_id, driver_id)
  do update set viewed_at = excluded.viewed_at;
end;
$$;

create or replace function public.nearby_online_driver_markers(
  p_lat numeric,
  p_lng numeric,
  p_radius_km numeric default 5
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  with candidates as (
    select
      round(dp.latitude::numeric, 3) as latitude,
      round(dp.longitude::numeric, 3) as longitude,
      coalesce(
        (select dv.vehicle_type from public.driver_vehicles dv
         where dv.driver_id = dp.id and dv.is_active = true
         order by dv.updated_at desc limit 1),
        case
          when lower(coalesce(dp.vehicle_summary,'')) like '%moto%' then 'motorcycle'
          when lower(coalesce(dp.vehicle_summary,'')) like '%xl%' then 'xl'
          else 'car'
        end
      ) as vehicle_type,
      (
        6371 * acos(
          least(1, greatest(-1,
            cos(radians(p_lat::double precision))
            * cos(radians(dp.latitude::double precision))
            * cos(radians(dp.longitude::double precision) - radians(p_lng::double precision))
            + sin(radians(p_lat::double precision))
            * sin(radians(dp.latitude::double precision))
          ))
        )
      ) as distance_km
    from public.driver_profiles dp
    where dp.approval_status = 'approved'
      and dp.online_status = 'online'
      and dp.latitude is not null
      and dp.longitude is not null
      and public.same_operational_scope(v_uid, dp.id)
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'latitude', latitude,
        'longitude', longitude,
        'vehicle_type', vehicle_type,
        'distance_km', round(distance_km::numeric, 1)
      )
      order by distance_km
    ),
    '[]'::jsonb
  )
  into v_result
  from (
    select * from candidates
    where distance_km <= greatest(0.5, least(coalesce(p_radius_km, 5), 20))
    order by distance_km
    limit 12
  ) q;
  return v_result;
end;
$$;

create or replace function public.nearby_online_driver_markers(
  p_lat numeric,
  p_lng numeric,
  p_radius_km numeric default 5,
  p_vehicle_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_requested text := nullif(lower(trim(coalesce(p_vehicle_type, ''))), '');
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  with candidates as (
    select
      round(dp.latitude::numeric, 3) as latitude,
      round(dp.longitude::numeric, 3) as longitude,
      coalesce(
        (select dv.vehicle_type from public.driver_vehicles dv
         where dv.driver_id = dp.id and dv.is_active = true
         order by dv.updated_at desc limit 1),
        case
          when lower(coalesce(dp.vehicle_summary,'')) like '%moto%' then 'motorcycle'
          when lower(coalesce(dp.vehicle_summary,'')) like '%xl%' then 'xl'
          else 'car'
        end
      ) as vehicle_type,
      (
        6371 * acos(
          least(1, greatest(-1,
            cos(radians(p_lat::double precision))
            * cos(radians(dp.latitude::double precision))
            * cos(radians(dp.longitude::double precision) - radians(p_lng::double precision))
            + sin(radians(p_lat::double precision))
            * sin(radians(dp.latitude::double precision))
          ))
        )
      ) as distance_km
    from public.driver_profiles dp
    where dp.approval_status = 'approved'
      and dp.online_status = 'online'
      and dp.latitude is not null
      and dp.longitude is not null
      and public.same_operational_scope(v_uid, dp.id)
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'latitude', latitude,
        'longitude', longitude,
        'vehicle_type', vehicle_type,
        'distance_km', round(distance_km::numeric, 1)
      )
      order by distance_km
    ),
    '[]'::jsonb
  )
  into v_result
  from (
    select * from candidates
    where distance_km <= greatest(0.5, least(coalesce(p_radius_km, 5), 20))
      and (v_requested is null or vehicle_type = v_requested)
    order by distance_km
    limit 16
  ) q;
  return v_result;
end;
$$;

create or replace function public.notify_available_ride_to_drivers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver record;
  v_lock_driver uuid;
begin
  if new.status <> 'searching' then return new; end if;

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

  for v_driver in
    select
      dp.id,
      case
        when new.pickup_latitude is null or new.pickup_longitude is null
          or dp.latitude is null or dp.longitude is null
        then null::double precision
        else 6371 * acos(
          least(1, greatest(-1,
            cos(radians(new.pickup_latitude::double precision))
            * cos(radians(dp.latitude::double precision))
            * cos(radians(dp.longitude::double precision)
                  - radians(new.pickup_longitude::double precision))
            + sin(radians(new.pickup_latitude::double precision))
            * sin(radians(dp.latitude::double precision))
          ))
        )
      end as distance_km
    from public.driver_profiles dp
    where dp.approval_status = 'approved'
      and dp.online_status = 'online'
      and dp.id <> new.passenger_id
      and public.same_operational_scope(dp.id, new.passenger_id)
      and (
        new.pickup_latitude is null or new.pickup_longitude is null
        or dp.latitude is null or dp.longitude is null
        or 6371 * acos(
          least(1, greatest(-1,
            cos(radians(new.pickup_latitude::double precision))
            * cos(radians(dp.latitude::double precision))
            * cos(radians(dp.longitude::double precision)
                  - radians(new.pickup_longitude::double precision))
            + sin(radians(new.pickup_latitude::double precision))
            * sin(radians(dp.latitude::double precision))
          ))
        ) <= 10
      )
    order by distance_km nulls last, dp.updated_at desc nulls last
  loop
    v_lock_driver := null;

    insert into public.driver_request_push_locks(
      driver_id, ride_request_id, locked_until, updated_at
    )
    values(v_driver.id, new.id, now() + interval '15 seconds', now())
    on conflict (driver_id)
    do update set
      ride_request_id = excluded.ride_request_id,
      locked_until = excluded.locked_until,
      updated_at = now()
    where public.driver_request_push_locks.locked_until <= now()
    returning driver_id into v_lock_driver;

    if v_lock_driver is null then continue; end if;

    insert into public.notifications(user_id, title, body, type)
    values(
      v_driver.id,
      'Nueva solicitud disponible',
      'Tienes una nueva solicitud cercana. Abre Express para verla.',
      'ride_request'
    );
  end loop;

  return new;
end;
$$;

create or replace function public.notify_ride_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger uuid;
  v_driver_name text;
  v_amount text;
begin
  select r.passenger_id into v_passenger
  from public.ride_requests r
  where r.id = new.ride_request_id;

  if v_passenger is null then return new; end if;
  if new.driver_id = v_passenger then
    raise exception 'No puedes ofertar en tu propia solicitud';
  end if;
  if not public.same_operational_scope(v_passenger, new.driver_id) then
    raise exception 'Solicitud fuera de tu entorno operativo';
  end if;
  if new.status <> 'pending' then return new; end if;

  if tg_op = 'UPDATE'
     and old.status = 'pending'
     and old.proposed_fare is not distinct from new.proposed_fare
     and old.eta_minutes is not distinct from new.eta_minutes
     and old.expires_at is not distinct from new.expires_at then
    return new;
  end if;

  update public.ride_requests
  set status = 'offers_received', updated_at = now()
  where id = new.ride_request_id and status = 'searching';

  select nullif(trim(u.full_name), '') into v_driver_name
  from public.users u where u.id = new.driver_id;

  v_amount := trim(to_char(new.proposed_fare, 'FM999999990.00'));

  insert into public.notifications(user_id, title, body, type)
  values(
    v_passenger,
    'Nueva oferta de conductor',
    coalesce(v_driver_name, 'Un conductor') ||
      ' te ofrece Bs ' || v_amount || '. Revisa la oferta en Express.',
    'ride_offer'
  );

  return new;
end;
$$;

create or replace function public.select_ride_offer(p_offer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ride_id uuid;
  v_driver_id uuid;
  v_passenger_id uuid;
  v_fare numeric;
  v_trip_id uuid;
  v_pin text;
  v_driver_name text;
  v_amount text;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;

  update public.driver_offers
  set status = 'expired'
  where id = p_offer_id
    and status = 'pending'
    and expires_at is not null
    and expires_at <= now();

  select o.ride_request_id, o.driver_id, r.passenger_id, o.proposed_fare
    into v_ride_id, v_driver_id, v_passenger_id, v_fare
  from public.driver_offers o
  join public.ride_requests r on r.id = o.ride_request_id
  where o.id = p_offer_id
    and r.passenger_id = auth.uid()
    and o.status = 'pending'
    and (o.expires_at is null or o.expires_at > now())
    and r.status in ('searching','offers_received')
  for update of o, r;

  if v_ride_id is null then
    raise exception 'Oferta vencida o no disponible';
  end if;
  if v_driver_id = v_passenger_id then
    raise exception 'No puedes asignarte tu propia solicitud';
  end if;
  if not public.same_operational_scope(v_passenger_id, v_driver_id) then
    raise exception 'Oferta fuera de tu entorno operativo';
  end if;

  select nullif(trim(u.full_name), '') into v_driver_name
  from public.users u where u.id = v_driver_id;
  v_amount := trim(to_char(v_fare, 'FM999999990.00'));

  insert into public.notifications(user_id, title, body, type)
  select distinct
    o.driver_id,
    'Oferta no seleccionada',
    'Este viaje fue asignado a otro conductor.',
    'ride_offer_declined'
  from public.driver_offers o
  where o.ride_request_id = v_ride_id
    and o.status = 'pending'
    and o.id <> p_offer_id
    and o.driver_id <> v_driver_id
    and public.same_operational_scope(v_passenger_id, o.driver_id);

  update public.driver_offers
  set status = case when id = p_offer_id then 'selected' else 'declined' end
  where ride_request_id = v_ride_id and status = 'pending';

  update public.ride_requests
  set status = 'driver_selected', updated_at = now()
  where id = v_ride_id;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');

  insert into public.trips(
    ride_request_id, passenger_id, driver_id, status, final_fare,
    payment_status, boarding_pin
  )
  values(
    v_ride_id, v_passenger_id, v_driver_id, 'driver_arriving', v_fare,
    'pending', v_pin
  )
  returning id into v_trip_id;

  insert into public.trip_status_history(trip_id, status, changed_by)
  values(v_trip_id, 'driver_arriving', auth.uid());

  update public.driver_profiles
  set online_status = 'busy', updated_at = now()
  where id = v_driver_id;

  insert into public.notifications(user_id, title, body, type)
  values
    (
      v_driver_id,
      '¡Viaje confirmado!',
      'Tu oferta de Bs ' || v_amount ||
        ' fue aceptada. Ya estás en camino al punto de recogida.',
      'ride_assigned'
    ),
    (
      v_passenger_id,
      'Conductor confirmado',
      coalesce(v_driver_name, 'Tu conductor') ||
        ' fue asignado y ya va en camino. Sigue su llegada en el mapa.',
      'ride_assigned'
    );

  return v_trip_id;
end;
$$;

create or replace function public.claim_delivery(p_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer uuid;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists(
    select 1 from public.driver_profiles dp
    where dp.id = auth.uid()
      and dp.approval_status = 'approved'
      and dp.online_status in ('online','busy')
  ) then
    raise exception 'Conductor no aprobado o fuera de línea';
  end if;

  select customer_id into v_customer
  from public.delivery_requests
  where id = p_delivery_id
    and courier_id is null
    and status = 'searching'
  for update;

  if v_customer is null
     or not public.same_operational_scope(v_customer, auth.uid()) then
    raise exception 'Delivery no disponible en tu entorno';
  end if;

  update public.delivery_requests
  set courier_id = auth.uid(), status = 'accepted', updated_at = now()
  where id = p_delivery_id
    and customer_id = v_customer
    and courier_id is null
    and status = 'searching';

  if not found then raise exception 'Delivery no disponible'; end if;

  insert into public.delivery_status_history(delivery_id, status, changed_by)
  values(p_delivery_id, 'accepted', auth.uid());
end;
$$;
