-- Las acciones de soporte del administrador sobre un viaje (iniciar, completar, etc.) ahora
-- llegan al instante a la app del conductor:
--  1) «Iniciar viaje» también avisa al conductor (antes solo avisaba al pasajero).
--  2) Se toca la solicitud del viaje: la app del conductor escucha cambios en ride_requests
--     y refresca la pantalla en el momento (antes esperaba al respaldo de 30 s o más).
do $$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_trip_action_v1';
  if v_def is null then raise exception 'admin_trip_action_v1 no existe'; end if;
  if position('Viaje iniciado' in v_def) > 0 then return; end if;
  v_new := replace(v_def,
    'values (v_trip.passenger_id, ''Viaje en curso'', ''Tu viaje ya está en curso.'', ''trip_status'');',
    'values (v_trip.passenger_id, ''Viaje en curso'', ''Tu viaje ya está en curso.'', ''trip_status''), (v_trip.driver_id, ''Viaje iniciado'', ''Un administrador inició el viaje. Continúa hacia el destino.'', ''trip_status'');');
  if v_new = v_def then raise exception 'no se encontró el aviso de inicio de viaje'; end if;
  v_def := v_new;
  v_new := replace(v_def,
    'perform public.admin_log_action(''trip_support_'' || p_action',
    E'update public.ride_requests set updated_at = now() where id = v_trip.ride_request_id;\n  perform public.admin_log_action(''trip_support_'' || p_action');
  if v_new = v_def then raise exception 'no se encontró el registro de la acción'; end if;
  execute v_new;
end $$;
