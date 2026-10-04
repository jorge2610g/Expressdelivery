-- Enforce runtime isolation between Passenger and Driver in the single Express app.
-- Safe/backward-compatible: no columns are removed and existing active services
-- are never forced offline by the cleanup.

create or replace function public.guard_user_driver_mode_transition()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.active_mode is not distinct from old.active_mode then
    return new;
  end if;

  if coalesce(new.active_mode,'passenger') <> 'driver' then
    if exists (
      select 1
      from public.trips t
      where t.driver_id = new.id
        and t.status not in ('completed','cancelled')
    ) or exists (
      select 1
      from public.delivery_requests d
      where d.courier_id = new.id
        and d.status not in ('delivered','cancelled')
    ) then
      raise exception 'No puedes cambiar a Pasajero mientras tienes un servicio activo';
    end if;

    update public.driver_profiles
    set online_status='offline',
        updated_at=now()
    where id=new.id
      and online_status <> 'offline';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_user_driver_mode_transition
  on public.users;
create trigger guard_user_driver_mode_transition
before update of active_mode on public.users
for each row execute function public.guard_user_driver_mode_transition();

create or replace function public.guard_driver_online_requires_driver_mode()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.online_status in ('online','busy') then
    if not exists (
      select 1
      from public.users u
      where u.id=new.id
        and u.account_status='active'
        and u.active_mode='driver'
    ) then
      raise exception 'Debes estar en modo Conductor para conectarte';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_driver_online_mode_insert
  on public.driver_profiles;
create trigger guard_driver_online_mode_insert
before insert on public.driver_profiles
for each row execute function public.guard_driver_online_requires_driver_mode();

drop trigger if exists guard_driver_online_mode_update
  on public.driver_profiles;
create trigger guard_driver_online_mode_update
before update of online_status on public.driver_profiles
for each row execute function public.guard_driver_online_requires_driver_mode();

-- Repair only stale availability with no active service. Active trips/deliveries
-- remain untouched and are protected by the mode-transition guard above.
update public.driver_profiles dp
set online_status='offline',
    updated_at=now()
from public.users u
where u.id=dp.id
  and dp.online_status='online'
  and coalesce(u.active_mode,'passenger') <> 'driver'
  and not exists (
    select 1 from public.trips t
    where t.driver_id=dp.id
      and t.status not in ('completed','cancelled')
  )
  and not exists (
    select 1 from public.delivery_requests d
    where d.courier_id=dp.id
      and d.status not in ('delivered','cancelled')
  );

-- Defense in depth: dispatch must never notify a user whose current runtime is
-- Passenger even if an old client left driver_profiles.online_status stale.
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
    join public.users u on u.id=dp.id
    where dp.approval_status = 'approved'
      and dp.online_status = 'online'
      and u.account_status = 'active'
      and u.active_mode = 'driver'
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
    values(v_driver.id,new.id,now()+interval '15 seconds',now())
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

revoke all on function public.guard_user_driver_mode_transition()
from public,anon,authenticated;
revoke all on function public.guard_driver_online_requires_driver_mode()
from public,anon,authenticated;
