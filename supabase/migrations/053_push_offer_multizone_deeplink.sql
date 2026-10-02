-- Multizone push hardening for ride requests and offers.
-- Keeps production behavior, but scopes request pushes to the driver's zone/service
-- and carries ride/offer identifiers through the notification pipeline.

alter table public.notifications
  add column if not exists ride_request_id uuid
    references public.ride_requests(id) on delete set null,
  add column if not exists offer_id uuid
    references public.driver_offers(id) on delete set null;

create index if not exists notifications_ride_request_id_idx
  on public.notifications(ride_request_id)
  where ride_request_id is not null;

create index if not exists notifications_offer_id_idx
  on public.notifications(offer_id)
  where offer_id is not null;

create or replace function public.notify_available_ride_to_drivers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver record;
  v_lock_driver uuid;
  v_radius numeric := 10;
  v_scheduled_before integer := 30;
begin
  if new.status <> 'searching' then
    return new;
  end if;

  -- Synthetic load-test requests must never generate production push traffic.
  if left(coalesce(new.pickup_address,''), 9) = '[LOADTEST' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.status = 'searching'
       and old.expires_at is not distinct from new.expires_at
       and old.proposed_fare is not distinct from new.proposed_fare then
      return new;
    end if;
  end if;

  select
    coalesce(max_driver_request_radius_km, 10),
    coalesce(scheduled_publish_before_minutes, 30)
  into v_radius, v_scheduled_before
  from public.app_settings
  where id = true;

  if new.scheduled_for is not null
     and new.scheduled_for >
       now() + make_interval(mins => least(greatest(v_scheduled_before, 5), 1440)) then
    return new;
  end if;

  for v_driver in
    select
      dp.id,
      case
        when new.pickup_latitude is null
          or new.pickup_longitude is null
          or dp.latitude is null
          or dp.longitude is null
        then null::numeric
        else public.geo_distance_km(
          new.pickup_latitude,
          new.pickup_longitude,
          dp.latitude,
          dp.longitude
        )
      end as distance_km
    from public.driver_profiles dp
    where dp.approval_status = 'approved'
      and dp.online_status = 'online'
      and dp.id <> new.passenger_id
      and public.same_operational_scope(dp.id, new.passenger_id)
      and public.driver_subscription_allows_dispatch(dp.id)

      -- Once a request has a zone, only drivers assigned to that same zone
      -- are eligible for the push.
      and (
        new.zone_id is null
        or dp.zone_id = new.zone_id
      )

      -- Respect the service catalog for the request's zone. Legacy requests
      -- without zone_id keep the global service-catalog fallback.
      and (
        (
          new.zone_id is not null
          and exists(
            select 1
            from public.zone_service_catalog zs
            where zs.zone_id = new.zone_id
              and zs.service_key = new.category
              and zs.enabled = true
              and zs.driver_visible = true
          )
        )
        or
        (
          new.zone_id is null
          and exists(
            select 1
            from public.service_catalog c
            where c.service_key = new.category
              and c.enabled = true
              and c.driver_visible = true
          )
        )
      )

      -- Distance remains a secondary filter inside the correct operational
      -- zone. Missing coordinates do not silently discard a valid request.
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
        ) <= least(greatest(v_radius, 1), 100)
      )
    order by distance_km nulls last, dp.updated_at desc nulls last
  loop
    v_lock_driver := null;

    insert into public.driver_request_push_locks(
      driver_id, ride_request_id, locked_until, updated_at
    )
    values(
      v_driver.id,
      new.id,
      now() + interval '15 seconds',
      now()
    )
    on conflict (driver_id)
    do update set
      ride_request_id = excluded.ride_request_id,
      locked_until = excluded.locked_until,
      updated_at = now()
    where public.driver_request_push_locks.locked_until <= now()
    returning driver_id into v_lock_driver;

    if v_lock_driver is null then
      continue;
    end if;

    insert into public.notifications(
      user_id, title, body, type, ride_request_id
    )
    values(
      v_driver.id,
      'Nueva solicitud disponible',
      'Tienes una nueva solicitud cercana. Abre Express para verla.',
      'ride_request',
      new.id
    );
  end loop;

  return new;
end;
$$;

create or replace function public.notify_ride_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger uuid;
  v_driver_name text;
  v_amount text;
begin
  select r.passenger_id into v_passenger
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
  where id = new.ride_request_id and status = 'searching';

  select nullif(trim(u.full_name), '') into v_driver_name
  from public.users u
  where u.id = new.driver_id;

  v_amount := trim(to_char(new.proposed_fare, 'FM999999990.00'));

  insert into public.notifications(
    user_id, title, body, type, ride_request_id, offer_id
  )
  values(
    v_passenger,
    'Nueva oferta de conductor',
    coalesce(v_driver_name, 'Un conductor') ||
      ' te ofrece Bs ' || v_amount || '. Revisa la oferta en Express.',
    'ride_offer',
    new.ride_request_id,
    new.id
  );

  return new;
end;
$$;

-- Include the target identifiers in the payload sent to Web Push / FCM.
create or replace function public.dispatch_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $$
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
      'ride_request_id', new.ride_request_id,
      'offer_id', new.offer_id
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
$$;

revoke execute on function public.dispatch_push_notification()
  from public, anon, authenticated;
