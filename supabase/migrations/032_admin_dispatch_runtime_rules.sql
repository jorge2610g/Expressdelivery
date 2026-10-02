-- Reglas de dispatch configuradas desde Adminexpress.
-- Radio, cantidad de solicitudes, visibilidad y anticipación de programados.

create or replace function public.available_ride_requests_for_driver()
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_scheduled_before integer := 30;
  v_visible_seconds integer := 180;
  v_max_visible integer := 20;
  v_radius numeric := 15;
  v_lat numeric;
  v_lng numeric;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not public.is_approved_online_driver(v_uid) then
    return '[]'::jsonb;
  end if;

  select
    coalesce(scheduled_publish_before_minutes,30),
    coalesce(request_visible_seconds,180),
    coalesce(max_visible_requests_driver,20),
    coalesce(max_driver_request_radius_km,15)
  into v_scheduled_before,v_visible_seconds,v_max_visible,v_radius
  from public.app_settings
  where id=true;

  select latitude,longitude
  into v_lat,v_lng
  from public.driver_profiles
  where id=v_uid
  limit 1;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc),'[]'::jsonb)
  into v_result
  from (
    select r.*
    from public.ride_requests r
    where r.status in ('searching','offers_received')
      and r.expires_at > now()
      and r.passenger_id <> v_uid
      and (
        r.scheduled_for is null
        or r.scheduled_for <=
          now() + make_interval(mins => least(greatest(v_scheduled_before,5),1440))
      )
      and (
        r.scheduled_for is not null
        or r.created_at >
          now() - make_interval(secs => least(greatest(v_visible_seconds,30),1800))
      )
      and exists (
        select 1
        from public.service_catalog c
        where c.service_key=r.category
          and c.enabled=true
          and c.driver_visible=true
      )
      and (
        v_lat is null
        or v_lng is null
        or r.pickup_latitude is null
        or r.pickup_longitude is null
        or (
          111.195 * sqrt(
            power((r.pickup_latitude - v_lat)::double precision,2) +
            power(
              ((r.pickup_longitude - v_lng)::double precision) *
              cos(radians(((r.pickup_latitude + v_lat) / 2)::double precision)),
              2
            )
          )
        ) <= least(greatest(v_radius,1),100)
      )
    order by r.created_at asc
    limit least(greatest(v_max_visible,1),100)
  ) x;

  return v_result;
end;
$$;
