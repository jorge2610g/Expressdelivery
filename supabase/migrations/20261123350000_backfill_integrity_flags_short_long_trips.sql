-- Revisión del historial (Producción): viajes completados en menos de 5 minutos (desde que
-- empezó el viaje) con 1 km o más y velocidad implícita mayor a 35 km/h. Se agregan a
-- «Viajes sospechosos» para revisión manual. NO generan avisos ni sanciones (action_taken = 'none').
insert into public.trip_integrity_flags
  (trip_id, driver_id, passenger_id, channel, zone_id, severity, reasons, metrics, action_taken)
select t.id, t.driver_id, t.passenger_id, t.channel, r.zone_id,
       case when x.vel > 80 then 'high' else 'medium' end,
       jsonb_build_array('viaje_historico_muy_corto'),
       jsonb_strip_nulls(jsonb_build_object(
         'minutos_reales', round(x.min_real::numeric, 1),
         'minutos_estimados', r.route_duration_minutes,
         'km_ruta', r.route_distance_km,
         'velocidad_implicita_kmh', round(x.vel::numeric),
         'sin_recorrido', true, 'origen', 'revision_historial')),
       'none'
from public.trips t
join public.ride_requests r on r.id = t.ride_request_id
cross join lateral (
  select extract(epoch from (t.completed_at - coalesce(
           (select min(h.created_at) from public.trip_status_history h
             where h.trip_id = t.id and h.status = 'in_progress'), t.created_at))) / 60.0 as min_real
) m
cross join lateral (
  select m.min_real, r.route_distance_km / greatest(m.min_real, 0.1) * 60 as vel
) x
where t.status = 'completed' and t.channel = 'production' and t.completed_at is not null
  and r.zone_id is not null
  and x.min_real < 5 and r.route_distance_km >= 1 and x.vel > 35
on conflict (trip_id) do nothing;
