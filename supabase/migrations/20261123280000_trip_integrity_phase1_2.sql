-- Integridad de viajes, fases 1 y 2.
-- 1) Se guarda el recorrido GPS del conductor mientras tiene un viaje activo.
-- 2) Al completarse cada viaje se revisa y, si hay irregularidades, se marca (sin sancionar):
--    los viajes marcados no suman al campeonato hasta que un administrador los revise.

-- ── Fase 1: recorrido del conductor ────────────────────────────────────────────
create table if not exists public.trip_location_points (
  id bigint generated always as identity primary key,
  trip_id uuid not null references public.trips(id) on delete cascade,
  driver_id uuid not null,
  trip_status text not null,
  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  heading_degrees numeric,
  recorded_at timestamptz not null default now()
);
create index if not exists trip_location_points_trip_idx
  on public.trip_location_points (trip_id, recorded_at);
create index if not exists trip_location_points_recorded_idx
  on public.trip_location_points (recorded_at);
alter table public.trip_location_points enable row level security;
revoke all on public.trip_location_points from anon, authenticated;

create or replace function public.record_driver_trip_point()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_trip uuid; v_status text; v_last timestamptz;
begin
  begin
    if new.latitude is null or new.longitude is null then return new; end if;
    select t.id, t.status into v_trip, v_status
      from public.trips t
     where t.driver_id = new.id
       and t.status not in ('completed','cancelled')
     order by t.created_at desc limit 1;
    if v_trip is null then return new; end if;
    select max(recorded_at) into v_last from public.trip_location_points where trip_id = v_trip;
    if v_last is not null and v_last > now() - interval '3 seconds' then return new; end if;
    insert into public.trip_location_points(trip_id, driver_id, trip_status, latitude, longitude, heading_degrees)
    values (v_trip, new.id, v_status, new.latitude, new.longitude, new.heading_degrees);
  exception when others then
    null; -- guardar el recorrido nunca debe bloquear la ubicación del conductor
  end;
  return new;
end $$;
revoke all on function public.record_driver_trip_point() from public, anon, authenticated;

drop trigger if exists record_driver_trip_point on public.driver_profiles;
create trigger record_driver_trip_point
  after update of latitude, longitude, updated_at on public.driver_profiles
  for each row
  when (new.latitude is not null and new.longitude is not null)
  execute function public.record_driver_trip_point();

-- Se conservan 90 días.
select cron.schedule('trip-location-points-retention', '17 3 * * *',
  $c$delete from public.trip_location_points where recorded_at < now() - interval '90 days'$c$)
where not exists (select 1 from cron.job where jobname = 'trip-location-points-retention');

-- ── Fase 2: revisión al completar el viaje ─────────────────────────────────────
create table if not exists public.trip_integrity_flags (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null unique references public.trips(id) on delete cascade,
  driver_id uuid not null,
  passenger_id uuid,
  channel text not null,
  zone_id uuid,
  severity text not null check (severity in ('medium','high')),
  reasons jsonb not null,
  metrics jsonb not null default '{}'::jsonb,
  review_status text not null default 'open' check (review_status in ('open','cleared','confirmed')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now()
);
create index if not exists trip_integrity_flags_status_idx
  on public.trip_integrity_flags (channel, review_status, created_at desc);
create index if not exists trip_integrity_flags_driver_idx
  on public.trip_integrity_flags (driver_id, created_at desc);
alter table public.trip_integrity_flags enable row level security;
revoke all on public.trip_integrity_flags from anon, authenticated;

-- Evalúa un viaje completado. Solo marca terminar ANTES de lo previsto (terminar
-- después significa que el viaje tardó más y es normal).
create or replace function public.trip_integrity_evaluate(p_trip_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  t public.trips%rowtype;
  r public.ride_requests%rowtype;
  v_reasons text[] := '{}';
  v_start timestamptz; v_end timestamptz; v_minutes numeric;
  v_first record; v_last record;
  v_points integer := 0; v_path_km numeric := 0; v_max_kmh numeric := 0;
  v_direct_km numeric; v_route_km numeric; v_est numeric;
  v_pair integer; v_short integer;
  v_start_off numeric; v_end_off numeric;
  v_metrics jsonb; v_severity text;
begin
  select * into t from public.trips where id = p_trip_id;
  if t.id is null or t.status <> 'completed' then return null; end if;
  select * into r from public.ride_requests where id = t.ride_request_id;
  if r.id is null then return null; end if;

  v_route_km := r.route_distance_km;
  v_est := r.route_duration_minutes;
  v_direct_km := public.geo_distance_km(r.pickup_latitude, r.pickup_longitude,
                                        r.destination_latitude, r.destination_longitude);

  select count(*) into v_points from public.trip_location_points
   where trip_id = t.id and trip_status = 'in_progress';
  if v_points >= 2 then
    select latitude, longitude, recorded_at into v_first from public.trip_location_points
     where trip_id = t.id and trip_status = 'in_progress' order by recorded_at asc limit 1;
    select latitude, longitude, recorded_at into v_last from public.trip_location_points
     where trip_id = t.id and trip_status = 'in_progress' order by recorded_at desc limit 1;
    v_start := v_first.recorded_at;
    v_end := coalesce(t.completed_at, v_last.recorded_at);
    v_minutes := extract(epoch from (v_end - v_start)) / 60.0;
    v_start_off := public.geo_distance_km(v_first.latitude, v_first.longitude,
                                          r.pickup_latitude, r.pickup_longitude);
    v_end_off := public.geo_distance_km(v_last.latitude, v_last.longitude,
                                        r.destination_latitude, r.destination_longitude);
    select coalesce(sum(seg), 0), coalesce(max(kmh), 0) into v_path_km, v_max_kmh from (
      select public.geo_distance_km(plat, plng, latitude, longitude) as seg,
             case when extract(epoch from (recorded_at - prev_at)) between 2 and 120
                       and public.geo_distance_km(plat, plng, latitude, longitude) > 0.05
                  then public.geo_distance_km(plat, plng, latitude, longitude)
                       / (extract(epoch from (recorded_at - prev_at)) / 3600.0)
                  else 0 end as kmh
      from (
        select latitude, longitude, recorded_at,
               lag(latitude) over w as plat, lag(longitude) over w as plng,
               lag(recorded_at) over w as prev_at
        from public.trip_location_points
        where trip_id = t.id and trip_status = 'in_progress'
        window w as (order by recorded_at)
      ) q where plat is not null
    ) s;

    if v_est is not null and v_est >= 3 and v_minutes < v_est * 0.5 then
      v_reasons := array_append(v_reasons, 'termino_antes_de_lo_previsto'::text);
    end if;
    if v_start_off > 0.35 then v_reasons := array_append(v_reasons, 'inicio_lejos_del_origen'::text); end if;
    if v_end_off > 0.35 then v_reasons := array_append(v_reasons, 'fin_lejos_del_destino'::text); end if;
    if v_route_km is not null and v_route_km >= 0.5 and v_path_km < v_route_km * 0.6 then
      v_reasons := array_append(v_reasons, 'recorrido_mucho_menor_a_la_ruta'::text);
    end if;
    if v_max_kmh > 120 then v_reasons := array_append(v_reasons, 'velocidad_imposible'::text); end if;
  end if;

  if v_direct_km is not null and v_direct_km < 0.2 then
    v_reasons := array_append(v_reasons, 'origen_y_destino_casi_iguales'::text);
  end if;

  select count(*) into v_pair from public.trips x
   where x.driver_id = t.driver_id and x.passenger_id = t.passenger_id
     and x.status = 'completed' and x.channel = t.channel
     and x.completed_at > coalesce(t.completed_at, now()) - interval '24 hours'
     and x.completed_at <= coalesce(t.completed_at, now());
  if v_pair >= 3 then v_reasons := array_append(v_reasons, 'misma_pareja_repetida'::text); end if;

  select count(*) into v_short from public.trips x
   where x.driver_id = t.driver_id and x.status = 'completed' and x.channel = t.channel
     and x.completed_at > coalesce(t.completed_at, now()) - interval '2 hours'
     and x.completed_at <= coalesce(t.completed_at, now())
     and x.completed_at - x.created_at < interval '6 minutes';
  if v_short >= 4 then v_reasons := array_append(v_reasons, 'muchos_viajes_cortos_seguidos'::text); end if;

  v_metrics := jsonb_strip_nulls(jsonb_build_object(
    'minutos_reales', round(v_minutes, 1), 'minutos_estimados', v_est,
    'km_ruta', v_route_km, 'km_recorridos', round(v_path_km, 2),
    'km_directos', round(v_direct_km::numeric, 2),
    'metros_inicio_vs_origen', round(v_start_off * 1000),
    'metros_fin_vs_destino', round(v_end_off * 1000),
    'velocidad_maxima_kmh', round(v_max_kmh),
    'puntos_gps', v_points, 'viajes_misma_pareja_24h', v_pair,
    'viajes_cortos_2h', v_short, 'sin_recorrido', v_points < 2));

  if coalesce(array_length(v_reasons, 1), 0) = 0 then
    return jsonb_build_object('flagged', false, 'metrics', v_metrics);
  end if;

  v_severity := case when array_length(v_reasons, 1) >= 2
                       or v_reasons && array['velocidad_imposible','misma_pareja_repetida','origen_y_destino_casi_iguales']
                     then 'high' else 'medium' end;
  insert into public.trip_integrity_flags(trip_id, driver_id, passenger_id, channel, zone_id,
                                          severity, reasons, metrics)
  values (t.id, t.driver_id, t.passenger_id, t.channel, r.zone_id,
          v_severity, to_jsonb(v_reasons), v_metrics)
  on conflict (trip_id) do nothing;
  return jsonb_build_object('flagged', true, 'severity', v_severity,
                            'reasons', to_jsonb(v_reasons), 'metrics', v_metrics);
end $$;
revoke all on function public.trip_integrity_evaluate(uuid) from public, anon, authenticated;

create or replace function public.trip_integrity_on_complete()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  begin
    perform public.trip_integrity_evaluate(new.id);
  exception when others then
    null; -- la revisión nunca debe impedir completar un viaje
  end;
  return new;
end $$;
revoke all on function public.trip_integrity_on_complete() from public, anon, authenticated;

drop trigger if exists trip_integrity_on_complete on public.trips;
create trigger trip_integrity_on_complete
  after update of status on public.trips
  for each row
  when (new.status = 'completed' and old.status is distinct from 'completed')
  execute function public.trip_integrity_on_complete();
