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
