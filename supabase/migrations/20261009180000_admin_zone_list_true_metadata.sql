-- Fix Admin zone list: it previously omitted operating coverage mode from
-- the card display and omitted critical editable metadata (landing mode,
-- driver registration and country status), causing UI fallback values to
-- masquerade as actual persisted configuration. No zone rows are mutated.
-- Existing admin role/zone scope and active filtering are retained.
CREATE OR REPLACE FUNCTION public.admin_zone_list_for_country(p_country_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_zone uuid;
  v_country text:=upper(trim(coalesce(p_country_code,'')));
begin
  select a.access_role,a.zone_id
    into v_role,v_zone
  from public.admin_users a
  join public.users u on u.id=a.user_id
  where a.user_id=auth.uid()
    and a.active=true
    and u.account_status='active'
  limit 1;

  if v_role is null then raise exception 'No autorizado'; end if;
  if v_country='' then return '[]'::jsonb; end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',z.id,
          'zone_key',z.zone_key,
          'name',z.name,
          'city',z.city,
          'region_department',z.region_department,
          'country',z.country,
          'country_code',z.country_code,
          'currency_code',z.currency_code,
          'active',z.active,
          'center_latitude',z.center_latitude,
          'center_longitude',z.center_longitude,
          'radius_km',z.radius_km,
          'coverage_mode',z.coverage_mode,
          'driver_registration_enabled',z.driver_registration_enabled,
          'passenger_landing_mode',z.passenger_landing_mode,
          'passenger_default_module',z.passenger_default_module,
          'passenger_landing_title',z.passenger_landing_title,
          'passenger_landing_subtitle',z.passenger_landing_subtitle,
          'passenger_landing_order',z.passenger_landing_order,
          'country_active',(select c.active from public.service_countries c
              where c.country_code=upper(coalesce(z.country_code,'')))
        )
        order by z.city,z.name
      ),
      '[]'::jsonb
    )
    from public.service_zones z
    where z.active=true
      and upper(coalesce(z.country_code,''))=v_country
      and (
        v_role='super_admin'
        or z.id=v_zone
      )
  );
end;
$function$;
