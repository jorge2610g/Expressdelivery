-- Resolver una alerta SOS también desbloquea el viaje si quedó en 'emergency'.
-- Antes, si la alerta ya estaba resuelta, admin_resolve_emergency_v3 salía sin tocar el viaje.
-- Ahora, si la alerta ya no está activa pero el viaje sigue en 'emergency' y no tiene otras
-- alertas abiertas, lo devuelve a su último estado operativo y avisa a ambas partes.
-- Sigue siendo idempotente: si no hay nada que desbloquear, no cambia ni avisa.
-- Aplicada en producción el 2026-11-06 con nombre resolve_emergency_unsticks_trip.

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
  v_was_active boolean;
  v_stuck boolean := false;
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

  v_was_active := v_emergency.status = 'active';

  if not v_was_active then
    -- La alerta ya estaba cerrada: solo se actúa si el viaje sigue bloqueado.
    v_stuck := v_emergency.trip_id is not null and exists (
      select 1
      from public.trips t
      where t.id = v_emergency.trip_id
        and t.status = 'emergency'
    );

    if not v_stuck then
      return jsonb_build_object(
        'emergency_id', v_emergency.id,
        'status', v_emergency.status,
        'already_closed', true,
        'trip_resumed', false,
        'trip_status', null
      );
    end if;
  else
    update public.emergency_events
    set status = 'resolved',
        resolved_at = now()
    where id = p_emergency_id;
  end if;

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

    -- Solo se devuelve el viaje si no quedan otras alertas abiertas.
    if v_trip.status = 'emergency' and v_other_open_alerts = 0 then
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
      'restored_status', v_restore_status,
      'was_active', v_was_active
    )
  );

  return jsonb_build_object(
    'emergency_id', p_emergency_id,
    'status', 'resolved',
    'already_closed', (not v_was_active and not v_trip_resumed),
    'trip_resumed', v_trip_resumed,
    'trip_status', v_trip_status
  );
end;
$$;

revoke execute on function public.admin_resolve_emergency_v3(uuid, text) from public, anon;
grant execute on function public.admin_resolve_emergency_v3(uuid, text) to authenticated;
