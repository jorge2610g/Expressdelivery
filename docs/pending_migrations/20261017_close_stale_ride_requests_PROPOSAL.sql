-- PROPUESTA, NO APLICADA. Requiere autorización explícita y validación en Supabase.
-- Cierra solicitudes que quedaron en 'searching' u 'offers_received' después de vencer,
-- sin tocar solicitudes activas. Solo puede ejecutarla el servicio (service_role).
--
-- Criterios de seguridad (TODOS deben cumplirse para modificar una solicitud):
--   1) estado abierto ('searching' u 'offers_received');
--   2) expires_at no nulo y vencido hace más de 30 s (margen para transiciones en curso);
--   3) ninguna oferta 'selected' ni viaje asociado (no se toca nada asignado);
--   4) ninguna oferta 'pending' todavía vigente (no se cierra una solicitud con oferta válida).
-- Acciones: las ofertas pendientes pasan a 'expired' y la solicitud a 'cancelled', igual
-- que cleanup_expired_ride_requests (no se introduce un estado nuevo).
-- Lote acotado y 'for update skip locked' para no bloquear a los usuarios.

create or replace function public.close_stale_ride_requests(p_limit integer default 100)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_count integer := 0;
begin
  with candidates as (
    select r.id
    from public.ride_requests r
    where r.status in ('searching','offers_received')
      and r.expires_at is not null
      and r.expires_at <= now() - interval '30 seconds'
      and not exists (
        select 1 from public.driver_offers o
        where o.ride_request_id = r.id and o.status = 'selected'
      )
      and not exists (
        select 1 from public.trips t where t.ride_request_id = r.id
      )
      and not exists (
        select 1 from public.driver_offers o
        where o.ride_request_id = r.id
          and o.status = 'pending'
          and o.expires_at is not null
          and o.expires_at > now()
      )
    order by r.expires_at
    limit greatest(least(coalesce(p_limit, 100), 500), 1)
    for update skip locked
  ),
  expired_offers as (
    update public.driver_offers o
    set status = 'expired'
    where o.status = 'pending'
      and o.ride_request_id in (select id from candidates)
    returning o.id
  ),
  closed_requests as (
    update public.ride_requests r
    set status = 'cancelled', updated_at = now()
    where r.id in (select id from candidates)
    returning r.id
  )
  select count(*) into v_count from closed_requests;

  return v_count;
end
$fn$;

revoke all on function public.close_stale_ride_requests(integer) from public, anon, authenticated;
grant execute on function public.close_stale_ride_requests(integer) to service_role;
