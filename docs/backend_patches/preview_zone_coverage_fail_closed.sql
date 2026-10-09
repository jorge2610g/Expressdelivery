-- REVIEW-ONLY PATCH, DO NOT EXECUTE AGAINST PRODUCTION.
-- This is intentionally NOT a numbered migration. Generate the eventual
-- migration using `supabase migration new` and validate in the isolated
-- physical Preview project before any scheduled Production rollout.
--
-- Emergency protection: existing admin_zone_coverage_save accepts
-- p_channel='preview' and then upserts into live service_zones + polygons.
-- This preserves the exact signature and Production behavior while rejecting
-- Preview writes. It does NOT protect other unscoped admin RPCs.
--
-- Required rollout order:
-- (1) review and test in physically isolated Preview DB;
-- (2) establish server-side protections for other unscoped RPCs;
-- (3) deploy Preview Admin QA-shadow UI and test QA edits;
-- (4) only then plan a compatible Production migration with rollback;
-- (5) verify Production zone metadata and traffic unchanged.
--
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
 -- QA must never mutate the live geography, regardless of UI/client version.
 -- Production continues to execute the historical implementation unchanged.
 if p_channel='preview' then
   raise exception 'Esta cobertura es exclusiva de QA: utiliza la configuración aislada de Preview';
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
end $$;;
