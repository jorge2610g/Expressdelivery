-- Persist cancellation reasons so history/detail screens can explain why a
-- request or assigned trip ended. Existing records remain null.

alter table public.ride_requests
  add column if not exists cancellation_reason text;

alter table public.trips
  add column if not exists cancellation_reason text;

create or replace function public.cancel_ride_request(
  p_ride_request_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_passenger uuid;
  v_status text;
  v_trip_id uuid;
  v_trip_status text;
  v_driver uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
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
    update public.ride_requests
    set cancellation_reason = coalesce(cancellation_reason, v_reason),
        updated_at = now()
    where id = p_ride_request_id;
    return;
  end if;

  if v_status in ('searching','offers_received') then
    update public.ride_requests
    set status = 'cancelled',
        cancellation_reason = v_reason,
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
      coalesce(v_reason, 'El pasajero canceló la solicitud de viaje.'),
      'ride_cancelled'
    from public.driver_offers o
    where o.ride_request_id = p_ride_request_id;

    insert into public.notifications(user_id, title, body, type)
    values (
      v_passenger,
      'Viaje cancelado',
      coalesce(v_reason, 'La solicitud fue cancelada.'),
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
      set status = 'cancelled',
          cancellation_reason = v_reason,
          updated_at = now()
      where id = p_ride_request_id;
      return;
    end if;

    if v_trip_status = 'cancelled' then
      update public.ride_requests
      set status = 'cancelled',
          cancellation_reason = coalesce(cancellation_reason, v_reason),
          updated_at = now()
      where id = p_ride_request_id;
      return;
    end if;

    if v_trip_status not in ('driver_assigned','driver_arriving','driver_waiting') then
      raise exception 'El viaje ya no se puede cancelar desde este estado';
    end if;

    update public.trips
    set status = 'cancelled',
        cancellation_reason = v_reason
    where id = v_trip_id;

    insert into public.trip_status_history(trip_id, status, changed_by)
    values (v_trip_id, 'cancelled', auth.uid());

    update public.ride_requests
    set status = 'cancelled',
        cancellation_reason = v_reason,
        updated_at = now()
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
        coalesce(v_reason, 'El pasajero canceló el viaje.'),
        'trip_cancelled'
      ),
      (
        v_passenger,
        'Viaje cancelado',
        coalesce(v_reason, 'El viaje fue cancelado.'),
        'trip_cancelled'
      );
    return;
  end if;

  raise exception 'La solicitud ya no se puede cancelar';
end;
$function$;

create or replace function public.cancel_trip(
  p_trip_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_passenger uuid;
  v_driver uuid;
  v_status text;
  v_other uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
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
    update public.trips
    set cancellation_reason = coalesce(cancellation_reason, v_reason)
    where id = p_trip_id;
    return;
  end if;

  if v_status not in ('driver_assigned','driver_arriving','driver_waiting') then
    raise exception 'El viaje ya no se puede cancelar desde este estado';
  end if;

  update public.trips
  set status = 'cancelled',
      cancellation_reason = v_reason
  where id = p_trip_id;

  insert into public.trip_status_history(trip_id, status, changed_by)
  values (p_trip_id, 'cancelled', auth.uid());

  update public.ride_requests r
  set status = 'cancelled',
      cancellation_reason = v_reason,
      updated_at = now()
  where r.id = (
    select ride_request_id
    from public.trips
    where id = p_trip_id
  );

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
      coalesce(v_reason, 'El viaje fue cancelado por la otra parte.'),
      'trip_cancelled'
    ),
    (
      auth.uid(),
      'Viaje cancelado',
      coalesce(v_reason, 'El viaje fue cancelado.'),
      'trip_cancelled'
    );
end;
$function$;
