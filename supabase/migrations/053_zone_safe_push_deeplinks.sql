-- Zone-safe ride/offer push notifications with deep-link metadata.
-- Keeps notification center compatibility while attaching the ride identifiers
-- needed by Android to reopen the correct live flow.

alter table public.notifications
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create index if not exists notifications_user_type_created_idx
  on public.notifications(user_id,type,created_at desc);

create or replace function public.dispatch_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $function$
declare
  v_secret text;
begin
  select webhook_secret
    into v_secret
  from public.push_server_config
  where id = true;

  if v_secret is null then
    return new;
  end if;

  perform net.http_post(
    url := 'https://zgpijrznvaskgcmauwxx.supabase.co/functions/v1/express-push-dispatch',
    body := jsonb_build_object(
      'notification_id', new.id,
      'user_id', new.user_id,
      'title', new.title,
      'body', new.body,
      'type', new.type,
      'metadata', coalesce(new.metadata,'{}'::jsonb)
    ),
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-express-push-secret', v_secret
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$function$;

revoke execute on function public.dispatch_push_notification()
  from public, anon, authenticated;

create or replace function public.notify_available_ride_to_drivers()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_driver record;
  v_lock_driver uuid;
  v_radius numeric := 15;
begin
  if new.status <> 'searching' then return new; end if;
  if left(coalesce(new.pickup_address,''), 9) = '[LOADTEST' then return new; end if;
  if new.zone_id is null then return new; end if;

  if tg_op = 'UPDATE' then
    if old.status = 'searching'
       and old.expires_at is not distinct from new.expires_at
       and old.proposed_fare is not distinct from new.proposed_fare then
      return new;
    end if;
  end if;

  if new.scheduled_for is not null
     and new.scheduled_for > now() + interval '30 minutes' then
    return new;
  end if;

  select coalesce(
    (select max_driver_request_radius_km from public.app_settings where id=true),
    15
  ) into v_radius;

  for v_driver in
    select
      dp.id,
      public.geo_distance_km(
        new.pickup_latitude,
        new.pickup_longitude,
        dp.latitude,
        dp.longitude
      ) as distance_km
    from public.driver_profiles dp
    where dp.approval_status = 'approved'
      and dp.online_status = 'online'
      and dp.id <> new.passenger_id
      and dp.zone_id = new.zone_id
      and public.same_operational_scope(dp.id, new.passenger_id)
      and public.driver_subscription_allows_dispatch(dp.id)
      and exists(
        select 1
        from public.zone_service_catalog zs
        where zs.zone_id = new.zone_id
          and zs.service_key = new.category
          and zs.enabled = true
          and zs.driver_visible = true
      )
      and (
        new.pickup_latitude is null
        or new.pickup_longitude is null
        or dp.latitude is null
        or dp.longitude is null
        or public.geo_distance_km(
          new.pickup_latitude,
          new.pickup_longitude,
          dp.latitude,
          dp.longitude
        ) <= least(greatest(v_radius,1),100)
      )
    order by distance_km nulls last, dp.updated_at desc nulls last
  loop
    v_lock_driver := null;

    insert into public.driver_request_push_locks(
      driver_id,ride_request_id,locked_until,updated_at
    )
    values(
      v_driver.id,new.id,now()+interval '15 seconds',now()
    )
    on conflict (driver_id)
    do update set
      ride_request_id=excluded.ride_request_id,
      locked_until=excluded.locked_until,
      updated_at=now()
    where public.driver_request_push_locks.locked_until <= now()
    returning driver_id into v_lock_driver;

    if v_lock_driver is null then continue; end if;

    insert into public.notifications(user_id,title,body,type,metadata)
    values(
      v_driver.id,
      'Nueva solicitud disponible',
      'Tienes una nueva solicitud cercana. Abre Express para verla.',
      'ride_request',
      jsonb_build_object(
        'ride_request_id',new.id,
        'zone_id',new.zone_id,
        'mode','driver',
        'deep_link','ride_request'
      )
    );
  end loop;

  return new;
end;
$function$;

create or replace function public.notify_ride_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_passenger uuid;
  v_driver_name text;
  v_amount text;
  v_ride_zone uuid;
  v_driver_zone uuid;
begin
  select r.passenger_id,r.zone_id
    into v_passenger,v_ride_zone
  from public.ride_requests r
  where r.id = new.ride_request_id;

  if v_passenger is null then
    return new;
  end if;

  if new.driver_id = v_passenger then
    raise exception 'No puedes ofertar en tu propia solicitud';
  end if;

  if not public.same_operational_scope(v_passenger, new.driver_id) then
    raise exception 'Solicitud fuera de tu entorno operativo';
  end if;

  select dp.zone_id
    into v_driver_zone
  from public.driver_profiles dp
  where dp.id = new.driver_id;

  if v_ride_zone is null
     or v_driver_zone is null
     or v_driver_zone <> v_ride_zone then
    raise exception 'Solicitud fuera de la zona del conductor';
  end if;

  if not public.driver_subscription_allows_dispatch(new.driver_id) then
    raise exception 'Suscripción requerida para ofertar';
  end if;

  if new.status <> 'pending' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'pending'
     and old.proposed_fare is not distinct from new.proposed_fare
     and old.eta_minutes is not distinct from new.eta_minutes
     and old.expires_at is not distinct from new.expires_at then
    return new;
  end if;

  update public.ride_requests
  set status = 'offers_received', updated_at = now()
  where id = new.ride_request_id
    and status = 'searching';

  select nullif(trim(u.full_name), '')
    into v_driver_name
  from public.users u
  where u.id = new.driver_id;

  v_amount := trim(to_char(new.proposed_fare, 'FM999999990.00'));

  insert into public.notifications(user_id,title,body,type,metadata)
  values(
    v_passenger,
    'Nueva oferta de conductor',
    coalesce(v_driver_name,'Un conductor')
      || ' te ofrece Bs ' || v_amount || '. Revisa la oferta en Express.',
    'ride_offer',
    jsonb_build_object(
      'ride_request_id',new.ride_request_id,
      'offer_id',new.id,
      'driver_id',new.driver_id,
      'zone_id',v_ride_zone,
      'mode','passenger',
      'deep_link','ride_offer'
    )
  );

  return new;
end;
$function$;

create or replace function public.available_ride_requests_for_driver()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_scheduled_before integer := 30;
  v_visible_seconds integer := 180;
  v_max_visible integer := 20;
  v_radius numeric := 15;
  v_lat numeric;
  v_lng numeric;
  v_zone_id uuid;
  v_audit boolean := false;
  v_limit integer := 20;
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

  select exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid and m.enabled=true and g.active=true
  ) into v_audit;

  v_limit := case
    when v_audit then 250
    else least(greatest(v_max_visible,1),100)
  end;

  select latitude,longitude,zone_id
    into v_lat,v_lng,v_zone_id
  from public.driver_profiles
  where id=v_uid
  limit 1;

  if v_zone_id is null
     or not public.driver_subscription_allows_dispatch(v_uid) then
    return '[]'::jsonb;
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.created_at asc),
    '[]'::jsonb
  )
  into v_result
  from (
    select r.*
    from public.ride_requests r
    where r.status in ('searching','offers_received')
      and r.expires_at > now()
      and r.passenger_id <> v_uid
      and r.zone_id = v_zone_id
      and public.same_operational_scope(r.passenger_id,v_uid)
      and (
        r.scheduled_for is null
        or r.scheduled_for <=
          now()+make_interval(
            mins=>least(greatest(v_scheduled_before,5),1440)
          )
      )
      and (
        r.scheduled_for is not null
        or r.created_at >
          now()-make_interval(
            secs=>least(greatest(v_visible_seconds,30),1800)
          )
      )
      and exists(
        select 1
        from public.zone_service_catalog zs
        where zs.zone_id=v_zone_id
          and zs.service_key=r.category
          and zs.enabled=true
          and zs.driver_visible=true
      )
      and (
        v_lat is null
        or v_lng is null
        or r.pickup_latitude is null
        or r.pickup_longitude is null
        or public.geo_distance_km(
          v_lat,v_lng,r.pickup_latitude,r.pickup_longitude
        ) <= least(greatest(v_radius,1),100)
      )
    order by r.created_at asc
    limit v_limit
  ) x;

  return v_result;
end;
$function$;

revoke execute on function public.notify_available_ride_to_drivers()
  from public, anon, authenticated;
revoke execute on function public.notify_ride_offer()
  from public, anon, authenticated;
