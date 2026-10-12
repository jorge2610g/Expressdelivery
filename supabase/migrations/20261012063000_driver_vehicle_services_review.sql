-- Atomic vehicle + service preference update for Web onboarding edits.
-- Keep the existing RPC unchanged for older mobile clients.
create or replace function public.update_my_driver_vehicle_services_for_review(
  p_vehicle_type text,
  p_vehicle_brand text,
  p_vehicle_model text,
  p_vehicle_color text,
  p_vehicle_plate text,
  p_vehicle_year integer,
  p_vehicle_photo_paths text[],
  p_service_keys text[]
) returns jsonb
language plpgsql security definer set search_path=public
as $vehicle_services$
declare
  v_uid uuid:=auth.uid();
  v_zone uuid;
  v_key text;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  select dp.zone_id into v_zone from public.driver_profiles dp
  where dp.id=v_uid;
  if v_zone is null then raise exception 'Selecciona la zona del conductor'; end if;
  if nullif(trim(coalesce(p_vehicle_type,'')),'') is null then
    raise exception 'Selecciona tu tipo de vehículo';
  end if;
  if coalesce(cardinality(p_service_keys),0)=0 then
    raise exception 'Selecciona al menos un servicio de tu vehículo';
  end if;
  foreach v_key in array p_service_keys loop
    if not exists (
      select 1
      from public.zone_service_catalog zc
      join public.service_catalog c on c.service_key=zc.service_key
      where zc.zone_id=v_zone and zc.service_key=v_key
        and zc.enabled and zc.driver_visible
        and c.enabled and c.driver_visible
        and (c.vehicle_type is null or c.vehicle_type=p_vehicle_type)
    ) then
      raise exception 'El servicio % no corresponde al vehículo de esta zona',v_key;
    end if;
  end loop;

  -- The existing RPC handles owner checks, private photo ownership and
  -- review/pending status. Any later failure rolls back this whole call.
  v_result:=public.update_my_driver_vehicle_for_review(
    p_vehicle_type,p_vehicle_brand,p_vehicle_model,p_vehicle_color,
    p_vehicle_plate,p_vehicle_year,p_vehicle_photo_paths
  );

  delete from public.driver_service_preferences where driver_id=v_uid;
  foreach v_key in array p_service_keys loop
    insert into public.driver_service_preferences(
      driver_id,zone_id,service_key,enabled)
    values (v_uid,v_zone,v_key,true)
    on conflict(driver_id,zone_id,service_key)
    do update set enabled=true,updated_at=now();
  end loop;

  return v_result||jsonb_build_object('service_keys',to_jsonb(p_service_keys));
end;
$vehicle_services$;
revoke all on function public.update_my_driver_vehicle_services_for_review(
 text,text,text,text,text,integer,text[],text[])
 from public,anon;
grant execute on function public.update_my_driver_vehicle_services_for_review(
 text,text,text,text,text,integer,text[],text[])
 to authenticated;
