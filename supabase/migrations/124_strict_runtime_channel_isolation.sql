-- Strict Preview/Production isolation for live operations and driver dispatch.
-- Mirrors the production migration applied on 2026-10-06.
-- 1) operational scope follows account_runtime_bindings;
-- 2) driver dispatch rejects a channel different from the account runtime;
-- 3) admin live payloads expose channel for trips/deliveries/activity.

CREATE OR REPLACE FUNCTION public.same_operational_scope(p_user_a uuid, p_user_b uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'app_private'
AS $function$
declare
  v_env_a text;
  v_env_b text;
  v_group_a uuid;
  v_group_b uuid;
begin
  if p_user_a is null or p_user_b is null then
    return false;
  end if;

  select lower(b.environment)
    into v_env_a
  from public.account_runtime_bindings b
  where b.user_id = p_user_a
  limit 1;

  if v_env_a is null then
    v_env_a := case when exists(
      select 1
      from public.audit_test_group_members m
      join public.audit_test_groups g on g.id = m.group_id
      where m.user_id = p_user_a
        and m.enabled = true
        and g.active = true
    ) then 'preview' else 'production' end;
  end if;

  select lower(b.environment)
    into v_env_b
  from public.account_runtime_bindings b
  where b.user_id = p_user_b
  limit 1;

  if v_env_b is null then
    v_env_b := case when exists(
      select 1
      from public.audit_test_group_members m
      join public.audit_test_groups g on g.id = m.group_id
      where m.user_id = p_user_b
        and m.enabled = true
        and g.active = true
    ) then 'preview' else 'production' end;
  end if;

  if v_env_a is distinct from v_env_b then
    return false;
  end if;

  if v_env_a = 'production' then
    return true;
  end if;

  if v_env_a <> 'preview' then
    return false;
  end if;

  select m.group_id
    into v_group_a
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_a
    and m.enabled = true
    and g.active = true
  order by m.updated_at desc nulls last, m.created_at desc
  limit 1;

  select m.group_id
    into v_group_b
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_b
    and m.enabled = true
    and g.active = true
  order by m.updated_at desc nulls last, m.created_at desc
  limit 1;

  return v_group_a is not null
    and v_group_b is not null
    and v_group_a = v_group_b;
end;
$function$

CREATE OR REPLACE FUNCTION public.available_ride_requests_for_driver_v2(p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_runtime jsonb;
  v_expected_channel text;
  v_s jsonb;
  v_enabled boolean:=false;
  v_enforcement boolean:=false;
  v_priority jsonb;
  v_level text:='medium';
  v_base jsonb;
  v_lat numeric;
  v_lng numeric;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false) is false then
    return '[]'::jsonb;
  end if;

  v_expected_channel:=public.normalize_runtime_channel(
    v_runtime->>'environment'
  );

  if v_channel is distinct from v_expected_channel then
    return '[]'::jsonb;
  end if;

  v_s:=public.driver_priority_settings_for(v_channel);
  v_enabled:=case when v_channel='preview'
    then coalesce((v_s->>'preview_enabled')::boolean,false)
    else coalesce((v_s->>'production_enabled')::boolean,false)
  end;
  v_enforcement:=case when v_channel='preview'
    then coalesce((v_s->>'preview_enforcement_enabled')::boolean,false)
    else coalesce((v_s->>'production_enforcement_enabled')::boolean,false)
  end;

  select coalesce(jsonb_agg(e),'[]'::jsonb)
  into v_base
  from jsonb_array_elements(
    coalesce(public.available_ride_requests_for_driver(),'[]'::jsonb)
  ) e
  where public.normalize_runtime_channel(e->>'channel')=v_channel;

  if coalesce(v_enabled,false) is false
     or coalesce(v_enforcement,false) is false then
    return v_base;
  end if;

  v_priority:=public.driver_priority_summary_for_v2(v_uid,v_channel);
  v_level:=coalesce(v_priority->>'level','medium');

  select latitude,longitude into v_lat,v_lng
  from public.driver_profiles where id=v_uid;

  select coalesce(
    jsonb_agg(x.payload order by x.rank_a,x.rank_b,x.rank_c,x.created_at),
    '[]'::jsonb
  )
  into v_result
  from (
    select
      e as payload,
      coalesce((e->>'created_at')::timestamptz,now()) as created_at,
      case
        when v_level in ('high','medium') then coalesce(
          public.geo_distance_km(
            v_lat,v_lng,
            nullif(e->>'pickup_latitude','')::numeric,
            nullif(e->>'pickup_longitude','')::numeric
          ),99999)
        else 0
      end as rank_a,
      case
        when v_level='high' then -coalesce(pr.passenger_rating,5)
        else 0
      end as rank_b,
      case
        when v_level in ('high','medium') then -coalesce(
          nullif(e->>'proposed_fare','')::numeric
          / nullif(nullif(e->>'route_distance_km','')::numeric,0),0
        )
        else 0
      end as rank_c
    from jsonb_array_elements(coalesce(v_base,'[]'::jsonb)) e
    left join lateral (
      select round(avg(r.score)::numeric,2) as passenger_rating
      from public.ratings r
      where r.to_user_id=nullif(e->>'passenger_id','')::uuid
        and r.rated_role='passenger'
    ) pr on true
  ) x;

  return coalesce(v_result,'[]'::jsonb);
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
  where dp.approval_status='approved'
    and dp.latitude is not null
    and dp.longitude is not null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'channel', t.channel,
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
  left join public.users pu on pu.id=t.passenger_id
  left join public.users du on du.id=t.driver_id
  where t.status not in ('completed','cancelled');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', d.id,
        'channel', d.channel,
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
  left join public.delivery_requests ed on ed.id=e.delivery_id
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
        'status',t.status,
        'title','Viaje',
        'subtitle',coalesce(rr.pickup_address,'Origen') || ' → ' ||
                   coalesce(rr.destination_address,'Destino'),
        'created_at',t.created_at
      ) as item
    from public.trips t
    left join public.ride_requests rr on rr.id=t.ride_request_id
    union all
    select
      d.created_at,
      jsonb_build_object(
        'kind','delivery',
        'id',d.id,
        'channel',d.channel,
        'status',d.status,
        'title','Delivery',
        'subtitle',coalesce(d.pickup_address,'Origen') || ' → ' ||
                   coalesce(d.dropoff_address,'Destino'),
        'created_at',d.created_at
      )
    from public.delivery_requests d
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
        'status',e.status,
        'title','SOS / Emergencia',
        'subtitle',coalesce(u.full_name,'Usuario Express'),
        'created_at',e.created_at
      )
    from public.emergency_events e
    left join public.users u on u.id=e.user_id
    left join public.trips et on et.id=e.trip_id
    left join public.delivery_requests ed on ed.id=e.delivery_id
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

