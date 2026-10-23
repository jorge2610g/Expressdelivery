-- Web driver onboarding: location is used only to suggest/validate the selected service zone.
-- Manual country/city selection remains available when browser geolocation is denied.
create or replace function public.submit_driver_web_onboarding(
  p_zone_id uuid,
  p_license_number text,
  p_service_keys text[],
  p_vehicle_type text,
  p_vehicle_brand text,
  p_vehicle_model text,
  p_vehicle_color text,
  p_vehicle_plate text,
  p_vehicle_year integer,
  p_profile_photo_path text,
  p_vehicle_photo_paths text[],
  p_documents jsonb,
  p_lat numeric,
  p_lng numeric
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_uid uuid := auth.uid();
  v_detected_zone uuid;
begin
  if v_uid is null then
    raise exception 'Autenticación requerida';
  end if;

  if p_zone_id is null then
    raise exception 'Selecciona un país y una ciudad habilitados';
  end if;

  if (p_lat is null) <> (p_lng is null) then
    raise exception 'La ubicación está incompleta; vuelve a detectar o selecciona la ciudad manualmente';
  end if;

  if p_lat is not null and (p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180) then
    raise exception 'La ubicación no es válida';
  end if;

  if exists (
    select 1
    from public.driver_profiles dp
    where dp.id = v_uid
      and lower(coalesce(dp.approval_status, '')) = 'approved'
  ) then
    raise exception 'Tu registro ya fue aprobado. Inicia sesión en la aplicación Express';
  end if;

  if not exists (
    select 1
    from public.service_zones z
    join public.service_countries c
      on c.country_code = upper(coalesce(z.country_code, ''))
    where z.id = p_zone_id
      and z.active = true
      and z.driver_registration_enabled = true
      and c.active = true
      and c.driver_registration_enabled = true
  ) then
    raise exception 'El registro de conductores no está habilitado en esa ciudad';
  end if;

  if p_lat is not null then
    v_detected_zone := public.service_zone_id_for_point(p_lat, p_lng);
    if v_detected_zone is null then
      raise exception 'No hay cobertura de conductores en tu ubicación. Selecciona otra ciudad';
    end if;
    if v_detected_zone is distinct from p_zone_id then
      raise exception 'La ciudad seleccionada no coincide con tu ubicación. Puedes elegirla manualmente';
    end if;
  end if;

  return public.submit_driver_onboarding(
    p_zone_id,
    p_license_number,
    p_service_keys,
    p_vehicle_type,
    p_vehicle_brand,
    p_vehicle_model,
    p_vehicle_color,
    p_vehicle_plate,
    p_vehicle_year,
    p_profile_photo_path,
    p_vehicle_photo_paths,
    p_documents
  );
end;
$function$;

revoke all on function public.submit_driver_web_onboarding(
  uuid, text, text[], text, text, text, text, text, integer, text, text[], jsonb,
  numeric, numeric
) from public, anon;
grant execute on function public.submit_driver_web_onboarding(
  uuid, text, text[], text, text, text, text, text, integer, text, text[], jsonb,
  numeric, numeric
) to authenticated;

comment on function public.submit_driver_web_onboarding(
  uuid, text, text[], text, text, text, text, text, integer, text, text[], jsonb,
  numeric, numeric
) is 'Submits driver onboarding from the standalone web portal, allowing either a verified one-time location or manual selection of an enabled country and zone.';
