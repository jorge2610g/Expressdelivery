-- Single, mutually exclusive coverage authority for each operating zone.
-- Existing zones keep their previous effective geo mode on migration.
alter table public.service_zones
 add column if not exists coverage_mode text not null default 'radius';
alter table public.service_zones
 drop constraint if exists service_zones_coverage_mode_check;
alter table public.service_zones
 add constraint service_zones_coverage_mode_check
 check (coverage_mode in ('radius','polygon'));

-- Preserve prior production operation: active polygon previously overrode radius.
update public.service_zones z set coverage_mode='polygon'
 where exists (
  select 1 from public.service_zone_polygons p
  where p.zone_id=z.id and p.active=true
 ) and z.coverage_mode='radius';

create or replace function public.admin_zone_coverage_get(
 p_zone_id uuid, p_channel text
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare v_zone public.service_zones%rowtype; v_polygon jsonb;
begin
 if auth.uid() is null or not public.is_admin()
   or p_channel not in ('preview','production')
   or not public.admin_environment_allowed(p_channel) then
   raise exception 'No autorizado para ver la cobertura';
 end if;
 select * into v_zone from public.service_zones where id=p_zone_id;
 if not found then raise exception 'Zona no encontrada'; end if;
 select to_jsonb(p) into v_polygon from public.service_zone_polygons p
 where p.zone_id=p_zone_id and p.active=true
 order by p.updated_at desc,p.id desc limit 1;
 return jsonb_build_object(
  'zone_id',v_zone.id,'coverage_mode',v_zone.coverage_mode,
  'center_latitude',v_zone.center_latitude,
  'center_longitude',v_zone.center_longitude,
  'radius_km',v_zone.radius_km,
  'polygon',coalesce(v_polygon->'polygon','[]'::jsonb),
  'polygon_id',v_polygon->>'id'
 );
end $$;

-- Zone fields and coverage mode are committed together in ONE transaction.
-- For radius ALL zone polygons become inactive. For polygon exactly ONE
-- operating polygon is active; radius is retained as inert legacy data.
create or replace function public.admin_zone_coverage_save(
 p_channel text, p_id uuid, p_name text, p_city text,
 p_region_department text, p_country_code text, p_active boolean,
 p_driver_registration_enabled boolean,
 p_center_latitude numeric, p_center_longitude numeric, p_radius_km numeric,
 p_zone_key text, p_currency_code text, p_coverage_mode text,
 p_polygon jsonb
) returns uuid language plpgsql security definer
set search_path=public as $$
declare v_zone_id uuid; v_poly_id uuid; v_lat numeric; v_lng numeric;
 v_point jsonb; v_distinct integer; v_count integer;
 v_center_lat numeric:=p_center_latitude;
 v_center_lng numeric:=p_center_longitude;
begin
 if auth.uid() is null or not public.is_admin()
  or p_channel not in ('preview','production')
  or not public.admin_environment_allowed(p_channel) then
  raise exception 'No autorizado para modificar la cobertura';
 end if;
 if p_coverage_mode not in ('radius','polygon') or p_coverage_mode is null then
  raise exception 'Selecciona cobertura por Radio o Polígono';
 end if;
 if p_coverage_mode='radius' then
  if v_center_lat is null or v_center_lng is null
    or v_center_lat not between -90 and 90
    or v_center_lng not between -180 and 180
    or p_radius_km is null or p_radius_km <= 0 or p_radius_km > 1000 then
   raise exception 'Selecciona un centro y un radio válido (hasta 1000 km)';
  end if;
 else
  if p_polygon is null or jsonb_typeof(p_polygon)<>'array'
    or jsonb_array_length(p_polygon) < 3
    or jsonb_array_length(p_polygon) > 300 then
   raise exception 'Dibuja un polígono válido de 3 a 300 puntos';
  end if;
  v_count:=0; v_center_lat:=0; v_center_lng:=0;
  for v_point in select value from jsonb_array_elements(p_polygon) loop
    begin
      v_lat := (v_point->>'lat')::numeric;
      v_lng := (v_point->>'lng')::numeric;
    exception when others then
      raise exception 'Polígono contiene coordenadas inválidas';
    end;
    if v_lat is null or v_lng is null or v_lat not between -90 and 90
      or v_lng not between -180 and 180 then
      raise exception 'Polígono contiene coordenadas fuera de rango';
    end if;
    v_count:=v_count+1;
    v_center_lat:=v_center_lat+v_lat;
    v_center_lng:=v_center_lng+v_lng;
  end loop;
  select count(*) into v_distinct from (
    select distinct value->>'lat',value->>'lng'
    from jsonb_array_elements(p_polygon)
  ) points;
  if v_distinct<3 then raise exception 'Usa al menos 3 puntos distintos'; end if;
  v_center_lat:=v_center_lat/v_count;
  v_center_lng:=v_center_lng/v_count;
 end if;

 v_zone_id:=public.admin_upsert_zone_v3(
  p_id,p_name,p_city,p_region_department,p_country_code,p_active,
  p_driver_registration_enabled,v_center_lat,v_center_lng,
  case when p_coverage_mode='radius' then p_radius_km
       else coalesce(nullif(p_radius_km,0),25) end,
  p_zone_key,p_currency_code
 );
 -- Lock zone before mutating coverage for deterministic concurrent admin writes.
 perform 1 from public.service_zones where id=v_zone_id for update;
 if p_coverage_mode='polygon' then
   select p.id into v_poly_id from public.service_zone_polygons p
     where p.zone_id=v_zone_id
     order by p.active desc,p.updated_at desc,p.id desc limit 1;
 end if;
 update public.service_zone_polygons
   set active=false,updated_at=now()
   where zone_id=v_zone_id and active=true;
 if p_coverage_mode='polygon' then
   if v_poly_id is null then
     insert into public.service_zone_polygons(zone_id,name,polygon,active)
     values(v_zone_id,'Cobertura principal',p_polygon,true);
   else
     update public.service_zone_polygons
       set polygon=p_polygon,active=true,updated_at=now()
       where id=v_poly_id and zone_id=v_zone_id;
   end if;
 end if;
 update public.service_zones set coverage_mode=p_coverage_mode,
   updated_at=now() where id=v_zone_id;
 perform public.admin_log_action('upsert','service_zone_coverage',
   v_zone_id::text,jsonb_build_object('coverage_mode',p_coverage_mode));
 return v_zone_id;
end $$;

revoke all on function public.admin_zone_coverage_get(uuid,text) from public,anon;
revoke all on function public.admin_zone_coverage_save(
 text,uuid,text,text,text,text,boolean,boolean,numeric,numeric,numeric,
 text,text,text,jsonb) from public,anon;
grant execute on function public.admin_zone_coverage_get(uuid,text) to authenticated;
grant execute on function public.admin_zone_coverage_save(
 text,uuid,text,text,text,text,boolean,boolean,numeric,numeric,numeric,
 text,text,text,jsonb) to authenticated;

-- Existing client RPC gets the explicit single selected coverage mode.
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
          'coverage_mode',z.coverage_mode
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
$function$


-- The same decision applies to the passenger, driver, fare and availability
-- checks: NEVER silently fall back to a saved radius when polygon is chosen.
create or replace function public.service_zone_id_for_point(
 p_lat numeric,p_lng numeric
) returns uuid language plpgsql stable security definer
set search_path=public as $$
declare v_id uuid;
begin
 if p_lat is null or p_lng is null then return null; end if;
 select z.id into v_id
 from public.service_zones z
 join public.service_countries c
   on c.country_code=upper(coalesce(z.country_code,''))
  and c.active=true
 where z.active=true
   and (
     (z.coverage_mode='polygon' and exists(
       select 1 from public.service_zone_polygons p
       where p.zone_id=z.id and p.active=true
         and public.point_in_json_polygon(p_lat,p_lng,p.polygon)))
     or
     (z.coverage_mode='radius'
       and z.center_latitude is not null
       and z.center_longitude is not null
       and public.geo_distance_km(p_lat,p_lng,z.center_latitude,z.center_longitude)
            <= greatest(coalesce(z.radius_km,20),0.5))
   )
 order by
   case when z.coverage_mode='polygon' then 0 else 1 end,
   public.geo_distance_km(p_lat,p_lng,z.center_latitude,z.center_longitude)
 limit 1;
 return v_id;
end $$;
