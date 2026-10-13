-- Express 2026-10-13: use the same Taxi trips engine, with parcel-specific
-- pickup validation and customer/driver status terminology.
-- Taxi PIN validation remains unchanged in start_trip_with_pin.
create or replace function public.confirm_parcel_pickup_v2(
 p_trip_id uuid,p_channel text default 'production'
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_driver uuid; v_passenger uuid; v_status text;
  v_mode text; v_zone uuid; v_trip_channel text;
begin
  if auth.uid() is null then raise exception 'Sesión no válida'; end if;
  select t.driver_id,t.passenger_id,t.status,r.service_mode,
         r.zone_id,t.channel
    into v_driver,v_passenger,v_status,v_mode,v_zone,v_trip_channel
  from public.trips t join public.ride_requests r on r.id=t.ride_request_id
  where t.id=p_trip_id for update of t;

  if not found or v_driver is distinct from auth.uid()
     or v_trip_channel is distinct from v_channel
     or public.admin_user_runtime_environment(v_driver) is distinct from v_channel
  then raise exception 'Envío fuera de tu entorno o conductor incorrecto'; end if;
  if v_mode is distinct from 'parcel' or v_status<>'driver_waiting' then
    raise exception 'Solo puedes confirmar un paquete pendiente de recogida';
  end if;
  if not public.driver_work_permission_allowed(v_driver,'parcel',v_channel)
     or not public.express_parcel_zone_available(v_zone,v_channel,'driver')
  then raise exception 'Servicio de Envíos no autorizado'; end if;

  update public.trips set status='in_progress' where id=p_trip_id;
  insert into public.trip_status_history(trip_id,status,changed_by)
    values(p_trip_id,'in_progress',v_driver);
  insert into public.notifications(user_id,title,body,type)
    values(v_passenger,'Paquete recogido',
    'El repartidor confirmó la recogida y va camino al destinatario.',
    'trip_status');
end $$;

revoke all on function public.confirm_parcel_pickup_v2(uuid,text)
  from public,anon;
grant execute on function public.confirm_parcel_pickup_v2(uuid,text)
  to authenticated;

-- Preserve every existing Taxi transition and accounting rule.

CREATE OR REPLACE FUNCTION public.advance_trip(p_trip_id uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current text;
  v_driver uuid;
  v_passenger uuid;
  v_fare numeric;
  v_payment_method text;
  v_currency text;
  v_title text;
  v_body text;
  v_direct boolean;
  v_mode text;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;

  select t.status,t.driver_id,t.passenger_id,t.final_fare,
         r.payment_method,r.currency,r.service_mode
  into v_current,v_driver,v_passenger,v_fare,v_payment_method,v_currency,v_mode
  from public.trips t
  join public.ride_requests r on r.id=t.ride_request_id
  where t.id=p_trip_id
  for update of t;

  if v_driver is distinct from auth.uid() then raise exception 'No autorizado'; end if;
  if not (
    (v_current='driver_assigned' and p_status in ('driver_arriving','driver_waiting')) or
    (v_current='driver_arriving' and p_status='driver_waiting') or
    (v_current='in_progress' and p_status='completed') or
    (p_status='emergency' and v_current<>'completed')
  ) then
    if v_current='driver_waiting' and p_status='in_progress' then
      raise exception 'Debes validar el PIN de abordaje';
    end if;
    raise exception 'Transición de viaje inválida';
  end if;

  v_direct:=v_payment_method in ('cash','driver_qr');

  update public.trips
  set status=p_status,
      completed_at=case when p_status='completed' then now() else completed_at end,
      payment_status=case
        when p_status='completed' and v_direct then 'paid'
        else payment_status end
  where id=p_trip_id;

  insert into public.trip_status_history(trip_id,status,changed_by)
  values(p_trip_id,p_status,auth.uid());

  v_title:=case p_status
    when 'driver_arriving' then 'Tu conductor va en camino'
    when 'driver_waiting' then 'Tu conductor llegó · 5 minutos'
    when 'completed' then 'Llegaste a destino'
    when 'emergency' then 'Alerta de emergencia'
    else 'Actualización de viaje' end;
  v_body:=case p_status
    when 'driver_arriving' then 'Ya va hacia el punto de recogida. Sigue su llegada en el mapa.'
    when 'driver_waiting' then 'Ya está en el punto de recogida. Tienes 5 minutos para bajar y abordar. Abre Express y toca “Ya voy”.'
    when 'completed' then 'Tu viaje finalizó correctamente. Ya puedes calificar al conductor.'
    when 'emergency' then 'El viaje cambió a estado de emergencia.'
    else 'El estado de tu viaje cambió.' end;

  if v_mode='parcel' then
    v_title:=case p_status
      when 'driver_arriving' then 'Tu repartidor va a recoger el paquete'
      when 'driver_waiting' then 'Repartidor en el punto de recogida'
      when 'completed' then 'Paquete entregado'
      when 'emergency' then 'Alerta en tu envío'
      else 'Actualización del envío' end;
    v_body:=case p_status
      when 'driver_arriving' then 'Tu repartidor se dirige a recoger el paquete.'
      when 'driver_waiting' then 'El repartidor llegó. Entrega el paquete al conductor indicado.'
      when 'completed' then 'La entrega se marcó como completada. Puedes calificar el servicio.'
      when 'emergency' then 'Tu envío está marcado como emergencia.'
      else 'El estado de tu paquete cambió.' end;
  end if;

  insert into public.notifications(user_id,title,body,type)
  values(v_passenger,v_title,v_body,'trip_status');

  if p_status='completed' then
    insert into public.payment_transactions(
      payer_id,payee_id,trip_id,method,amount,currency,status,paid_at
    ) values(
      v_passenger,v_driver,p_trip_id,v_payment_method,
      coalesce(v_fare,0),coalesce(v_currency,'BOB'),
      case when v_direct then 'paid' else 'pending' end,
      case when v_direct then now() else null end
    )
    on conflict(trip_id) where trip_id is not null do nothing;

    update public.driver_profiles
    set completed_trips=completed_trips+1,
        online_status='online',updated_at=now()
    where id=v_driver;

    insert into public.notifications(user_id,title,body,type)
    values(
      v_driver,case when v_mode='parcel' then 'Envío completado'
                   else 'Viaje completado' end,
      case when v_mode='parcel' then
        'La entrega del paquete quedó registrada en tus ganancias.'
      else 'El viaje quedó registrado correctamente en tus ganancias.' end,
      'trip_completed'
    );
  end if;
end;
$function$
;

-- Preserve trip selection and accounting; adapt only parcel assignment messages.
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
        else 'Tu oferta de Bs ' || v_amount ||
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
