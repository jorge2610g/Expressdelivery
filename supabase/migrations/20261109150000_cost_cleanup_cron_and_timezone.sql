-- Reducción de carga en la base de datos (auditoría 2026-11-09).
--
-- 1) Limpieza de ofertas vencidas: antes la llamaba cada app pasajero en su pantalla
--    principal (72,000 llamadas). Ahora corre en el servidor cada minuto. La función
--    pública sigue existiendo para compatibilidad, pero ya no la llama el cliente.
-- 2) Validación de zona horaria de los avisos programados: consultar
--    pg_timezone_names costaba ~420 ms por llamada. Se reemplaza por una prueba
--    directa con now() at time zone, que es barata y rechaza zonas inválidas.

begin;

-- 1) Función interna sin validación de sesión (la ejecuta el cron, no un usuario).
create or replace function public.cleanup_expired_ride_offers_cron()
returns void
language sql
security definer
set search_path = public
as $$
  update public.driver_offers
  set status = 'expired'
  where status = 'pending'
    and expires_at is not null
    and expires_at <= now();
$$;

revoke all on function public.cleanup_expired_ride_offers_cron() from public, anon, authenticated;

-- Programar cada minuto, sin duplicar si ya existe.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'cleanup-expired-ride-offers') then
    perform cron.unschedule('cleanup-expired-ride-offers');
  end if;
  perform cron.schedule(
    'cleanup-expired-ride-offers',
    '* * * * *',
    'select public.cleanup_expired_ride_offers_cron();'
  );
end
$$;

-- 2) Validación barata de zona horaria.
create or replace function public.notification_timezone_valid(p_tz text)
returns boolean
language plpgsql
stable
set search_path = public
as $$
begin
  if p_tz is null or btrim(p_tz) = '' then
    return false;
  end if;
  perform now() at time zone p_tz;
  return true;
exception when others then
  return false;
end;
$$;

-- Reemplaza, dentro de la función de validación existente, la consulta al catálogo
-- por la prueba barata. El resto de la validación queda igual.
do $$
declare
  d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'notification_schedule_check_definition';

  if d is null then
    raise exception 'No se encontró notification_schedule_check_definition';
  end if;

  if position('pg_catalog.pg_timezone_names' in d) > 0 then
    d := replace(
      d,
      'select 1 from pg_catalog.pg_timezone_names t where t.name = p_timezone',
      'select 1 where public.notification_timezone_valid(p_timezone)'
    );
    execute d;
  end if;
end
$$;

commit;
