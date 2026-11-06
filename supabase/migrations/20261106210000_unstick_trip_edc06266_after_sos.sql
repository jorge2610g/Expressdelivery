-- Desbloqueo único del viaje edc06266-cc97-485e-a04b-61e8d3d639e9.
-- Su alerta SOS se resolvió con admin_resolve_emergency_v2, que no devolvía el viaje
-- a su estado anterior. El viaje quedó en 'emergency' y bloqueado para pasajero y conductor.
-- Último estado antes de la alerta: in_progress (2026-11-06 17:59:37 UTC).
-- Solo actúa si el viaje sigue en 'emergency' y no tiene alertas abiertas.
-- Aplicada en producción el 2026-11-06 con nombre unstick_trip_edc06266_after_sos.
begin;

do $$
declare
  v_trip uuid := 'edc06266-cc97-485e-a04b-61e8d3d639e9';
  v_passenger uuid;
  v_driver uuid;
  v_admin uuid;
  v_open integer;
begin
  select passenger_id, driver_id
    into v_passenger, v_driver
  from public.trips
  where id = v_trip and status = 'emergency'
  for update;

  if not found then
    return;
  end if;

  select count(*)
    into v_open
  from public.emergency_events
  where trip_id = v_trip and status = 'active';

  if v_open > 0 then
    raise exception 'El viaje tiene alertas abiertas; no se desbloquea';
  end if;

  select user_id
    into v_admin
  from public.admin_users
  where access_role = 'super_admin' and active = true
  order by user_id
  limit 1;

  if v_admin is null then
    raise exception 'No hay super admin activo';
  end if;

  update public.trips
     set status = 'in_progress'
   where id = v_trip;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (v_trip, 'in_progress', v_admin);

  insert into public.notifications (user_id, title, body, type, metadata)
  values
    (v_passenger, 'Alerta resuelta', 'La alerta fue resuelta. El viaje continúa.',
     'trip_status', jsonb_build_object('trip_id', v_trip)),
    (v_driver, 'Alerta resuelta', 'La alerta fue resuelta. El viaje continúa.',
     'trip_status', jsonb_build_object('trip_id', v_trip));
end
$$;

commit;
