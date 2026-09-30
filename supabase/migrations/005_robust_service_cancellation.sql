-- Robust cancellation for ride requests, trips and deliveries.
-- Applied to production Supabase on 2026-09-30.

create or replace function public.cancel_ride_request(
  p_ride_request_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger uuid;
  v_status text;
  v_trip_id uuid;
  v_trip_status text;
  v_driver uuid;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select passenger_id, status
    into v_passenger, v_status
  from public.ride_requests
  where id = p_ride_request_id
  for update;

  if v_passenger is null or v_passenger <> auth.uid() then
    raise exception 'No autorizado';
  end if;

  if v_status = 'cancelled' then
    return;
  end if;

  if v_status in ('searching','offers_received') then
    update public.ride_requests
    set status = 'cancelled',
        updated_at = now()
    where id = p_ride_request_id;

    update public.driver_offers
    set status = 'declined'
    where ride_request_id = p_ride_request_id
      and status = 'pending';

    insert into public.notifications(user_id, title, body, type)
    select distinct
      o.driver_id,
      'Solicitud cancelada',
      coalesce(nullif(trim(p_reason), ''), 'El pasajero canceló la solicitud de viaje.'),
      'ride_cancelled'
    from public.driver_offers o
    where o.ride_request_id = p_ride_request_id;

    insert into public.notifications(user_id, title, body, type)
    values (
      v_passenger,
      'Viaje cancelado',
      coalesce(nullif(trim(p_reason), ''), 'La solicitud fue cancelada.'),
      'ride_cancelled'
    );
    return;
  end if;

  if v_status = 'driver_selected' then
    select id, status, driver_id
      into v_trip_id, v_trip_status, v_driver
    from public.trips
    where ride_request_id = p_ride_request_id
    order by created_at desc
    limit 1
    for update;

    if v_trip_id is null then
      update public.ride_requests
      set status = 'cancelled', updated_at = now()
      where id = p_ride_request_id;
      return;
    end if;

    if v_trip_status = 'cancelled' then
      update public.ride_requests
      set status = 'cancelled', updated_at = now()
      where id = p_ride_request_id;
      return;
    end if;

    if v_trip_status not in ('driver_assigned','driver_arriving','driver_waiting') then
      raise exception 'El viaje ya no se puede cancelar desde este estado';
    end if;

    update public.trips
    set status = 'cancelled'
    where id = v_trip_id;

    insert into public.trip_status_history(trip_id, status, changed_by)
    values (v_trip_id, 'cancelled', auth.uid());

    update public.ride_requests
    set status = 'cancelled', updated_at = now()
    where id = p_ride_request_id;

    update public.driver_profiles
    set online_status = 'online', updated_at = now()
    where id = v_driver
      and approval_status = 'approved';

    insert into public.notifications(user_id, title, body, type)
    values
      (
        v_driver,
        'Viaje cancelado',
        coalesce(nullif(trim(p_reason), ''), 'El pasajero canceló el viaje.'),
        'trip_cancelled'
      ),
      (
        v_passenger,
        'Viaje cancelado',
        coalesce(nullif(trim(p_reason), ''), 'El viaje fue cancelado.'),
        'trip_cancelled'
      );
    return;
  end if;

  raise exception 'La solicitud ya no se puede cancelar';
end;
$$;

create or replace function public.cancel_trip(
  p_trip_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger uuid;
  v_driver uuid;
  v_status text;
  v_other uuid;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select passenger_id, driver_id, status
    into v_passenger, v_driver, v_status
  from public.trips
  where id = p_trip_id
  for update;

  if auth.uid() not in (v_passenger, v_driver) then
    raise exception 'No autorizado';
  end if;

  if v_status = 'cancelled' then
    return;
  end if;

  if v_status not in ('driver_assigned','driver_arriving','driver_waiting') then
    raise exception 'El viaje ya no se puede cancelar desde este estado';
  end if;

  update public.trips
  set status = 'cancelled'
  where id = p_trip_id;

  insert into public.trip_status_history(trip_id, status, changed_by)
  values (p_trip_id, 'cancelled', auth.uid());

  update public.ride_requests r
  set status = 'cancelled',
      updated_at = now()
  where r.id = (select ride_request_id from public.trips where id = p_trip_id);

  update public.driver_profiles
  set online_status = 'online',
      updated_at = now()
  where id = v_driver
    and approval_status = 'approved';

  v_other := case when auth.uid() = v_passenger then v_driver else v_passenger end;

  insert into public.notifications(user_id, title, body, type)
  values
    (
      v_other,
      'Viaje cancelado',
      coalesce(nullif(trim(p_reason), ''), 'El viaje fue cancelado por la otra parte.'),
      'trip_cancelled'
    ),
    (
      auth.uid(),
      'Viaje cancelado',
      coalesce(nullif(trim(p_reason), ''), 'El viaje fue cancelado.'),
      'trip_cancelled'
    );
end;
$$;

create or replace function public.cancel_delivery(
  p_delivery_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer uuid;
  v_courier uuid;
  v_status text;
  v_other uuid;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select customer_id, courier_id, status
    into v_customer, v_courier, v_status
  from public.delivery_requests
  where id = p_delivery_id
  for update;

  if auth.uid() <> v_customer and (v_courier is null or auth.uid() <> v_courier) then
    raise exception 'No autorizado';
  end if;

  if v_status = 'cancelled' then
    return;
  end if;

  if auth.uid() = v_customer and v_status not in ('searching','accepted') then
    raise exception 'El cliente ya no puede cancelar este delivery';
  end if;

  if v_courier is not null and auth.uid() = v_courier and v_status <> 'accepted' then
    raise exception 'El repartidor ya no puede cancelar este delivery';
  end if;

  update public.delivery_requests
  set status = 'cancelled',
      updated_at = now()
  where id = p_delivery_id;

  insert into public.delivery_status_history(delivery_id, status, changed_by)
  values (p_delivery_id, 'cancelled', auth.uid());

  if v_courier is not null then
    update public.driver_profiles
    set online_status = 'online',
        updated_at = now()
    where id = v_courier
      and approval_status = 'approved';

    v_other := case when auth.uid() = v_customer then v_courier else v_customer end;

    insert into public.notifications(user_id, title, body, type)
    values (
      v_other,
      'Delivery cancelado',
      coalesce(nullif(trim(p_reason), ''), 'El delivery fue cancelado por la otra parte.'),
      'delivery_cancelled'
    );
  end if;

  insert into public.notifications(user_id, title, body, type)
  values (
    auth.uid(),
    'Delivery cancelado',
    coalesce(nullif(trim(p_reason), ''), 'El delivery fue cancelado.'),
    'delivery_cancelled'
  );
end;
$$;
