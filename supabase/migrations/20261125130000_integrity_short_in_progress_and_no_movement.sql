-- Detección de viajes sin recorrido: antes, si el viaje tenía menos de 2 puntos GPS «en curso»,
-- no se evaluaba duración ni movimiento. Un viaje iniciado y completado en 8 segundos con el
-- conductor quieto en la recogida (25/11, Trinidad) quedó sin marca.
-- Nuevas razones:
--   en_curso_muy_corto : menos de 90 s entre «en curso» y «completado» con ruta de 0.5 km o más.
--   sin_movimiento_gps : con 2 o más puntos GPS en todo el viaje, el conductor nunca se alejó
--                        más de 100 m de su primer punto y la ruta era de 0.5 km o más.
do $m$
declare d text;
begin
  d := pg_get_functiondef('public.trip_integrity_evaluate(uuid)'::regprocedure);

  d := replace(d, '  v_metrics jsonb; v_severity text;',
    '  v_metrics jsonb; v_severity text;' || E'\n' ||
    '  v_inprog_sec numeric; v_spread_km numeric := 0; v_total_points integer := 0;');

  d := replace(d, '  if v_direct_km is not null and v_direct_km < 0.2 then',
    '  select extract(epoch from (t.completed_at - min(h.created_at))) into v_inprog_sec' || E'\n' ||
    '    from public.trip_status_history h where h.trip_id = t.id and h.status = ''in_progress'';' || E'\n' ||
    '  if v_inprog_sec is not null and v_inprog_sec < 90 and v_route_km is not null and v_route_km >= 0.5 then' || E'\n' ||
    '    v_reasons := array_append(v_reasons, ''en_curso_muy_corto''::text);' || E'\n' ||
    '  end if;' || E'\n' ||
    '  select count(*), coalesce(max(public.geo_distance_km(f.latitude, f.longitude, p.latitude, p.longitude)), 0)' || E'\n' ||
    '    into v_total_points, v_spread_km' || E'\n' ||
    '    from public.trip_location_points p' || E'\n' ||
    '    cross join lateral (select latitude, longitude from public.trip_location_points' || E'\n' ||
    '                         where trip_id = t.id order by recorded_at asc limit 1) f' || E'\n' ||
    '   where p.trip_id = t.id;' || E'\n' ||
    '  if v_total_points >= 2 and v_spread_km < 0.1 and v_route_km is not null and v_route_km >= 0.5 then' || E'\n' ||
    '    v_reasons := array_append(v_reasons, ''sin_movimiento_gps''::text);' || E'\n' ||
    '  end if;' || E'\n' ||
    E'\n' || '  if v_direct_km is not null and v_direct_km < 0.2 then');

  d := replace(d, '''viajes_cortos_2h'', v_short, ''sin_recorrido'', v_points < 2));',
    '''viajes_cortos_2h'', v_short, ''sin_recorrido'', v_points < 2,' || E'\n' ||
    '    ''segundos_en_curso'', round(v_inprog_sec), ''movimiento_gps_m'', round(v_spread_km * 1000)));');

  d := replace(d, 'array[''velocidad_imposible'',''misma_pareja_repetida'',''origen_y_destino_casi_iguales'']',
                  'array[''velocidad_imposible'',''misma_pareja_repetida'',''origen_y_destino_casi_iguales'',''en_curso_muy_corto'',''sin_movimiento_gps'']');

  if position('en_curso_muy_corto' in d) = 0 or position('v_inprog_sec numeric' in d) = 0
     or position('segundos_en_curso' in d) = 0 or position('''sin_movimiento_gps'']' in d) = 0 then
    raise exception 'No se pudo aplicar el parche de detección a trip_integrity_evaluate';
  end if;
  execute d;
end $m$;

-- Viajes de producción de los últimos 14 días que cumplen las reglas nuevas y no tenían marca.
-- Solo se crea la marca para revisión: no se aplican sanciones automáticas hacia atrás.
insert into public.trip_integrity_flags(trip_id, driver_id, passenger_id, channel, zone_id, severity, reasons, metrics)
select c.id, c.driver_id, c.passenger_id, c.channel, c.zone_id, 'high',
       to_jsonb(array_remove(array[
         case when c.inprog < 90 then 'en_curso_muy_corto' end,
         case when c.np >= 2 and c.spread < 0.1 then 'sin_movimiento_gps' end], null)),
       jsonb_strip_nulls(jsonb_build_object('km_ruta', c.rk, 'segundos_en_curso', round(c.inprog),
         'movimiento_gps_m', round(c.spread * 1000), 'puntos_gps_total', c.np, 'revision_retroactiva', true))
  from (
    select t.id, t.driver_id, t.passenger_id, t.channel, r.zone_id, r.route_distance_km rk,
      (select extract(epoch from (t.completed_at - min(h.created_at))) from public.trip_status_history h
        where h.trip_id = t.id and h.status = 'in_progress') inprog,
      (select count(*) from public.trip_location_points p where p.trip_id = t.id) np,
      (select coalesce(max(public.geo_distance_km(f.latitude, f.longitude, p.latitude, p.longitude)), 0)
         from public.trip_location_points p
         cross join lateral (select latitude, longitude from public.trip_location_points
                              where trip_id = t.id order by recorded_at asc limit 1) f
        where p.trip_id = t.id) spread
    from public.trips t join public.ride_requests r on r.id = t.ride_request_id
   where t.status = 'completed' and t.channel = 'production'
     and t.completed_at > now() - interval '14 days'
     and not exists (select 1 from public.trip_integrity_flags f where f.trip_id = t.id)
  ) c
 where c.rk >= 0.5 and (c.inprog < 90 or (c.np >= 2 and c.spread < 0.1))
on conflict (trip_id) do nothing;
