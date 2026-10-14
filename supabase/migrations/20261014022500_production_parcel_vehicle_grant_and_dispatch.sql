-- Driver Envíos dispatch recovery, 2026-10-14.
-- Production incident: passenger-visible parcel zone was driver_visible=false.
-- Parcel vehicle grants were restricted to Preview even for Production admins.
-- Do not create or approve individual driver/vehicle grants automatically.
-- Preserve all environment, driver identity, vehicle capacity and zone checks.
CREATE OR REPLACE FUNCTION public.admin_set_driver_parcel_vehicle_grant(p_driver_id uuid, p_vehicle_id uuid, p_channel text, p_parcel_kind text, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone uuid;
  v_vehicle_type text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Solo el administrador puede asignar tipos de envío';
  end if;
  -- Match the exact identity/environment guard used for driver service
  -- approvals. An administrator in Preview cannot edit a Production driver.
  perform public.admin_assert_target_environment(p_driver_id,p_channel);
  if p_parcel_kind not in ('moto','auto','carga') or p_parcel_kind is null then
    raise exception 'Tipo de envío no válido';
  end if;
  select dp.zone_id,dv.vehicle_type into v_zone,v_vehicle_type
  from public.driver_profiles dp
  join public.driver_vehicles dv on dv.driver_id=dp.id
  where dp.id=p_driver_id and dv.id=p_vehicle_id and dv.is_active=true;
  if v_zone is null then
    raise exception 'Vehículo activo y zona del conductor requeridos';
  end if;
  -- The verified driver / active vehicle / zone and payload are constrained above.
  if coalesce(p_enabled,false) and
      public.parcel_vehicle_capacity(v_vehicle_type)
        < public.parcel_kind_capacity(p_parcel_kind) then
    raise exception 'Este vehículo no tiene capacidad para ese envío';
  end if;
  insert into public.driver_parcel_vehicle_grants(
    driver_id,vehicle_id,zone_id,channel,parcel_kind,enabled,updated_by)
  values (p_driver_id,p_vehicle_id,v_zone,p_channel,
    p_parcel_kind,coalesce(p_enabled,false),auth.uid())
  on conflict(driver_id,vehicle_id,channel,parcel_kind) do update set
    zone_id=excluded.zone_id,enabled=excluded.enabled,
    updated_by=auth.uid(),updated_at=now();
  return jsonb_build_object('driver_id',p_driver_id,'vehicle_id',p_vehicle_id,
    'channel',p_channel,'parcel_kind',p_parcel_kind,'enabled',coalesce(p_enabled,false));
end;
$function$
;
-- Synchronize only the active *Production* Envíos zones that have already
-- been explicitly enabled for passengers. Never enable a disabled module.
-- Individual work permits and vehicle grants remain required by dispatcher.
update public.zone_service_catalog zc
set driver_visible=true,
    updated_at=now()
where zc.service_key in ('parcel','delivery')
  and zc.enabled=true
  and zc.passenger_visible=true
  and zc.driver_visible is distinct from true
  and exists (
    select 1
    from public.service_zones z
    where z.id=zc.zone_id and z.active=true
      and exists (
        select 1 from public.zone_service_catalog parcel
        where parcel.zone_id=z.id and parcel.service_key='parcel'
          and parcel.enabled=true and parcel.passenger_visible=true
      )
  );
