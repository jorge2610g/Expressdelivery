-- PROCEDIMIENTO DE RECUPERACIÓN: restaura las definiciones anteriores a la v3.
-- Solo DDL. No modifica datos. Ejecutar en orden.
CREATE OR REPLACE FUNCTION public.enforce_driver_offer_deadline()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.created_at := coalesce(new.created_at, now());
  if new.status = 'pending' then
    new.expires_at := new.created_at + interval '15 seconds';
  end if;
  return new;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.enforce_driver_offer_minimum_lifetime()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'pending' then
    if new.expires_at is null
       or new.expires_at < now() + interval '30 seconds' then
      new.expires_at := now() + interval '30 seconds';
    end if;
  end if;
  return new;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.select_ride_offer(p_offer_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ride_id uuid;
  v_driver_id uuid;
  v_passenger_id uuid;
  v_fare numeric;
  v_trip_id uuid;
  v_pin text;
  v_driver_name text;
  v_amount text;
  v_mode text;
  v_currency text;
begin
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  update public.driver_offers
  set status = 'expired'
  where id = p_offer_id
    and status = 'pending'
    and expires_at is not null
    and expires_at <= now();

  select o.ride_request_id, o.driver_id, r.passenger_id, o.proposed_fare,
         r.service_mode, r.currency
    into v_ride_id, v_driver_id, v_passenger_id, v_fare,
         v_mode, v_currency
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

  select nullif(trim(u.full_name), '')
    into v_driver_name
  from public.users u
  where u.id = v_driver_id;

  v_amount := trim(to_char(v_fare, 'FM999999990.00'));

  insert into public.notifications(user_id, title, body, type)
  select distinct
    o.driver_id,
    'Oferta no seleccionada',
    case when v_mode='parcel'
      then 'Este envío fue asignado a otro repartidor.'
      else 'Este viaje fue asignado a otro conductor.' end,
    'ride_offer_declined'
  from public.driver_offers o
  where o.ride_request_id = v_ride_id
    and o.status = 'pending'
    and o.id <> p_offer_id
    and o.driver_id <> v_driver_id
    and public.same_operational_scope(v_passenger_id, o.driver_id);

  update public.driver_offers
  set status = case when id = p_offer_id then 'selected' else 'declined' end
  where ride_request_id = v_ride_id
    and status = 'pending';

  update public.ride_requests
  set status = 'driver_selected', updated_at = now()
  where id = v_ride_id;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');

  insert into public.trips (
    ride_request_id, passenger_id, driver_id, status, final_fare,
    payment_status, boarding_pin
  ) values (
    v_ride_id, v_passenger_id, v_driver_id, 'driver_arriving', v_fare,
    'pending', v_pin
  )
  returning id into v_trip_id;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (v_trip_id, 'driver_arriving', auth.uid());

  update public.driver_profiles
  set online_status = 'busy', updated_at = now()
  where id = v_driver_id;

  insert into public.notifications (user_id, title, body, type)
  values
    (
      v_driver_id,
      case when v_mode='parcel'
        then '¡Envío confirmado!' else '¡Viaje confirmado!' end,
      case when v_mode='parcel'
        then 'Tu oferta de ' || coalesce(v_currency,'CLP') || ' ' || v_amount ||
          ' fue aceptada. Ve a recoger el paquete.'
        else 'Tu oferta de ' || public.express_push_currency_label(v_currency) || v_amount ||
          ' fue aceptada. Ya estás en camino al punto de recogida.' end,
      'ride_assigned'
    ),
    (
      v_passenger_id,
      case when v_mode='parcel'
        then 'Repartidor asignado' else 'Conductor confirmado' end,
      case when v_mode='parcel'
        then coalesce(v_driver_name, 'Tu repartidor') ||
          ' aceptó el envío y va camino a recoger el paquete.'
        else coalesce(v_driver_name, 'Tu conductor') ||
          ' fue asignado y ya va en camino. Sigue su llegada en el mapa.' end,
      'ride_assigned'
    );

  return v_trip_id;
end;
$function$

;
drop function if exists public.driver_offer_expires_at(timestamptz, uuid);
