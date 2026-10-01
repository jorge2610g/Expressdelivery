-- Make the pickup waiting push explicit about the five-minute window.

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
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

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
      completed_at =
        case when p_status = 'completed' then now() else completed_at end,
      payment_status =
        case
          when p_status = 'completed' and v_payment_method = 'cash'
            then 'paid'
          else payment_status
        end
  where id = p_trip_id;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (p_trip_id, p_status, auth.uid());

  v_title := case p_status
    when 'driver_arriving' then 'Tu conductor va en camino'
    when 'driver_waiting' then 'Tu conductor llegó · 5 minutos'
    when 'completed' then 'Llegaste a destino'
    when 'emergency' then 'Alerta de emergencia'
    else 'Actualización de viaje'
  end;

  v_body := case p_status
    when 'driver_arriving' then
      'Ya va hacia el punto de recogida. Sigue su llegada en el mapa.'
    when 'driver_waiting' then
      'Ya está en el punto de recogida. Tienes 5 minutos para bajar y abordar. Abre Express y toca “Ya voy”.'
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
