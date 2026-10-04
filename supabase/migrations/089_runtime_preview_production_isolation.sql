-- Runtime isolation between Preview and Production.
-- Existing operational data is intentionally treated as Preview.
-- Legacy clients remain safe because new rows default to production.

alter table public.ride_requests
  add column if not exists channel text not null default 'production';
alter table public.delivery_requests
  add column if not exists channel text not null default 'production';
alter table public.driver_offers
  add column if not exists channel text not null default 'production';
alter table public.trips
  add column if not exists channel text not null default 'production';
alter table public.native_push_tokens
  add column if not exists channel text not null default 'production';
alter table public.notifications
  add column if not exists channel text not null default 'production';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname='ride_requests_channel_check'
  ) then
    alter table public.ride_requests
      add constraint ride_requests_channel_check
      check (channel in ('preview','production'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname='delivery_requests_channel_check'
  ) then
    alter table public.delivery_requests
      add constraint delivery_requests_channel_check
      check (channel in ('preview','production'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname='driver_offers_channel_check'
  ) then
    alter table public.driver_offers
      add constraint driver_offers_channel_check
      check (channel in ('preview','production'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname='trips_channel_check'
  ) then
    alter table public.trips
      add constraint trips_channel_check
      check (channel in ('preview','production'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname='native_push_tokens_channel_check'
  ) then
    alter table public.native_push_tokens
      add constraint native_push_tokens_channel_check
      check (channel in ('preview','production'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname='notifications_channel_check'
  ) then
    alter table public.notifications
      add constraint notifications_channel_check
      check (channel in ('preview','production'));
  end if;
end $$;

-- Preserve real customer history in Production.
-- Only dedicated QA/sandbox identities are migrated to Preview.
update public.ride_requests r
set channel='preview'
where exists(
  select 1
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id=m.group_id
  where m.user_id=r.passenger_id
    and m.enabled=true
    and g.active=true
);

update public.delivery_requests d
set channel='preview'
where exists(
  select 1
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id=m.group_id
  where m.user_id=d.customer_id
    and m.enabled=true
    and g.active=true
)
or exists(
  select 1
  from public.marketplace_orders o
  where o.id=d.marketplace_order_id
    and o.channel='preview'
);

-- Updating an old offer must not re-fire offer notifications/telemetry.
alter table public.driver_offers
  disable trigger trg_notify_ride_offer;
alter table public.driver_offers
  disable trigger trg_log_driver_offer_flow_event;

update public.driver_offers o
set channel=r.channel
from public.ride_requests r
where r.id=o.ride_request_id
  and o.channel is distinct from r.channel;

alter table public.driver_offers
  enable trigger trg_log_driver_offer_flow_event;
alter table public.driver_offers
  enable trigger trg_notify_ride_offer;

update public.trips t
set channel=r.channel
from public.ride_requests r
where r.id=t.ride_request_id
  and t.channel is distinct from r.channel;

-- Existing installed Play Store tokens remain Production.
-- Preview tokens move to Preview automatically on their next registration.
update public.native_push_tokens
set channel='production'
where channel is distinct from 'production';

create index if not exists ride_requests_channel_status_created_idx
  on public.ride_requests(channel,status,created_at desc);
create index if not exists delivery_requests_channel_status_created_idx
  on public.delivery_requests(channel,status,created_at desc);
create index if not exists driver_offers_channel_request_idx
  on public.driver_offers(channel,ride_request_id,status);
create index if not exists trips_channel_created_idx
  on public.trips(channel,created_at desc);
create index if not exists native_push_tokens_user_channel_active_idx
  on public.native_push_tokens(user_id,channel,active);
create index if not exists notifications_user_channel_created_idx
  on public.notifications(user_id,channel,created_at desc);

create or replace function public.normalize_runtime_channel(p_channel text)
returns text
language sql
immutable
as $func$
  select case
    when lower(trim(coalesce(p_channel,'')))='preview' then 'preview'
    else 'production'
  end
$func$;

create or replace function public.is_active_audit_user(p_user_id uuid)
returns boolean
language sql
stable security definer
set search_path=public
as $func$
  select exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=p_user_id
      and m.enabled=true
      and g.active=true
  )
$func$;

create or replace function public.guard_request_runtime_channel()
returns trigger
language plpgsql
security definer
set search_path=public
as $func$
declare
  v_user uuid;
begin
  new.channel:=public.normalize_runtime_channel(new.channel);
  v_user:=case
    when tg_table_name='ride_requests' then new.passenger_id
    else new.customer_id
  end;

  if new.channel='preview'
     and not public.is_active_audit_user(v_user) then
    raise exception 'Preview requiere una cuenta QA/sandbox activa';
  end if;

  return new;
end;
$func$;

drop trigger if exists trg_guard_ride_request_runtime_channel
on public.ride_requests;
create trigger trg_guard_ride_request_runtime_channel
before insert or update of channel,passenger_id
on public.ride_requests
for each row execute function public.guard_request_runtime_channel();

drop trigger if exists trg_guard_delivery_request_runtime_channel
on public.delivery_requests;
create trigger trg_guard_delivery_request_runtime_channel
before insert or update of channel,customer_id
on public.delivery_requests
for each row execute function public.guard_request_runtime_channel();

create or replace function public.sync_trip_runtime_channel()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if new.ride_request_id is not null then
    select r.channel into new.channel
    from public.ride_requests r
    where r.id=new.ride_request_id;
  end if;
  new.channel:=public.normalize_runtime_channel(new.channel);
  return new;
end;
$$;

drop trigger if exists trg_sync_trip_runtime_channel on public.trips;
create trigger trg_sync_trip_runtime_channel
before insert or update of ride_request_id
on public.trips
for each row execute function public.sync_trip_runtime_channel();

create or replace function public.sync_delivery_runtime_channel()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if new.marketplace_order_id is not null then
    select o.channel into new.channel
    from public.marketplace_orders o
    where o.id=new.marketplace_order_id;
  end if;
  new.channel:=public.normalize_runtime_channel(new.channel);
  return new;
end;
$$;

drop trigger if exists trg_sync_delivery_runtime_channel
on public.delivery_requests;
create trigger trg_sync_delivery_runtime_channel
before insert or update of marketplace_order_id
on public.delivery_requests
for each row execute function public.sync_delivery_runtime_channel();

create or replace function public.guard_driver_offer_runtime_channel()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_channel text;
begin
  select r.channel into v_channel
  from public.ride_requests r
  where r.id=new.ride_request_id;

  if v_channel is null then
    raise exception 'Solicitud no disponible';
  end if;

  new.channel:=public.normalize_runtime_channel(new.channel);
  if new.channel<>v_channel then
    raise exception 'Oferta fuera del entorno operativo';
  end if;
  if new.channel='preview'
     and not public.is_active_audit_user(new.driver_id) then
    raise exception 'Preview requiere un conductor QA/sandbox activo';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_driver_offer_runtime_channel
on public.driver_offers;
create trigger trg_guard_driver_offer_runtime_channel
before insert or update of ride_request_id,channel
on public.driver_offers
for each row execute function public.guard_driver_offer_runtime_channel();

create or replace function public.notification_runtime_channel()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_channel text:=nullif(current_setting('app.runtime_channel',true),'');
  v_id uuid;
begin
  if v_channel not in ('preview','production') then
    v_channel:=null;
  end if;

  if v_channel is null and new.metadata ? 'ride_request_id' then
    begin
      v_id:=(new.metadata->>'ride_request_id')::uuid;
      select channel into v_channel from public.ride_requests where id=v_id;
    exception when others then null;
    end;
  end if;

  if v_channel is null and new.metadata ? 'trip_id' then
    begin
      v_id:=(new.metadata->>'trip_id')::uuid;
      select channel into v_channel from public.trips where id=v_id;
    exception when others then null;
    end;
  end if;

  if v_channel is null and new.metadata ? 'delivery_id' then
    begin
      v_id:=(new.metadata->>'delivery_id')::uuid;
      select channel into v_channel from public.delivery_requests where id=v_id;
    exception when others then null;
    end;
  end if;

  new.channel:=public.normalize_runtime_channel(v_channel);
  new.metadata:=coalesce(new.metadata,'{}'::jsonb)
    || jsonb_build_object('channel',new.channel);
  return new;
end;
$$;

drop trigger if exists trg_notification_runtime_channel
on public.notifications;
create trigger trg_notification_runtime_channel
before insert or update of metadata
on public.notifications
for each row execute function public.notification_runtime_channel();

create or replace function public.register_native_push_token_v2(
  p_token text,
  p_platform text default 'android',
  p_device_label text default null,
  p_channel text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_id uuid;
  v_platform text:=lower(coalesce(nullif(trim(p_platform),''),'android'));
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if p_token is null or length(trim(p_token))<20 then
    raise exception 'Token push inválido';
  end if;
  if v_platform not in ('android','ios') then
    raise exception 'Plataforma push inválida';
  end if;
  if v_channel='preview'
     and not public.is_active_audit_user(v_uid) then
    raise exception 'Preview requiere una cuenta QA/sandbox activa';
  end if;

  insert into public.native_push_tokens(
    user_id,token,platform,device_label,channel,
    active,last_seen_at,updated_at
  )
  values(
    v_uid,trim(p_token),v_platform,
    nullif(trim(coalesce(p_device_label,'')),''),
    v_channel,true,now(),now()
  )
  on conflict(token)
  do update set
    user_id=excluded.user_id,
    platform=excluded.platform,
    device_label=coalesce(
      excluded.device_label,
      public.native_push_tokens.device_label
    ),
    channel=excluded.channel,
    active=true,
    last_seen_at=now(),
    updated_at=now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.register_native_push_token_v2(text,text,text,text)
from public,anon;
grant execute on function public.register_native_push_token_v2(text,text,text,text)
to authenticated;

create or replace function public.admin_trip_list_v3(
  p_channel text default 'production',
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_zone_id uuid default null,
  p_status text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
    from (
      select
        t.id,t.status,t.final_fare,t.payment_status,t.created_at,t.completed_at,
        t.channel,
        pu.full_name as passenger_name,du.full_name as driver_name,
        rr.pickup_address,rr.destination_address,rr.category,rr.currency,
        rr.payment_method,rr.zone_id,z.name as zone_name,z.city,
        z.region_department,z.country
      from public.trips t
      left join public.ride_requests rr on rr.id=t.ride_request_id
      left join public.users pu on pu.id=t.passenger_id
      left join public.users du on du.id=t.driver_id
      left join public.service_zones z on z.id=rr.zone_id
      where t.channel=v_channel
        and rr.channel=v_channel
        and (p_from is null or t.created_at>=p_from)
        and (p_to is null or t.created_at<p_to)
        and (p_zone_id is null or rr.zone_id=p_zone_id)
        and (p_status is null or p_status='' or t.status=p_status)
      order by t.created_at desc
      limit greatest(1,least(coalesce(p_limit,100),500))
      offset greatest(0,coalesce(p_offset,0))
    ) x
  );
end;
$$;

create or replace function public.admin_delivery_list_v3(
  p_channel text default 'production',
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_status text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
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
        d.pickup_address,d.dropoff_address,d.package_type
      from public.delivery_requests d
      left join public.users cu on cu.id=d.customer_id
      left join public.users du on du.id=d.courier_id
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
$$;

create or replace function public.admin_open_service_requests_v2(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'rides',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc),'[]'::jsonb)
      from (
        select r.*,u.full_name as passenger_name
        from public.ride_requests r
        left join public.users u on u.id=r.passenger_id
        where r.channel=v_channel
          and r.status in ('searching','offers_received')
          and (r.scheduled_for is not null or r.expires_at>now())
        order by r.created_at asc
      ) x
    ),
    'deliveries',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc),'[]'::jsonb)
      from (
        select d.*,u.full_name as customer_name
        from public.delivery_requests d
        left join public.users u on u.id=d.customer_id
        where d.channel=v_channel
          and d.status='searching'
          and d.courier_id is null
        order by d.created_at asc
      ) x
    )
  );
end;
$$;

create or replace function public.admin_available_drivers_v2(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
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
$$;

create or replace function public.admin_assign_ride_v2(
  p_ride_request_id uuid,
  p_driver_id uuid,
  p_final_fare numeric default null,
  p_channel text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_request_channel text;
  v_trip uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select channel into v_request_channel
  from public.ride_requests
  where id=p_ride_request_id;

  if v_request_channel is distinct from v_channel then
    raise exception 'Viaje fuera del entorno seleccionado';
  end if;

  if not exists(
    select 1 from public.native_push_tokens
    where user_id=p_driver_id and active=true and channel=v_channel
  ) then
    raise exception 'Conductor fuera del entorno seleccionado';
  end if;

  perform set_config('app.runtime_channel',v_channel,true);
  v_trip:=public.admin_assign_ride(
    p_ride_request_id,p_driver_id,p_final_fare
  );
  return v_trip;
end;
$$;

create or replace function public.admin_assign_delivery_v2(
  p_delivery_id uuid,
  p_driver_id uuid,
  p_channel text default 'production'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_request_channel text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select channel into v_request_channel
  from public.delivery_requests
  where id=p_delivery_id;

  if v_request_channel is distinct from v_channel then
    raise exception 'Delivery fuera del entorno seleccionado';
  end if;

  if not exists(
    select 1 from public.native_push_tokens
    where user_id=p_driver_id and active=true and channel=v_channel
  ) then
    raise exception 'Conductor fuera del entorno seleccionado';
  end if;

  perform set_config('app.runtime_channel',v_channel,true);
  perform public.admin_assign_delivery(p_delivery_id,p_driver_id);
end;
$$;

create or replace function public.available_deliveries_for_driver_v2(
  p_channel text default 'production'
)
returns setof public.delivery_requests
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists(
    select 1 from public.driver_profiles dp
    where dp.id=v_uid
      and dp.approval_status='approved'
      and dp.online_status='online'
  ) then return; end if;

  return query
  select d.*
  from public.delivery_requests d
  where d.channel=v_channel
    and d.status='searching'
    and d.courier_id is null
    and public.same_operational_scope(d.customer_id,v_uid)
    and public.delivery_request_matches_driver_zone(
      d.pickup_latitude,d.pickup_longitude,
      d.marketplace_order_id,d.customer_id,v_uid
    )
  order by d.dispatch_priority desc,d.created_at asc
  limit 50;
end;
$$;

create or replace function public.claim_delivery_v2(
  p_delivery_id uuid,
  p_channel text default 'production'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not exists(
    select 1 from public.delivery_requests
    where id=p_delivery_id and channel=v_channel
  ) then
    raise exception 'Delivery fuera del entorno seleccionado';
  end if;
  perform set_config('app.runtime_channel',v_channel,true);
  perform public.claim_delivery(p_delivery_id);
end;
$$;

create or replace function public.my_current_country_trips_v2(
  p_channel text default 'production',
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default null
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';

  return (
    select coalesce(jsonb_agg(x.payload order by x.created_at desc),'[]'::jsonb)
    from (
      select
        to_jsonb(t)||jsonb_build_object(
          'ride_requests',
          case when rr.id is null then null else to_jsonb(rr) end
        ) as payload,
        t.created_at
      from public.trips t
      join public.ride_requests rr on rr.id=t.ride_request_id
      left join public.service_zones z on z.id=rr.zone_id
      where t.channel=v_channel
        and rr.channel=v_channel
        and (t.driver_id=v_uid or t.passenger_id=v_uid)
        and (
          z.country_code=v_country
          or (
            z.id is null and exists(
              select 1 from public.service_zones cz
              where cz.country_code=v_country
                and upper(cz.currency_code)=upper(rr.currency)
            )
          )
        )
        and (p_from is null or t.created_at>=p_from)
        and (p_to is null or t.created_at<p_to)
      order by t.created_at desc
      limit case when p_limit is null or p_limit<1 then null else p_limit end
    ) x
  );
end;
$$;

create or replace function public.my_current_country_deliveries_v2(
  p_channel text default 'production',
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default null
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';

  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
    from (
      select d.*
      from public.delivery_requests d
      where d.channel=v_channel
        and (d.customer_id=v_uid or d.courier_id=v_uid)
        and d.country_code=v_country
        and (p_from is null or d.created_at>=p_from)
        and (p_to is null or d.created_at<p_to)
      order by d.created_at desc
      limit case when p_limit is null or p_limit<1 then null else p_limit end
    ) x
  );
end;
$$;

create or replace function public.passenger_active_trip_live_state_v2(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select
    to_jsonb(t)||
    jsonb_build_object(
      'ride_requests',to_jsonb(r),
      'driver_profile',jsonb_build_object(
        'id',dp.id,'rating',dp.rating,
        'completed_trips',dp.completed_trips,
        'vehicle_summary',dp.vehicle_summary,
        'city',dp.city,'approval_status',dp.approval_status,
        'online_status',dp.online_status,
        'latitude',dp.latitude,'longitude',dp.longitude,
        'updated_at',dp.updated_at
      ),
      'driver_waiting_since',(
        select h.created_at from public.trip_status_history h
        where h.trip_id=t.id and h.status='driver_waiting'
        order by h.created_at desc limit 1
      ),
      'passenger_on_way_at',(
        select h.created_at from public.trip_status_history h
        where h.trip_id=t.id and h.status='passenger_on_way'
        order by h.created_at desc limit 1
      )
    )
  into v_result
  from public.trips t
  join public.ride_requests r on r.id=t.ride_request_id
  left join public.driver_profiles dp on dp.id=t.driver_id
  where t.passenger_id=v_uid
    and t.channel=v_channel
    and r.channel=v_channel
    and t.status not in ('completed','cancelled')
  order by t.created_at desc
  limit 1;

  return v_result;
end;
$$;

create or replace function public.passenger_live_offer_state_v2(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_ride public.ride_requests%rowtype;
  v_offers jsonb:='[]'::jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select * into v_ride
  from public.ride_requests r
  where r.passenger_id=v_uid
    and r.channel=v_channel
    and r.status in ('searching','offers_received')
    and r.expires_at>now()-interval '30 seconds'
  order by r.created_at desc
  limit 1;

  if v_ride.id is not null then
    select coalesce(
      jsonb_agg(
        to_jsonb(o)||
        jsonb_build_object(
          'driver_profiles',jsonb_build_object(
            'id',dp.id,'rating',dp.rating,
            'completed_trips',dp.completed_trips,
            'vehicle_summary',dp.vehicle_summary,
            'city',dp.city,'approval_status',dp.approval_status,
            'online_status',dp.online_status
          ),
          'driver_user',jsonb_build_object(
            'id',u.id,'full_name',u.full_name,'avatar_url',u.avatar_url
          )
        )
        order by o.created_at asc
      ),
      '[]'::jsonb
    )
    into v_offers
    from public.driver_offers o
    left join public.driver_profiles dp on dp.id=o.driver_id
    left join public.users u on u.id=o.driver_id
    where o.ride_request_id=v_ride.id
      and o.channel=v_channel
      and o.status='pending'
      and coalesce(o.expires_at,now()+interval '1 second')>now();
  end if;

  return jsonb_build_object(
    'ride',case when v_ride.id is null then null else to_jsonb(v_ride) end,
    'offers',v_offers,
    'server_now',now()
  );
end;
$$;

create or replace function public.passenger_home_state_v2(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_open_ride public.ride_requests%rowtype;
  v_active_trip public.trips%rowtype;
  v_active_delivery public.delivery_requests%rowtype;
  v_driver_id uuid;
  v_counterpart jsonb;
  v_driver_profile jsonb;
  v_offers jsonb:='[]'::jsonb;
  v_saved jsonb:='[]'::jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  update public.driver_offers o
  set status='declined'
  where o.channel=v_channel
    and o.status='pending'
    and exists(
      select 1 from public.ride_requests r
      where r.id=o.ride_request_id
        and r.channel=v_channel
        and r.passenger_id=v_uid
        and r.status in ('searching','offers_received')
        and o.expires_at<=now()
    );

  update public.ride_requests
  set status='cancelled',updated_at=now()
  where passenger_id=v_uid
    and channel=v_channel
    and status in ('searching','offers_received')
    and expires_at<=now()-interval '30 seconds';

  select * into v_active_trip
  from public.trips
  where passenger_id=v_uid
    and channel=v_channel
    and status not in ('completed','cancelled')
  order by created_at desc limit 1;

  if v_active_trip.id is null then
    select * into v_open_ride
    from public.ride_requests
    where passenger_id=v_uid
      and channel=v_channel
      and status in ('searching','offers_received')
      and expires_at>now()-interval '30 seconds'
    order by created_at desc limit 1;
  end if;

  select * into v_active_delivery
  from public.delivery_requests
  where customer_id=v_uid
    and channel=v_channel
    and status not in ('delivered','cancelled')
  order by created_at desc limit 1;

  if v_open_ride.id is not null then
    select coalesce(
      jsonb_agg(
        to_jsonb(o)||
        jsonb_build_object(
          'driver_profiles',jsonb_build_object(
            'id',dp.id,'rating',dp.rating,
            'completed_trips',dp.completed_trips,
            'vehicle_summary',dp.vehicle_summary,
            'city',dp.city,'approval_status',dp.approval_status,
            'online_status',dp.online_status
          ),
          'driver_user',jsonb_build_object(
            'id',u.id,'full_name',u.full_name,'avatar_url',u.avatar_url
          )
        )
        order by o.created_at asc
      ),
      '[]'::jsonb
    )
    into v_offers
    from public.driver_offers o
    left join public.driver_profiles dp on dp.id=o.driver_id
    left join public.users u on u.id=o.driver_id
    where o.ride_request_id=v_open_ride.id
      and o.channel=v_channel
      and o.status='pending'
      and coalesce(o.expires_at,now()+interval '1 second')>now();
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(sa) order by sa.created_at desc),'[]'::jsonb
  )
  into v_saved
  from public.saved_addresses sa
  where sa.user_id=v_uid;

  v_driver_id:=coalesce(v_active_trip.driver_id,v_active_delivery.courier_id);

  if v_driver_id is not null then
    select jsonb_build_object(
      'id',u.id,'full_name',u.full_name,'phone',u.phone,
      'avatar_url',u.avatar_url,'active_mode',u.active_mode
    )
    into v_counterpart
    from public.users u where u.id=v_driver_id;

    select jsonb_build_object(
      'id',dp.id,'rating',dp.rating,
      'completed_trips',dp.completed_trips,
      'vehicle_summary',dp.vehicle_summary,
      'city',dp.city,'approval_status',dp.approval_status,
      'online_status',dp.online_status
    )
    into v_driver_profile
    from public.driver_profiles dp where dp.id=v_driver_id;
  end if;

  return jsonb_build_object(
    'open_ride',
      case when v_open_ride.id is null then null else to_jsonb(v_open_ride) end,
    'active_trip',
      case
        when v_active_trip.id is null then null
        else to_jsonb(v_active_trip)||jsonb_build_object(
          'ride_requests',(
            select to_jsonb(r) from public.ride_requests r
            where r.id=v_active_trip.ride_request_id
              and r.channel=v_channel
          )
        )
      end,
    'active_delivery',
      case
        when v_active_delivery.id is null then null
        else to_jsonb(v_active_delivery)
      end,
    'offers',v_offers,
    'saved',v_saved,
    'counterpart',v_counterpart,
    'driver_profile',v_driver_profile
  );
end;
$$;

create or replace function public.select_ride_offer_v2(
  p_offer_id uuid,
  p_channel text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_offer_channel text;
  v_trip uuid;
begin
  select o.channel into v_offer_channel
  from public.driver_offers o
  where o.id=p_offer_id;

  if v_offer_channel is distinct from v_channel then
    raise exception 'Oferta fuera del entorno seleccionado';
  end if;

  perform set_config('app.runtime_channel',v_channel,true);
  v_trip:=public.select_ride_offer(p_offer_id);
  return v_trip;
end;
$$;

create or replace function public.advance_trip_v2(
  p_trip_id uuid,p_status text,p_channel text default 'production'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not exists(select 1 from public.trips where id=p_trip_id and channel=v_channel)
  then raise exception 'Viaje fuera del entorno seleccionado'; end if;
  perform set_config('app.runtime_channel',v_channel,true);
  perform public.advance_trip(p_trip_id,p_status);
end;
$$;

create or replace function public.start_trip_with_pin_v2(
  p_trip_id uuid,p_pin text,p_channel text default 'production'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not exists(select 1 from public.trips where id=p_trip_id and channel=v_channel)
  then raise exception 'Viaje fuera del entorno seleccionado'; end if;
  perform set_config('app.runtime_channel',v_channel,true);
  perform public.start_trip_with_pin(p_trip_id,p_pin);
end;
$$;

create or replace function public.cancel_trip_v2(
  p_trip_id uuid,p_reason text default null,p_channel text default 'production'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not exists(select 1 from public.trips where id=p_trip_id and channel=v_channel)
  then raise exception 'Viaje fuera del entorno seleccionado'; end if;
  perform set_config('app.runtime_channel',v_channel,true);
  perform public.cancel_trip(p_trip_id,p_reason);
end;
$$;

create or replace function public.advance_delivery_v2(
  p_delivery_id uuid,p_status text,p_channel text default 'production'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not exists(
    select 1 from public.delivery_requests
    where id=p_delivery_id and channel=v_channel
  ) then raise exception 'Delivery fuera del entorno seleccionado'; end if;
  perform set_config('app.runtime_channel',v_channel,true);
  perform public.advance_delivery(p_delivery_id,p_status);
end;
$$;

create or replace function public.cancel_delivery_v2(
  p_delivery_id uuid,p_reason text default null,p_channel text default 'production'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not exists(
    select 1 from public.delivery_requests
    where id=p_delivery_id and channel=v_channel
  ) then raise exception 'Delivery fuera del entorno seleccionado'; end if;
  perform set_config('app.runtime_channel',v_channel,true);
  perform public.cancel_delivery(p_delivery_id,p_reason);
end;
$$;

-- available_ride_requests_for_driver_v2 already accepts p_channel;
-- now enforce it on the base request set before priority ranking.
create or replace function public.available_ride_requests_for_driver_v2(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_preview boolean:=v_channel='preview';
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

  select case
    when v_preview then preview_enforcement_enabled
    else production_enforcement_enabled
  end
  into v_enforcement
  from public.driver_priority_settings
  where id=true;

  select coalesce(jsonb_agg(e),'[]'::jsonb)
  into v_base
  from jsonb_array_elements(
    coalesce(public.available_ride_requests_for_driver(),'[]'::jsonb)
  ) e
  where public.normalize_runtime_channel(e->>'channel')=v_channel;

  if coalesce(v_enforcement,false) is false then
    return v_base;
  end if;

  v_priority:=public.driver_priority_summary_for(v_uid);
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
        else -coalesce(
          public.geo_distance_km(
            v_lat,v_lng,
            nullif(e->>'pickup_latitude','')::numeric,
            nullif(e->>'pickup_longitude','')::numeric
          ),0)
      end as rank_a,
      case
        when v_level='low' then coalesce(pr.passenger_rating,0)
        else -coalesce(pr.passenger_rating,5)
      end as rank_b,
      case
        when v_level='low' then coalesce(
          nullif(e->>'proposed_fare','')::numeric/
          nullif(nullif(e->>'route_distance_km','')::numeric,0),0
        )
        else -coalesce(
          nullif(e->>'proposed_fare','')::numeric/
          nullif(nullif(e->>'route_distance_km','')::numeric,0),0
        )
      end as rank_c
    from jsonb_array_elements(coalesce(v_base,'[]'::jsonb)) e
    left join lateral (
      select round(avg(r.score)::numeric,2) as passenger_rating
      from public.ratings r
      where r.to_user_id=nullif(e->>'passenger_id','')::uuid
    ) pr on true
  ) x;

  return coalesce(v_result,'[]'::jsonb);
end;
$$;

revoke all on function public.admin_trip_list_v3(text,timestamptz,timestamptz,uuid,text,integer,integer) from public,anon;
revoke all on function public.admin_delivery_list_v3(text,timestamptz,timestamptz,text,integer,integer) from public,anon;
revoke all on function public.admin_open_service_requests_v2(text) from public,anon;
revoke all on function public.admin_available_drivers_v2(text) from public,anon;
revoke all on function public.admin_assign_ride_v2(uuid,uuid,numeric,text) from public,anon;
revoke all on function public.admin_assign_delivery_v2(uuid,uuid,text) from public,anon;
revoke all on function public.available_deliveries_for_driver_v2(text) from public,anon;
revoke all on function public.claim_delivery_v2(uuid,text) from public,anon;
revoke all on function public.my_current_country_trips_v2(text,timestamptz,timestamptz,integer) from public,anon;
revoke all on function public.my_current_country_deliveries_v2(text,timestamptz,timestamptz,integer) from public,anon;
revoke all on function public.passenger_active_trip_live_state_v2(text) from public,anon;
revoke all on function public.passenger_live_offer_state_v2(text) from public,anon;
revoke all on function public.passenger_home_state_v2(text) from public,anon;
revoke all on function public.select_ride_offer_v2(uuid,text) from public,anon;
revoke all on function public.advance_trip_v2(uuid,text,text) from public,anon;
revoke all on function public.start_trip_with_pin_v2(uuid,text,text) from public,anon;
revoke all on function public.cancel_trip_v2(uuid,text,text) from public,anon;
revoke all on function public.advance_delivery_v2(uuid,text,text) from public,anon;
revoke all on function public.cancel_delivery_v2(uuid,text,text) from public,anon;

grant execute on function public.admin_trip_list_v3(text,timestamptz,timestamptz,uuid,text,integer,integer) to authenticated;
grant execute on function public.admin_delivery_list_v3(text,timestamptz,timestamptz,text,integer,integer) to authenticated;
grant execute on function public.admin_open_service_requests_v2(text) to authenticated;
grant execute on function public.admin_available_drivers_v2(text) to authenticated;
grant execute on function public.admin_assign_ride_v2(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.admin_assign_delivery_v2(uuid,uuid,text) to authenticated;
grant execute on function public.available_deliveries_for_driver_v2(text) to authenticated;
grant execute on function public.claim_delivery_v2(uuid,text) to authenticated;
grant execute on function public.my_current_country_trips_v2(text,timestamptz,timestamptz,integer) to authenticated;
grant execute on function public.my_current_country_deliveries_v2(text,timestamptz,timestamptz,integer) to authenticated;
grant execute on function public.passenger_active_trip_live_state_v2(text) to authenticated;
grant execute on function public.passenger_live_offer_state_v2(text) to authenticated;
grant execute on function public.passenger_home_state_v2(text) to authenticated;
grant execute on function public.select_ride_offer_v2(uuid,text) to authenticated;
grant execute on function public.advance_trip_v2(uuid,text,text) to authenticated;
grant execute on function public.start_trip_with_pin_v2(uuid,text,text) to authenticated;
grant execute on function public.cancel_trip_v2(uuid,text,text) to authenticated;
grant execute on function public.advance_delivery_v2(uuid,text,text) to authenticated;
grant execute on function public.cancel_delivery_v2(uuid,text,text) to authenticated;
