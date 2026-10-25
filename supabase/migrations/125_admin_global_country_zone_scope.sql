-- Global country/zone scope support for the Express Admin.
-- Applied to Supabase on 2026-10-06.
-- Adds explicit geographic metadata to admin payloads and hardens manual dispatch.

CREATE OR REPLACE FUNCTION public.admin_available_drivers_v2(p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',dp.id,
          'name',coalesce(nullif(trim(u.full_name),''),'Conductor'),
          'phone',u.phone,
          'online_status',dp.online_status,
          'vehicle_summary',dp.vehicle_summary,
          'vehicle_types',coalesce((
            select jsonb_agg(dv.vehicle_type order by dv.created_at)
            from public.driver_vehicles dv
            where dv.driver_id=dp.id and dv.is_active=true
          ),'[]'::jsonb),
          'zone_id',dp.zone_id,
          'zone_key',z.zone_key,
          'zone_name',z.name,
          'country',z.country,
          'country_code',z.country_code,
          'city',dp.city,
          'latitude',dp.latitude,
          'longitude',dp.longitude,
          'rating',dp.rating,
          'channel',v_channel
        )
        order by dp.rating desc
      ),
      '[]'::jsonb
    )
    from public.driver_profiles dp
    join public.users u on u.id=dp.id
    left join public.service_zones z on z.id=dp.zone_id
    where dp.approval_status='approved'
      and u.account_status='active'
      and dp.online_status='online'
      and exists(
        select 1
        from public.native_push_tokens n
        where n.user_id=dp.id
          and n.active=true
          and n.channel=v_channel
      )
      and not exists(
        select 1 from public.trips t
        where t.driver_id=dp.id
          and t.status not in ('completed','cancelled')
      )
      and not exists(
        select 1 from public.delivery_requests d
        where d.courier_id=dp.id
          and d.status not in ('delivered','cancelled')
      )
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_open_service_requests_v2(p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'rides',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc),'[]'::jsonb)
      from (
        select
          r.*,
          u.full_name as passenger_name,
          z.zone_key,
          z.name as zone_name,
          z.city,
          z.region_department,
          z.country,
          z.country_code
        from public.ride_requests r
        left join public.users u on u.id=r.passenger_id
        left join public.service_zones z on z.id=r.zone_id
        where r.channel=v_channel
          and r.status in ('searching','offers_received')
          and (r.scheduled_for is not null or r.expires_at>now())
        order by r.created_at asc
      ) x
    ),
    'deliveries',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc),'[]'::jsonb)
      from (
        select
          d.*,
          u.full_name as customer_name,
          z.id as zone_id,
          z.zone_key,
          z.name as zone_name,
          z.city,
          z.region_department,
          z.country,
          z.country_code
        from public.delivery_requests d
        left join public.users u on u.id=d.customer_id
        left join lateral (
          select public.service_zone_id_for_point(
            d.pickup_latitude::numeric,
            d.pickup_longitude::numeric
          ) as zone_id
        ) dz on true
        left join public.service_zones z on z.id=dz.zone_id
        where d.channel=v_channel
          and d.status='searching'
          and d.courier_id is null
        order by d.created_at asc
      ) x
    )
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_delivery_list_v3(p_channel text DEFAULT 'production'::text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
    from (
      select
        d.id,d.status,d.proposed_fare,d.currency,d.payment_method,
        d.created_at,d.completed_at,d.channel,
        cu.full_name as customer_name,du.full_name as courier_name,
        d.pickup_address,d.dropoff_address,d.package_type,
        z.id as zone_id,z.zone_key,z.name as zone_name,z.city,
        z.region_department,z.country,z.country_code
      from public.delivery_requests d
      left join public.users cu on cu.id=d.customer_id
      left join public.users du on du.id=d.courier_id
      left join lateral (
        select public.service_zone_id_for_point(
          d.pickup_latitude::numeric,
          d.pickup_longitude::numeric
        ) as zone_id
      ) dz on true
      left join public.service_zones z on z.id=dz.zone_id
      where d.channel=v_channel
        and (p_from is null or d.created_at>=p_from)
        and (p_to is null or d.created_at<p_to)
        and (p_status is null or p_status='' or d.status=p_status)
      order by d.created_at desc
      limit greatest(1,least(coalesce(p_limit,100),500))
      offset greatest(0,coalesce(p_offset,0))
    ) x
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_assign_ride_v2(p_ride_request_id uuid, p_driver_id uuid, p_final_fare numeric DEFAULT NULL::numeric, p_channel text DEFAULT 'production'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_request_channel text;
  v_request_zone uuid;
  v_category text;
  v_driver_zone uuid;
  v_trip uuid;
  v_vehicle_ok boolean:=false;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select channel,zone_id,category
    into v_request_channel,v_request_zone,v_category
  from public.ride_requests
  where id=p_ride_request_id;

  if v_request_channel is distinct from v_channel then
    raise exception 'Viaje fuera del entorno seleccionado';
  end if;

  select zone_id into v_driver_zone
  from public.driver_profiles
  where id=p_driver_id;

  if v_request_zone is null
     or v_driver_zone is null
     or v_driver_zone is distinct from v_request_zone then
    raise exception 'Conductor fuera de la zona del viaje';
  end if;

  if not exists(
    select 1 from public.native_push_tokens
    where user_id=p_driver_id and active=true and channel=v_channel
  ) then
    raise exception 'Conductor fuera del entorno seleccionado';
  end if;

  select exists(
    select 1
    from public.driver_vehicles dv
    where dv.driver_id=p_driver_id
      and dv.is_active=true
      and (
        (v_category='motorcycle' and dv.vehicle_type='motorcycle')
        or (v_category='xl' and dv.vehicle_type='xl')
        or (v_category in ('economy','comfort') and dv.vehicle_type in ('car','xl'))
        or (v_category not in ('motorcycle','xl','economy','comfort'))
      )
  ) into v_vehicle_ok;

  if not coalesce(v_vehicle_ok,false) then
    raise exception 'El vehículo del conductor no es compatible con la categoría del viaje';
  end if;

  perform set_config('app.runtime_channel',v_channel,true);
  v_trip:=public.admin_assign_ride(
    p_ride_request_id,p_driver_id,p_final_fare
  );
  return v_trip;
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_dashboard_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_today timestamptz := date_trunc('day', now());
  v_metrics jsonb;
  v_drivers jsonb;
  v_trips jsonb;
  v_deliveries jsonb;
  v_emergencies jsonb;
  v_activity jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'users_total', (select count(*) from public.users),
    'drivers_total', (select count(*) from public.driver_profiles),
    'drivers_online', (
      select count(*) from public.driver_profiles
      where approval_status='approved' and online_status='online'
    ),
    'drivers_pending', (
      select count(*) from public.driver_profiles
      where approval_status='pending'
    ),
    'ride_searching', (
      select count(*) from public.ride_requests
      where status in ('searching','offers_received')
        and expires_at > v_now
    ),
    'active_trips', (
      select count(*) from public.trips
      where status not in ('completed','cancelled')
    ),
    'trips_today', (
      select count(*) from public.trips
      where created_at >= v_today
    ),
    'completed_today', (
      select count(*) from public.trips
      where status='completed'
        and coalesce(completed_at, created_at) >= v_today
    ),
    'cancelled_today', (
      select
        (select count(*) from public.trips
         where status='cancelled' and created_at >= v_today)
        +
        (select count(*) from public.ride_requests
         where status='cancelled' and created_at >= v_today)
    ),
    'delivery_searching', (
      select count(*) from public.delivery_requests
      where status='searching'
    ),
    'active_deliveries', (
      select count(*) from public.delivery_requests
      where status not in ('delivered','cancelled','searching')
    ),
    'deliveries_today', (
      select count(*) from public.delivery_requests
      where created_at >= v_today
    ),
    'completed_deliveries_today', (
      select count(*) from public.delivery_requests
      where status='delivered'
        and coalesce(completed_at, created_at) >= v_today
    ),
    'open_emergencies', (
      select count(*) from public.emergency_events
      where status not in ('resolved','closed')
    ),
    'paid_volume_today', (
      select coalesce(sum(amount),0)
      from public.payment_transactions
      where status='paid'
        and coalesce(paid_at,created_at) >= v_today
    )
  )
  into v_metrics;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', dp.id,
        'zone_id', dp.zone_id,
        'zone_key', z.zone_key,
        'zone_name', z.name,
        'country', z.country,
        'country_code', z.country_code,
        'name', coalesce(nullif(trim(u.full_name),''),'Conductor'),
        'phone', u.phone,
        'approval_status', dp.approval_status,
        'online_status', dp.online_status,
        'vehicle_summary', dp.vehicle_summary,
        'city', dp.city,
        'latitude', dp.latitude,
        'longitude', dp.longitude,
        'rating', dp.rating,
        'completed_trips', dp.completed_trips,
        'updated_at', dp.updated_at
      )
      order by
        case when dp.online_status='online' then 0 else 1 end,
        dp.updated_at desc
    ),
    '[]'::jsonb
  )
  into v_drivers
  from public.driver_profiles dp
  left join public.users u on u.id=dp.id
  left join public.service_zones z on z.id=dp.zone_id
  where dp.approval_status='approved'
    and dp.latitude is not null
    and dp.longitude is not null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'channel', t.channel,
        'zone_id', rr.zone_id,
        'zone_key', z.zone_key,
        'zone_name', z.name,
        'country', z.country,
        'country_code', z.country_code,
        'status', t.status,
        'final_fare', t.final_fare,
        'payment_status', t.payment_status,
        'created_at', t.created_at,
        'passenger_id', t.passenger_id,
        'driver_id', t.driver_id,
        'passenger_name', pu.full_name,
        'driver_name', du.full_name,
        'pickup_address', rr.pickup_address,
        'pickup_latitude', rr.pickup_latitude,
        'pickup_longitude', rr.pickup_longitude,
        'destination_address', rr.destination_address,
        'destination_latitude', rr.destination_latitude,
        'destination_longitude', rr.destination_longitude,
        'category', rr.category
      )
      order by t.created_at desc
    ),
    '[]'::jsonb
  )
  into v_trips
  from public.trips t
  left join public.ride_requests rr on rr.id=t.ride_request_id
  left join public.service_zones z on z.id=rr.zone_id
  left join public.users pu on pu.id=t.passenger_id
  left join public.users du on du.id=t.driver_id
  where t.status not in ('completed','cancelled');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', d.id,
        'channel', d.channel,
        'zone_id', z.id,
        'zone_key', z.zone_key,
        'zone_name', z.name,
        'country', z.country,
        'country_code', z.country_code,
        'status', d.status,
        'proposed_fare', d.proposed_fare,
        'payment_method', d.payment_method,
        'created_at', d.created_at,
        'customer_id', d.customer_id,
        'courier_id', d.courier_id,
        'customer_name', cu.full_name,
        'courier_name', du.full_name,
        'pickup_address', d.pickup_address,
        'pickup_latitude', d.pickup_latitude,
        'pickup_longitude', d.pickup_longitude,
        'dropoff_address', d.dropoff_address,
        'dropoff_latitude', d.dropoff_latitude,
        'dropoff_longitude', d.dropoff_longitude,
        'package_type', d.package_type
      )
      order by d.created_at desc
    ),
    '[]'::jsonb
  )
  into v_deliveries
  from public.delivery_requests d
  left join public.users cu on cu.id=d.customer_id
  left join public.users du on du.id=d.courier_id
  left join lateral (
    select public.service_zone_id_for_point(
      d.pickup_latitude::numeric,
      d.pickup_longitude::numeric
    ) as zone_id
  ) dz on true
  left join public.service_zones z on z.id=dz.zone_id
  where d.status not in ('delivered','cancelled');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'channel', coalesce(
          et.channel,
          ed.channel,
          case
            when lower(coalesce(erb.environment,''))='preview'
              then 'preview'
            else 'production'
          end
        ),
        'zone_id', ez.id,
        'zone_key', ez.zone_key,
        'zone_name', ez.name,
        'country', ez.country,
        'country_code', ez.country_code,
        'user_id', e.user_id,
        'user_name', u.full_name,
        'trip_id', e.trip_id,
        'delivery_id', e.delivery_id,
        'latitude', e.latitude,
        'longitude', e.longitude,
        'status', e.status,
        'created_at', e.created_at
      )
      order by e.created_at desc
    ),
    '[]'::jsonb
  )
  into v_emergencies
  from public.emergency_events e
  left join public.users u on u.id=e.user_id
  left join public.trips et on et.id=e.trip_id
  left join public.ride_requests err on err.id=et.ride_request_id
  left join public.delivery_requests ed on ed.id=e.delivery_id
  left join lateral (
    select public.service_zone_id_for_point(
      ed.pickup_latitude::numeric,
      ed.pickup_longitude::numeric
    ) as zone_id
  ) edz on true
  left join public.service_zones ez
    on ez.id=coalesce(err.zone_id,edz.zone_id,u.last_zone_id)
  left join public.account_runtime_bindings erb on erb.user_id=e.user_id
  where e.status not in ('resolved','closed');

  select coalesce(
    jsonb_agg(x.item order by x.ts desc),
    '[]'::jsonb
  )
  into v_activity
  from (
    select
      t.created_at as ts,
      jsonb_build_object(
        'kind','trip',
        'id',t.id,
        'channel',t.channel,
        'zone_id',rr.zone_id,
        'country_code',z.country_code,
        'status',t.status,
        'title','Viaje',
        'subtitle',coalesce(rr.pickup_address,'Origen') || ' → ' ||
                   coalesce(rr.destination_address,'Destino'),
        'created_at',t.created_at
      ) as item
    from public.trips t
    left join public.ride_requests rr on rr.id=t.ride_request_id
    left join public.service_zones z on z.id=rr.zone_id
    union all
    select
      d.created_at,
      jsonb_build_object(
        'kind','delivery',
        'id',d.id,
        'channel',d.channel,
        'zone_id',dz2.id,
        'country_code',dz2.country_code,
        'status',d.status,
        'title','Delivery',
        'subtitle',coalesce(d.pickup_address,'Origen') || ' → ' ||
                   coalesce(d.dropoff_address,'Destino'),
        'created_at',d.created_at
      )
    from public.delivery_requests d
    left join lateral (
      select public.service_zone_id_for_point(
        d.pickup_latitude::numeric,
        d.pickup_longitude::numeric
      ) as zone_id
    ) dzl on true
    left join public.service_zones dz2 on dz2.id=dzl.zone_id
    union all
    select
      e.created_at,
      jsonb_build_object(
        'kind','emergency',
        'id',e.id,
        'channel',coalesce(
          et.channel,
          ed.channel,
          case
            when lower(coalesce(erb.environment,''))='preview'
              then 'preview'
            else 'production'
          end
        ),
        'zone_id',esz.id,
        'country_code',esz.country_code,
        'status',e.status,
        'title','SOS / Emergencia',
        'subtitle',coalesce(u.full_name,'Usuario Express'),
        'created_at',e.created_at
      )
    from public.emergency_events e
    left join public.users u on u.id=e.user_id
    left join public.trips et on et.id=e.trip_id
    left join public.ride_requests erq on erq.id=et.ride_request_id
    left join public.delivery_requests ed on ed.id=e.delivery_id
    left join lateral (
      select public.service_zone_id_for_point(
        ed.pickup_latitude::numeric,
        ed.pickup_longitude::numeric
      ) as zone_id
    ) edzl on true
    left join public.service_zones esz
      on esz.id=coalesce(erq.zone_id,edzl.zone_id,u.last_zone_id)
    left join public.account_runtime_bindings erb on erb.user_id=e.user_id
    order by 1 desc
    limit 30
  ) x;

  return jsonb_build_object(
    'metrics', v_metrics,
    'drivers', v_drivers,
    'active_trips', v_trips,
    'active_deliveries', v_deliveries,
    'emergencies', v_emergencies,
    'activity', v_activity,
    'generated_at', v_now
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_marketplace_phase2_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'zones',(
      select coalesce(
        jsonb_agg(
          to_jsonb(s) || jsonb_build_object(
            'zone_key',z.zone_key,
            'zone_name',z.name,
            'country',z.country,
            'country_code',z.country_code,
            'currency_code',z.currency_code
          )
          order by z.country,z.city,z.name
        ),
        '[]'::jsonb
      )
      from public.marketplace_zone_settings s
      join public.service_zones z on z.id=s.zone_id
    ),
    'plus_plans',(
      select coalesce(
        jsonb_agg(
          to_jsonb(p) || jsonb_build_object(
            'zone_key',z.zone_key,
            'zone_name',z.name,
            'country',z.country,
            'country_code',z.country_code
          )
          order by z.name,p.name
        ),
        '[]'::jsonb
      )
      from public.marketplace_plus_plans p
      join public.service_zones z on z.id=p.zone_id
    ),
    'benefits',(
      select coalesce(
        jsonb_agg(
          to_jsonb(b) || jsonb_build_object(
            'merchant_name',m.name,
            'zone_id',m.zone_id,
            'country',z.country,
            'country_code',z.country_code
          )
          order by m.name
        ),
        '[]'::jsonb
      )
      from public.marketplace_plus_merchant_benefits b
      join public.marketplace_merchants m on m.id=b.merchant_id
      left join public.service_zones z on z.id=m.zone_id
    ),
    'merchants',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id',m.id,
            'name',m.name,
            'zone_id',m.zone_id,
            'zone_key',z.zone_key,
            'zone_name',z.name,
            'country',z.country,
            'country_code',z.country_code,
            'active',m.active
          )
          order by z.name,m.name
        ),
        '[]'::jsonb
      )
      from public.marketplace_merchants m
      left join public.service_zones z on z.id=m.zone_id
    ),
    'recent_orders',(
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.created_at desc),
        '[]'::jsonb
      )
      from (
        select
          o.id,o.channel,o.status,o.payment_method,o.payment_status,
          o.currency_code,o.total_amount,o.driver_payout,
          o.tip_amount,o.express_margin,o.created_at,
          o.transfer_receipt_url,o.transfer_submitted_at,
          o.zone_id,
          m.name merchant_name,
          z.zone_key,z.name as zone_name,z.country,z.country_code
        from public.marketplace_orders o
        join public.marketplace_merchants m on m.id=o.merchant_id
        join public.service_zones z on z.id=o.zone_id
        order by o.created_at desc
        limit 50
      ) x
    )
  );
end;
$function$

