-- Aceptación directa de viaje con precio fijo: el servidor exige que el conductor esté
-- en línea, aprobado y en la zona de la solicitud. La app ya filtra estas solicitudes,
-- pero una llamada directa a la RPC podía saltarse ese filtro.
-- Solo agrega la validación; el resto de la lógica queda igual que la migración anterior.

begin;

create or replace function public.driver_accept_fixed_price_ride_v1(
  p_ride_request_id uuid,
  p_channel text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_channel text := public.normalize_runtime_channel(p_channel);
  v_ride public.ride_requests%rowtype;
  v_offer_id uuid;
  v_trip_id uuid;
  v_pin text;
  v_driver_name text;
  v_amount text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select * into v_ride
  from public.ride_requests r
  where r.id = p_ride_request_id
  for update;

  if not found then
    raise exception 'Solicitud no disponible';
  end if;
  if v_ride.channel is distinct from v_channel then
    raise exception 'Solicitud fuera del entorno seleccionado';
  end if;
  if v_ride.pricing_mode <> 'fixed' or coalesce(v_ride.benefit_discount_amount, 0) <= 0 then
    raise exception 'Esta solicitud no es de precio fijo';
  end if;
  if v_ride.service_mode = 'parcel' then
    raise exception 'Esta solicitud no es de viaje';
  end if;
  if v_ride.status not in ('searching', 'offers_received')
     or v_ride.expires_at is null or v_ride.expires_at <= now() then
    raise exception 'Solicitud vencida o no disponible';
  end if;
  if v_ride.passenger_id = v_uid then
    raise exception 'No puedes asignarte tu propia solicitud';
  end if;
  -- El conductor debe estar en línea, aprobado y en la zona de la solicitud.
  if not exists (
    select 1
    from public.driver_profiles dp
    where dp.id = v_uid
      and dp.online_status = 'online'
      and dp.approval_status = 'approved'
      and dp.zone_id = v_ride.zone_id
  ) then
    raise exception 'Solicitud no disponible para tu estado en línea o tu zona';
  end if;

  perform pg_advisory_xact_lock(hashtext('driver_trip:' || v_uid::text));
  if public.driver_has_active_trip(v_uid) then
    raise exception 'Tienes un viaje activo. Termínalo antes de aceptar otro.';
  end if;
  if not public.same_operational_scope(v_ride.passenger_id, v_uid) then
    raise exception 'Oferta fuera de tu entorno operativo';
  end if;

  perform set_config('app.runtime_channel', v_channel, true);

  insert into public.driver_offers (
    ride_request_id, driver_id, channel, proposed_fare, eta_minutes, status, created_at, expires_at
  )
  values (
    v_ride.id, v_uid, v_channel, v_ride.proposed_fare, null, 'selected',
    now(), now() + interval '1 minute'
  )
  on conflict (ride_request_id, driver_id) do update set
    status = 'selected',
    proposed_fare = excluded.proposed_fare,
    channel = excluded.channel,
    eta_minutes = null,
    created_at = excluded.created_at,
    expires_at = excluded.expires_at
  returning id into v_offer_id;

  select nullif(trim(u.full_name), '') into v_driver_name
  from public.users u
  where u.id = v_uid;

  v_amount := trim(to_char(v_ride.proposed_fare, 'FM999999990.00'));

  insert into public.notifications(user_id, title, body, type)
  select distinct o.driver_id,
    'Oferta no seleccionada',
    'Este viaje fue asignado a otro conductor.',
    'ride_offer_declined'
  from public.driver_offers o
  where o.ride_request_id = v_ride.id
    and o.status = 'pending'
    and o.id <> v_offer_id
    and o.driver_id <> v_uid
    and public.same_operational_scope(v_ride.passenger_id, o.driver_id);

  update public.driver_offers
  set status = 'declined'
  where ride_request_id = v_ride.id
    and status = 'pending'
    and id <> v_offer_id;

  update public.ride_requests
  set status = 'driver_selected', updated_at = now()
  where id = v_ride.id;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');

  insert into public.trips (
    ride_request_id, passenger_id, driver_id, status, final_fare,
    payment_status, boarding_pin
  )
  values (
    v_ride.id, v_ride.passenger_id, v_uid, 'driver_arriving', v_ride.proposed_fare,
    'pending', v_pin
  )
  returning id into v_trip_id;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (v_trip_id, 'driver_arriving', v_uid);

  update public.driver_profiles
  set online_status = 'busy', updated_at = now()
  where id = v_uid;

  insert into public.notifications (user_id, title, body, type)
  values
    (
      v_uid,
      '¡Viaje confirmado!',
      'Viaje con precio fijo de ' || public.express_push_currency_label(v_ride.currency) || v_amount ||
        '. Ya estás en camino al punto de recogida.',
      'ride_assigned'
    ),
    (
      v_ride.passenger_id,
      'Conductor confirmado',
      coalesce(v_driver_name, 'Tu conductor') ||
        ' fue asignado y ya va en camino. Sigue su llegada en el mapa.',
      'ride_assigned'
    );

  return v_trip_id;
end;
$$;

revoke all on function public.driver_accept_fixed_price_ride_v1(uuid, text) from public, anon;
grant execute on function public.driver_accept_fixed_price_ride_v1(uuid, text) to authenticated;

commit;
