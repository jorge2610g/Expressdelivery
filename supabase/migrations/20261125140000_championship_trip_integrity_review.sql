-- Revisión retroactiva de los viajes que HOY suman en el campeonato (producción), con todas las reglas
-- de integridad vigentes (incluidas «en curso muy corto» y «sin movimiento»).
-- Alcance: solo viajes completados que cumplen las condiciones de un campeonato activo (ventana, zona,
-- servicio) y que no tienen ninguna marca. Los viajes que ya tenían marca (abierta, confirmada o
-- descartada) y los que no cuentan para el campeonato no se tocan.
-- Las marcas solo excluyen el viaje del campeonato; esta revisión NO aplica sanciones ni cambia el
-- conteo general de viajes del conductor.
do $m$
declare
  d text; r jsonb; v_id uuid; v_ids uuid[] := '{}';
begin
  -- Copia de trip_integrity_evaluate sin la llamada a driver_integrity_apply (sin sanciones).
  d := pg_get_functiondef('public.trip_integrity_evaluate(uuid)'::regprocedure);
  d := replace(d, 'FUNCTION public.trip_integrity_evaluate(', 'FUNCTION public.trip_integrity_review_only(');
  d := replace(d, '  perform public.driver_integrity_apply(t.id);' || E'\n', '');
  if position('driver_integrity_apply' in d) > 0 then
    raise exception 'La copia sin sanciones sigue llamando a driver_integrity_apply';
  end if;
  execute d;
  revoke all on function public.trip_integrity_review_only(uuid) from public, anon, authenticated;

  for v_id in
    select distinct t.id from public.trips t
      join public.ride_requests r on r.id = t.ride_request_id
      join public.driver_championships c on c.channel = t.channel and c.state = 'active'
       and t.completed_at >= c.starts_at and t.completed_at < c.ends_at
       and r.zone_id = c.zone_id and (c.service_key = '*' or r.category = c.service_key)
     where t.status = 'completed' and t.channel = 'production'
       and not exists (select 1 from public.trip_integrity_flags f where f.trip_id = t.id)
  loop
    r := public.trip_integrity_review_only(v_id);
    if coalesce((r->>'flagged')::boolean, false) then v_ids := array_append(v_ids, v_id); end if;
  end loop;

  update public.trip_integrity_flags
     set metrics = metrics || jsonb_build_object('revision_campeonato', '2026-11-25')
   where trip_id = any(v_ids);
end $m$;
