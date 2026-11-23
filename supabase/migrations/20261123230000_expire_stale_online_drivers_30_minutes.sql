-- Un conductor en línea sin ubicación pasa a desconectado a los 30 minutos (antes 10),
-- para no sacarlo de línea cuando cierra la app un rato.
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
           < now() - interval '30 minutes'
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
