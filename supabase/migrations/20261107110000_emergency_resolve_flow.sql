-- Resolver una alerta SOS y devolver el viaje a su estado anterior.
--
-- Causa del bloqueo: admin_resolve_emergency_v2 solo marcaba la alerta como
-- resuelta y dejaba trips.status = 'emergency'. advance_trip no admite ninguna
-- transición desde 'emergency' (solo volver a emergencia), así que el pasajero
-- y el conductor quedaban pausados hasta que el viaje se tocara a mano.
--
-- Esta función es nueva; no modifica admin_resolve_emergency_v2 ni
-- admin_resolve_emergency. Autorización igual que v2 y admin_resolve_emergency:
--   1. entorno permitido a la cuenta (admin_assert_environment);
--   2. solo super_admin activo (public.is_admin(), como admin_resolve_emergency);
--   3. alerta del mismo entorno (admin_assert_target_environment);
--   4. módulo 'dashboard' (admin_operator_assert_module; sin cambio para super_admin).
--
-- Comportamiento, en una transacción:
--   a. marca la alerta como 'resolved' con resolved_at;
--   b. si la alerta tiene viaje, el viaje sigue en 'emergency' y no quedan otras
--      alertas activas de ese viaje, lo devuelve al último estado distinto de
--      'emergency' registrado antes de la alerta (o 'in_progress' si no existe)
--      y registra el cambio en trip_status_history con changed_by = auth.uid();
--   c. si la alerta es de un envío, no toca delivery_requests;
--   d. avisa a pasajero y conductor (o cliente y repartidor) con notifications;
--   e. registra la acción en admin_audit_log con admin_log_action.
--
-- Idempotente: si la alerta ya no está activa, no cambia el viaje ni avisa.
-- No borra datos ni cambia canales: las notificaciones toman el canal del viaje
-- o del envío mediante metadata (trigger notification_runtime_channel).

create or replace function public.admin_resolve_emergency_v3(
  p_emergency_id uuid,
  p_channel text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel text;
  v_emergency public.emergency_events%rowtype;
  v_trip public.trips%rowtype;
  v_delivery public.delivery_requests%rowtype;
  v_has_trip boolean := false;
  v_has_delivery boolean := false;
  v_other_open_alerts integer := 0;
  v_since timestamptz;
  v_restore_status text := null;
  v_trip_resumed boolean := false;
  v_trip_status text := null;
  v_parties uuid[] := array[]::uuid[];
  v_recipient uuid;
  v_type text;
  v_body text;
  v_meta jsonb;
begin
  if p_emergency_id is null then
    raise exception 'Emergencia requerida';
  end if;

  v_channel := public.admin_assert_environment(p_channel);

  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  perform public.admin_operator_assert_module('dashboard');

  select * into v_emergency
  from public.emergency_events
  where id = p_emergency_id
  for update;

  if not found then
    raise exception 'Emergencia no encontrada';
  end if;

  perform public.admin_assert_target_environment(v_emergency.user_id, v_channel);

  -- Idempotencia: una alerta ya cerrada no vuelve a tocar el viaje ni avisa.
  if v_emergency.status <> 'active' then
    return jsonb_build_object(
      'emergency_id', v_emergency.id,
      'status', v_emergency.status,
      'already_closed', true,
      'trip_resumed', false,
      'trip_status', null
    );
  end if;

  update public.emergency_events
  set status = 'resolved',
      resolved_at = now()
  where id = p_emergency_id;

  if v_emergency.trip_id is not null then
    select * into v_trip
    from public.trips
    where id = v_emergency.trip_id
    for update;
    v_has_trip := found;
  end if;

  if v_emergency.delivery_id is not null then
    select * into v_delivery
    from public.delivery_requests
    where id = v_emergency.delivery_id;
    v_has_delivery := found;
  end if;

  if v_has_trip then
    v_trip_status := v_trip.status;

    select count(*)
      into v_other_open_alerts
    from public.emergency_events e
    where e.trip_id = v_trip.id
      and e.status = 'active'
      and e.id <> p_emergency_id;

    -- Solo se devuelve el viaje si esta era la última alerta abierta.
    if v_trip.status = 'emergency' and v_other_open_alerts = 0 then
      -- Momento en que se registró esta alerta en el historial del viaje.
      select h.created_at
        into v_since
      from public.trip_status_history h
      where h.trip_id = v_trip.id
        and h.status = 'emergency'
        and h.created_at <= v_emergency.created_at
      order by h.created_at desc, h.id desc
      limit 1;

      v_since := coalesce(v_since, v_emergency.created_at);

      -- Último estado operativo anterior a la alerta. Nunca se restaura a
      -- 'completed' ni 'cancelled'.
      select h.status
        into v_restore_status
      from public.trip_status_history h
      where h.trip_id = v_trip.id
        and h.status in ('driver_assigned', 'driver_arriving', 'driver_waiting', 'in_progress')
        and h.created_at < v_since
      order by h.created_at desc, h.id desc
      limit 1;

      v_restore_status := coalesce(v_restore_status, 'in_progress');

      update public.trips
      set status = v_restore_status
      where id = v_trip.id;

      insert into public.trip_status_history (trip_id, status, changed_by)
      values (v_trip.id, v_restore_status, auth.uid());

      v_trip_resumed := true;
      v_trip_status := v_restore_status;
    end if;

    v_parties := array[v_trip.passenger_id, v_trip.driver_id];
    v_type := 'trip_status';
    v_meta := jsonb_build_object(
      'trip_id', v_trip.id,
      'emergency_id', p_emergency_id
    );

    if v_trip_resumed then
      v_body := 'La alerta fue resuelta. El viaje continúa.';
    elsif v_other_open_alerts > 0 then
      v_body := 'La alerta fue resuelta. Otra alerta del viaje sigue abierta.';
    else
      v_body := 'La alerta fue resuelta.';
    end if;
  elsif v_has_delivery then
    v_parties := array[v_delivery.customer_id, v_delivery.courier_id];
    v_type := 'delivery_status';
    v_meta := jsonb_build_object(
      'delivery_id', v_delivery.id,
      'emergency_id', p_emergency_id
    );
    v_body := 'La alerta del envío fue resuelta.';
  end if;

  if v_has_trip or v_has_delivery then
    foreach v_recipient in array v_parties loop
      if v_recipient is not null then
        insert into public.notifications (user_id, title, body, type, metadata)
        values (v_recipient, 'Alerta resuelta', v_body, v_type, v_meta);
      end if;
    end loop;
  end if;

  perform public.admin_log_action(
    'resolve',
    'emergency',
    p_emergency_id::text,
    jsonb_build_object(
      'environment', v_channel,
      'trip_id', v_emergency.trip_id,
      'delivery_id', v_emergency.delivery_id,
      'trip_resumed', v_trip_resumed,
      'trip_status', v_trip_status,
      'restored_status', v_restore_status
    )
  );

  return jsonb_build_object(
    'emergency_id', p_emergency_id,
    'status', 'resolved',
    'already_closed', false,
    'trip_resumed', v_trip_resumed,
    'trip_status', v_trip_status
  );
end;
$$;

revoke execute on function public.admin_resolve_emergency_v3(uuid, text) from public, anon;
grant execute on function public.admin_resolve_emergency_v3(uuid, text) to authenticated;
