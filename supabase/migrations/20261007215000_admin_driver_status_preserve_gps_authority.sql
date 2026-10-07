-- Admin profile edits must not fabricate a live driver GPS session.
-- The mobile driver runtime is the only authority allowed to transition an
-- offline driver to online/busy because coverage enforcement requires a
-- current device location. Admin may always force a driver offline.

create or replace function public.admin_update_driver_profile(
  p_user_id uuid,
  p_full_name text,
  p_phone text,
  p_account_status text,
  p_license_number text,
  p_city text,
  p_zone_id uuid,
  p_approval_status text,
  p_online_status text,
  p_vehicle_type text,
  p_vehicle_brand text,
  p_vehicle_model text,
  p_vehicle_color text,
  p_vehicle_plate text,
  p_vehicle_year integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_vehicle_id uuid;
  v_summary text;
  v_online text;
  v_current_online text;
  v_city text;
  v_country_code text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_account_status not in ('active','suspended','blocked') then
    raise exception 'Estado de cuenta inválido';
  end if;
  if p_approval_status not in ('pending','approved','rejected','suspended') then
    raise exception 'Estado de conductor inválido';
  end if;
  if p_online_status not in ('online','offline','busy') then
    raise exception 'Estado operativo inválido';
  end if;
  if p_vehicle_type not in ('car','motorcycle','xl') then
    raise exception 'Tipo de vehículo inválido';
  end if;

  select z.city, upper(z.country_code)
    into v_city, v_country_code
  from public.service_zones z
  where z.id = p_zone_id
    and z.active = true;

  if v_city is null or v_country_code is null then
    raise exception 'Zona inválida';
  end if;

  select d.online_status
    into v_current_online
  from public.driver_profiles d
  where d.id = p_user_id;

  if v_current_online is null then
    raise exception 'Conductor no encontrado';
  end if;

  v_summary = trim(concat_ws(' ',
    nullif(trim(p_vehicle_brand),''),
    nullif(trim(p_vehicle_model),'')
  ));
  if nullif(trim(p_vehicle_plate),'') is not null then
    v_summary = trim(v_summary || ' · ' || trim(p_vehicle_plate));
  end if;

  update public.users
  set full_name = nullif(trim(p_full_name),''),
      phone = nullif(trim(p_phone),''),
      account_status = p_account_status,
      last_zone_id = p_zone_id,
      updated_at = now()
  where id = p_user_id;
  if not found then raise exception 'Usuario no encontrado'; end if;

  -- Do not bounce online_status offline->online during an ordinary admin edit.
  -- That old behavior triggered the live GPS coverage guard even when the
  -- administrator only changed profile/vehicle data.
  update public.driver_profiles
  set license_number = nullif(trim(p_license_number),''),
      vehicle_summary = nullif(v_summary,''),
      city = v_city,
      country_code = v_country_code,
      zone_id = p_zone_id,
      approval_status = p_approval_status,
      updated_at = now()
  where id = p_user_id;

  select id into v_vehicle_id
  from public.driver_vehicles
  where driver_id = p_user_id
  order by is_active desc, updated_at desc
  limit 1;

  update public.driver_vehicles
  set is_active = false, updated_at = now()
  where driver_id = p_user_id;

  if v_vehicle_id is null then
    insert into public.driver_vehicles(
      driver_id, vehicle_type, brand, model, color, plate, year, is_active, updated_at
    )
    values(
      p_user_id, p_vehicle_type,
      nullif(trim(p_vehicle_brand),''),
      nullif(trim(p_vehicle_model),''),
      nullif(trim(p_vehicle_color),''),
      nullif(trim(p_vehicle_plate),''),
      p_vehicle_year, true, now()
    );
  else
    update public.driver_vehicles
    set vehicle_type = p_vehicle_type,
        brand = nullif(trim(p_vehicle_brand),''),
        model = nullif(trim(p_vehicle_model),''),
        color = nullif(trim(p_vehicle_color),''),
        plate = nullif(trim(p_vehicle_plate),''),
        year = p_vehicle_year,
        is_active = true,
        updated_at = now()
    where id = v_vehicle_id;
  end if;

  -- Admin can force offline. It cannot take an offline driver online because
  -- only the driver device has the fresh GPS needed by coverage/tracking.
  v_online := case
    when p_account_status <> 'active'
      or p_approval_status <> 'approved'
      or not public.driver_subscription_allows_dispatch(p_user_id)
    then 'offline'
    when p_online_status = 'offline'
    then 'offline'
    when v_current_online in ('online','busy')
    then v_current_online
    else 'offline'
  end;

  update public.driver_profiles
  set online_status = v_online,
      updated_at = now()
  where id = p_user_id
    and online_status is distinct from v_online;

  perform public.admin_log_action(
    'update_driver_profile','driver_profile',p_user_id::text,
    jsonb_build_object(
      'approval_status',p_approval_status,
      'requested_online_status',p_online_status,
      'online_status',v_online,
      'country_code',v_country_code,
      'city',v_city,
      'zone_id',p_zone_id,
      'vehicle_type',p_vehicle_type,
      'plate',nullif(trim(p_vehicle_plate),'')
    )
  );

  return public.admin_driver_detail(p_user_id);
end;
$function$;

revoke execute on function public.admin_update_driver_profile(
  uuid,text,text,text,text,text,uuid,text,text,text,text,text,text,text,integer
) from public, anon;
grant execute on function public.admin_update_driver_profile(
  uuid,text,text,text,text,text,uuid,text,text,text,text,text,text,text,integer
) to authenticated;
