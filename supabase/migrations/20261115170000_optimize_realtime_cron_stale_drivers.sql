-- Optimización de carga de la base (sin cambiar lo que ve el usuario).
--
-- 1) Realtime: trips y ratings salen de la publicación. Ninguna app las escucha
--    (las leen con consultas normales), y cada cambio en esas tablas obligaba a
--    Realtime a decodificar el WAL sin que nadie lo usara.
-- 2) Cron: el historial de cron se purga cada día (conserva 1 día).
-- 3) Conductores fantasma: un conductor marcado «en línea» sin ubicación en
--    10 min y sin viaje ni envío activo pasa a «fuera de línea». El trigger
--    existente cancela sus ofertas pendientes. Un conductor con viaje o envío
--    activo nunca se toca.

do $$
begin
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'trips'
  ) then
    alter publication supabase_realtime drop table public.trips;
  end if;
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ratings'
  ) then
    alter publication supabase_realtime drop table public.ratings;
  end if;
end
$$;

select cron.unschedule('purge-cron-job-run-details')
  where exists (select 1 from cron.job where jobname = 'purge-cron-job-run-details');
select cron.schedule(
  'purge-cron-job-run-details',
  '10 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '1 day'$$
);

create or replace function public.expire_stale_online_drivers()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_count integer;
begin
  with stale as (
    update public.driver_profiles d
       set online_status = 'offline',
           updated_at = now()
     where d.online_status = 'online'
       and coalesce(d.location_updated_at, d.updated_at, d.created_at)
           < now() - interval '10 minutes'
       and not exists (
         select 1 from public.trips t
         where t.driver_id = d.id and t.status not in ('completed','cancelled')
       )
       and not exists (
         select 1 from public.delivery_requests r
         where r.courier_id = d.id and r.status not in ('delivered','cancelled')
       )
    returning 1
  )
  select count(*) into v_count from stale;
  return v_count;
end
$function$;

revoke all on function public.expire_stale_online_drivers() from public, anon, authenticated;

select cron.unschedule('expire-stale-online-drivers')
  where exists (select 1 from cron.job where jobname = 'expire-stale-online-drivers');
select cron.schedule(
  'expire-stale-online-drivers',
  '*/2 * * * *',
  $$select public.expire_stale_online_drivers()$$
);
