-- Código de país para preseleccionar el prefijo telefónico según la ubicación del usuario.
--
-- Nueva función: recibe un punto y devuelve solo el código ISO de 2 letras del país
-- de la zona de servicio que lo cubre (o null si no hay zona activa con código
-- telefónico). Reutiliza service_zone_id_for_point; no guarda ni registra la
-- ubicación. Accesible sin sesión, igual que phone_country_catalog, porque el
-- registro con Google y el correo ocurre antes de iniciar sesión.

create or replace function public.phone_country_for_point(p_lat numeric, p_lng numeric)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_zone uuid;
  v_country text;
begin
  if p_lat is null or p_lng is null then
    return null;
  end if;
  v_zone := public.service_zone_id_for_point(p_lat, p_lng);
  if v_zone is null then
    return null;
  end if;
  select upper(z.country_code) into v_country
  from public.service_zones z
  join public.service_countries c
    on c.country_code = upper(coalesce(z.country_code, ''))
   and c.active = true
  where z.id = v_zone
    and nullif(trim(coalesce(c.calling_code, '')), '') is not null;
  return v_country;
end
$function$;

revoke all on function public.phone_country_for_point(numeric, numeric) from public;
grant execute on function public.phone_country_for_point(numeric, numeric)
  to anon, authenticated, service_role;
