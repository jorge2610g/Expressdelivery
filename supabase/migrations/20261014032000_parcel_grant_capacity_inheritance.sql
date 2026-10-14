-- 2026-10-14: Envíos permissions inherit downwards by vehicle capacity.
-- A driver explicitly authorized for Auto may also receive Moto packages.
-- A driver authorized for Moto can never receive Auto or Carga.
-- The approved size on a specific active vehicle is the MAXIMUM allowed size.
-- A driver with no explicit enabled grant remains ineligible (fail closed).
-- No zone, account, grant, tariff, notification or Taxi data is modified.
create or replace function public.parcel_driver_can_carry(
  p_driver_id uuid, p_ride_id uuid
) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1
      from public.ride_requests r
      join public.driver_profiles dp
        on dp.id=p_driver_id and dp.zone_id=r.zone_id
      join public.driver_vehicles dv
        on dv.driver_id=dp.id and dv.is_active=true
      join public.driver_parcel_vehicle_grants g
        on g.driver_id=dp.id and g.vehicle_id=dv.id
        and g.zone_id=dp.zone_id and g.channel=r.channel
        and g.enabled
        and public.parcel_kind_capacity(g.parcel_kind)
            >= public.parcel_kind_capacity(r.parcel_kind)
      join public.driver_work_permissions wp
        on wp.driver_id=dp.id and wp.zone_id=dp.zone_id
        and wp.channel=r.channel and wp.service_key='parcel'
        and wp.status='approved'
     where r.id=p_ride_id and r.service_mode='parcel'
       and r.parcel_kind in ('moto','auto','carga')
       and public.admin_user_runtime_environment(dp.id)=r.channel
       and public.parcel_vehicle_capacity(dv.vehicle_type)
           >= public.parcel_kind_capacity(r.parcel_kind)
  );
$$;
-- Preserve function API and restricted callers used by feed/offer/trip triggers.
revoke execute on function public.parcel_driver_can_carry(uuid,uuid)
  from public,anon,authenticated;
