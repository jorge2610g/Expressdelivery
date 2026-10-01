-- UX de estados del viaje: textos de notificación más claros.
-- El actor que ejecuta la acción recibe feedback visual en Flutter; la contraparte
-- recibe una notificación contextual del cambio de estado.

create or replace function public.notify_ride_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
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
  values (
    v_passenger,
    'Nueva oferta de conductor',
    coalesce(v_driver_name, 'Un conductor') ||
      ' te ofrece Bs ' || v_amount || '. Revisa la oferta en Express.',
    'ride_offer'
  );

  return new;
end;
$function$;

create or replace function public.select_ride_offer(p_offer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
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
    and o.driver_id <> v_driver_id;

  update public.driver_offers
  set status = case when id = p_offer_id then 'selected' else 'declined' end
  where ride_request_id = v_ride_id and status = 'pending';

  update public.ride_requests
  set status = 'driver_selected', updated_at = now()
  where id = v_ride_id;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');

  insert into public.trips (
    ride_request_id, passenger_id, driver_id, status, final_fare,
    payment_status, boarding_pin
  ) values (
    v_ride_id, v_passenger_id, v_driver_id, 'driver_assigned', v_fare,
    'pending', v_pin
  ) returning id into v_trip_id;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (v_trip_id, 'driver_assigned', auth.uid());

  update public.driver_profiles
  set online_status = 'busy', updated_at = now()
  where id = v_driver_id;

  insert into public.notifications (user_id, title, body, type)
  values
    (
      v_driver_id,
      '¡Viaje confirmado!',
      'Tu oferta de Bs ' || v_amount ||
        ' fue aceptada. Dirígete al punto de recogida.',
      'ride_assigned'
    ),
    (
      v_passenger_id,
      'Conductor confirmado',
      coalesce(v_driver_name, 'Tu conductor') ||
        ' fue asignado a tu viaje. Sigue su llegada en el mapa.',
      'ride_assigned'
    );

  return v_trip_id;
end;
$function$;

create or replace function public.advance_trip(p_trip_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_current text;
  v_driver uuid;
  v_passenger uuid;
  v_fare numeric;
  v_payment_method text;
  v_currency text;
  v_title text;
  v_body text;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;

  select t.status, t.driver_id, t.passenger_id, t.final_fare,
         r.payment_method, r.currency
    into v_current, v_driver, v_passenger, v_fare,
         v_payment_method, v_currency
  from public.trips t
  join public.ride_requests r on r.id = t.ride_request_id
  where t.id = p_trip_id
  for update of t;

  if v_driver is distinct from auth.uid() then
    raise exception 'No autorizado';
  end if;

  if not (
    (v_current = 'driver_assigned' and p_status = 'driver_arriving') or
    (v_current = 'driver_arriving' and p_status = 'driver_waiting') or
    (v_current = 'in_progress' and p_status = 'completed') or
    (p_status = 'emergency' and v_current <> 'completed')
  ) then
    if v_current = 'driver_waiting' and p_status = 'in_progress' then
      raise exception 'Debes validar el PIN de abordaje';
    end if;
    raise exception 'Transición de viaje inválida';
  end if;

  update public.trips
  set status = p_status,
      completed_at = case when p_status = 'completed' then now() else completed_at end,
      payment_status = case
        when p_status = 'completed' and v_payment_method = 'cash' then 'paid'
        else payment_status
      end
  where id = p_trip_id;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (p_trip_id, p_status, auth.uid());

  v_title := case p_status
    when 'driver_arriving' then 'Tu conductor va en camino'
    when 'driver_waiting' then 'Tu conductor llegó'
    when 'completed' then 'Llegaste a destino'
    when 'emergency' then 'Alerta de emergencia'
    else 'Actualización de viaje'
  end;

  v_body := case p_status
    when 'driver_arriving' then
      'Ya va hacia el punto de recogida. Sigue su llegada en el mapa.'
    when 'driver_waiting' then
      'Ya se encuentra en el punto de recogida y te está esperando.'
    when 'completed' then
      'Tu viaje finalizó correctamente. Ya puedes calificar al conductor.'
    when 'emergency' then
      'El viaje cambió a estado de emergencia.'
    else
      'El estado de tu viaje cambió.'
  end;

  insert into public.notifications (user_id, title, body, type)
  values (v_passenger, v_title, v_body, 'trip_status');

  if p_status = 'completed' then
    insert into public.payment_transactions (
      payer_id, payee_id, trip_id, method, amount, currency, status, paid_at
    ) values (
      v_passenger, v_driver, p_trip_id, v_payment_method,
      coalesce(v_fare, 0), coalesce(v_currency, 'BOB'),
      case when v_payment_method = 'cash' then 'paid' else 'pending' end,
      case when v_payment_method = 'cash' then now() else null end
    )
    on conflict (trip_id) where trip_id is not null do nothing;

    update public.driver_profiles
    set completed_trips = completed_trips + 1,
        online_status = 'online',
        updated_at = now()
    where id = v_driver;

    insert into public.notifications (user_id, title, body, type)
    values (
      v_driver,
      'Viaje completado',
      'El viaje quedó registrado correctamente en tus ganancias.',
      'trip_completed'
    );
  end if;
end;
$function$;

create or replace function public.start_trip_with_pin(p_trip_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_driver uuid;
  v_passenger uuid;
  v_status text;
  v_pin text;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;

  select driver_id, passenger_id, status, boarding_pin
    into v_driver, v_passenger, v_status, v_pin
  from public.trips
  where id = p_trip_id
  for update;

  if v_driver is distinct from auth.uid() then
    raise exception 'No autorizado';
  end if;
  if v_status <> 'driver_waiting' then
    raise exception 'El viaje todavía no está listo para iniciar';
  end if;
  if coalesce(trim(p_pin), '') <> coalesce(v_pin, '') then
    raise exception 'PIN incorrecto';
  end if;

  update public.trips set status = 'in_progress' where id = p_trip_id;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (p_trip_id, 'in_progress', auth.uid());

  insert into public.notifications (user_id, title, body, type)
  values (
    v_passenger,
    'Viaje iniciado',
    'Tu viaje comenzó correctamente. Buen viaje.',
    'trip_status'
  );
end;
$function$;
