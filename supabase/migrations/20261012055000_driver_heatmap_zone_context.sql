-- Private, zone-scoped map context for the driver's single Web app.
-- Maps use request grid cells, not raw passenger GPS or profile locations.
create or replace function public.my_driver_heatmap_context(
  p_channel text default 'production'
) returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_bound_channel text;
  v_zone uuid;
  v_z public.service_zones%rowtype;
  v_enabled boolean:=false;
  v_window integer:=5;
  v_min_requests integer:=3;
  v_south numeric; v_north numeric;
  v_west numeric; v_east numeric;
  v_lat_d numeric; v_lng_d numeric;
  v_heat jsonb:='[]'::jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Autenticación requerida';
  end if;
  select coalesce(b.environment,'production') into v_bound_channel
  from public.account_runtime_bindings b where b.user_id=v_uid;
  v_bound_channel:=coalesce(v_bound_channel,'production');
  if v_channel<>v_bound_channel then
    raise exception 'Entorno no autorizado';
  end if;
  select dp.zone_id into v_zone from public.driver_profiles dp
  where dp.id=v_uid;
  if v_zone is null then
    return jsonb_build_object('bounds',null,'heat','[]'::jsonb);
  end if;
  select * into v_z from public.service_zones z
  where z.id=v_zone and z.active=true;
  if not found then
    return jsonb_build_object('bounds',null,'heat','[]'::jsonb);
  end if;

  select min((vertex.value->>'lat')::numeric),
         max((vertex.value->>'lat')::numeric),
         min((vertex.value->>'lng')::numeric),
         max((vertex.value->>'lng')::numeric)
  into v_south,v_north,v_west,v_east
  from public.service_zone_polygons z
  cross join lateral jsonb_array_elements(z.polygon) vertex(value)
  where z.zone_id=v_zone and z.active=true;

  if v_south is null or v_south=v_north
     or v_west is null or v_west=v_east then
    v_lat_d:=greatest(0.01,least(coalesce(v_z.radius_km,5),35)/111.0);
    v_lng_d:=v_lat_d/greatest(0.3,abs(cos(radians(
      coalesce(v_z.center_latitude,0)::double precision))));
    v_south:=coalesce(v_z.center_latitude,0)-v_lat_d;
    v_north:=coalesce(v_z.center_latitude,0)+v_lat_d;
    v_west:=coalesce(v_z.center_longitude,0)-v_lng_d;
    v_east:=coalesce(v_z.center_longitude,0)+v_lng_d;
  end if;

  select s.enabled,s.window_minutes,s.min_requests
  into v_enabled,v_window,v_min_requests
  from public.dynamic_pricing_channel_settings s
  where s.channel=v_channel;

  if coalesce(v_enabled,false) then
    select coalesce(jsonb_agg(jsonb_build_object(
      'latitude',(cells.cell_lat*0.004)::numeric(9,5),
      'longitude',(cells.cell_lng*0.004)::numeric(9,5),
      'multiplier',round(cells.multiplier,2),
      'requests',cells.requests,
      'radius_m',230
    ) order by cells.multiplier desc,cells.requests desc),'[]'::jsonb)
    into v_heat
    from (
      select round(rr.pickup_latitude::numeric/0.004)::integer cell_lat,
             round(rr.pickup_longitude::numeric/0.004)::integer cell_lng,
             max(rr.demand_multiplier)::numeric multiplier,
             count(*)::integer requests
      from public.ride_requests rr
      where rr.channel=v_channel and rr.zone_id=v_zone
        and rr.status='searching'
        and rr.created_at >= now()-make_interval(
          mins=>greatest(1,least(coalesce(v_window,5),30)))
        and rr.pickup_latitude is not null
        and rr.pickup_longitude is not null
        and rr.demand_multiplier>1.05
        and rr.pickup_address not like '[LOADTEST:%'
      group by 1,2
      having count(*)>=greatest(2,least(coalesce(v_min_requests,3),4))
      order by max(rr.demand_multiplier) desc,count(*) desc
      limit 12
    ) cells;
  end if;

  return jsonb_build_object(
    'zone_id',v_zone,
    'bounds',jsonb_build_object(
      'south',v_south,'north',v_north,'west',v_west,'east',v_east),
    'heat',coalesce(v_heat,'[]'::jsonb),
    'demand_enabled',coalesce(v_enabled,false)
  );
end;
$$;
revoke all on function public.my_driver_heatmap_context(text)
  from public,anon;
grant execute on function public.my_driver_heatmap_context(text)
  to authenticated;
