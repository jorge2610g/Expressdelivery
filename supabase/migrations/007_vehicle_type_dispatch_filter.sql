-- Filter nearby drivers and dispatch visibility by the driver's saved active vehicle type.
-- Applied to production Supabase on 2026-09-30.

create or replace function public.nearby_online_driver_markers(
  p_lat numeric,
  p_lng numeric,
  p_radius_km numeric default 5,
  p_vehicle_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_requested text := nullif(lower(trim(coalesce(p_vehicle_type, ''))), '');
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  with candidates as (
    select
      round(dp.latitude::numeric, 3) as latitude,
      round(dp.longitude::numeric, 3) as longitude,
      coalesce(
        (
          select dv.vehicle_type
          from public.driver_vehicles dv
          where dv.driver_id = dp.id
            and dv.is_active = true
          order by dv.updated_at desc
          limit 1
        ),
        case
          when lower(coalesce(dp.vehicle_summary,'')) like '%moto%' then 'motorcycle'
          when lower(coalesce(dp.vehicle_summary,'')) like '%xl%' then 'xl'
          else 'car'
        end
      ) as vehicle_type,
      (
        6371 * acos(
          least(1, greatest(-1,
            cos(radians(p_lat::double precision))
            * cos(radians(dp.latitude::double precision))
            * cos(radians(dp.longitude::double precision) - radians(p_lng::double precision))
            + sin(radians(p_lat::double precision))
            * sin(radians(dp.latitude::double precision))
          ))
        )
      ) as distance_km
    from public.driver_profiles dp
    where dp.approval_status = 'approved'
      and dp.online_status = 'online'
      and dp.latitude is not null
      and dp.longitude is not null
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'latitude', latitude,
        'longitude', longitude,
        'vehicle_type', vehicle_type,
        'distance_km', round(distance_km::numeric, 1)
      )
      order by distance_km
    ),
    '[]'::jsonb
  )
  into v_result
  from (
    select *
    from candidates
    where distance_km <= greatest(0.5, least(coalesce(p_radius_km, 5), 20))
      and (v_requested is null or vehicle_type = v_requested)
    order by distance_km
    limit 16
  ) q;

  return v_result;
end;
$$;

revoke execute on function public.nearby_online_driver_markers(numeric,numeric,numeric,text) from public, anon;
grant execute on function public.nearby_online_driver_markers(numeric,numeric,numeric,text) to authenticated;
