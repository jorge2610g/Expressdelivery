-- Viajes programados: se avisa a los conductores solo cerca de la hora programada.
--  * Antes el límite era fijo en 30 min: un viaje programado a 15-30 min salía de inmediato
--    (el pasajero lo veía como búsqueda normal). Ahora se usa el ajuste del panel
--    app_settings.scheduled_publish_before_minutes (queda en 10 min; mínimo 5).
--  * Un trabajo cada minuto publica los viajes programados cuando llega su hora
--    (antes nadie los avisaba al llegar el momento: solo aparecían si el conductor abría la app).
alter table public.ride_requests add column if not exists scheduled_published_at timestamptz;

update public.app_settings set scheduled_publish_before_minutes = 10 where id = true;

-- Al crear el viaje: si no es programado o ya está dentro de la ventana, queda publicado.
create or replace function public.mark_scheduled_ride_published()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare v_lead integer;
begin
  select least(greatest(coalesce(scheduled_publish_before_minutes, 10), 5), 1440)
    into v_lead from public.app_settings where id = true;
  if new.scheduled_for is null
     or new.scheduled_for <= now() + make_interval(mins => coalesce(v_lead, 10)) then
    new.scheduled_published_at := coalesce(new.scheduled_published_at, now());
  end if;
  return new;
end $$;

drop trigger if exists zz_mark_scheduled_ride_published on public.ride_requests;
create trigger zz_mark_scheduled_ride_published
  before insert on public.ride_requests
  for each row execute function public.mark_scheduled_ride_published();

-- El aviso inmediato a conductores usa la misma ventana que el ajuste del panel.
do $$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'notify_available_ride_to_drivers';
  if v_def is null then raise exception 'notify_available_ride_to_drivers no existe'; end if;
  if position('scheduled_publish_before_minutes' in v_def) > 0 then return; end if;
  v_new := replace(v_def,
    'new.scheduled_for > now() + interval ''30 minutes''',
    'new.scheduled_for > now() + make_interval(mins => (select least(greatest(coalesce(scheduled_publish_before_minutes, 10), 5), 1440) from public.app_settings where id = true))');
  if v_new = v_def then raise exception 'no se encontró el límite de 30 minutos'; end if;
  execute v_new;
end $$;

-- Publica los viajes programados cuando llega su ventana.
create or replace function public.publish_due_scheduled_rides()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r public.ride_requests%rowtype; v_id uuid; v_lead integer; v_max numeric; v_count integer := 0;
begin
  select least(greatest(coalesce(scheduled_publish_before_minutes, 10), 5), 1440),
         coalesce(max_driver_request_radius_km, 15)
    into v_lead, v_max from public.app_settings where id = true;
  for v_id in
    select id from public.ride_requests
     where status = 'searching' and scheduled_for is not null
       and scheduled_published_at is null and expires_at > now()
       and scheduled_for <= now() + make_interval(mins => v_lead)
     order by scheduled_for
     limit 200
  loop
    update public.ride_requests set scheduled_published_at = now() where id = v_id;
    select * into r from public.ride_requests where id = v_id;
    if r.dispatch_style = 'sequential' or r.zone_id is null
       or r.pickup_latitude is null or r.pickup_longitude is null then
      continue;
    end if;
    perform public.notify_ride_candidates(r, 0,
      least(greatest(coalesce(r.dispatch_ring_km, v_max), 1), 100));
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
revoke all on function public.publish_due_scheduled_rides() from public, anon, authenticated;

select cron.schedule('publish-due-scheduled-rides', '* * * * *', 'select public.publish_due_scheduled_rides()')
where not exists (select 1 from cron.job where jobname = 'publish-due-scheduled-rides');
