-- Corrección de 20261116120000_busqueda_por_anillos.
--
-- El anillo inicial se asignaba a todas las solicitudes, también a las programadas.
-- Eso dejaba los viajes programados solo a 1 km, y el guardia de ofertas rechazaba
-- ofertas de conductores lejanos en esos viajes. Los programados no usan anillos:
-- conservan el radio máximo y la visibilidad anterior.
--
-- Aplicar después de 20261116120000.

create or replace function public.set_ride_dispatch_ring()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_mode text;
  v_first numeric;
  v_max numeric;
begin
  select dispatch_mode,
         coalesce(dispatch_radius_km, 1),
         coalesce(max_driver_request_radius_km, 15)
    into v_mode, v_first, v_max
  from public.app_settings
  where id = true;

  if v_mode = 'progressive'
     and new.scheduled_for is null
     and new.pickup_latitude is not null
     and new.pickup_longitude is not null then
    new.dispatch_ring_km := least(greatest(v_first, 0.5), v_max);
    new.dispatch_ring_started_at := now();
  end if;
  return new;
end
$function$;
