-- Operational coverage hardening.
-- A disabled country/zone must immediately stop existing drivers, not only
-- block new registrations.

create or replace function public.enforce_driver_active_coverage_on_online()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_detected uuid;
begin
  if new.online_status='online'
     and old.online_status is distinct from new.online_status then
    if new.approval_status<>'approved' then
      raise exception 'El perfil de conductor no está aprobado';
    end if;
    if new.latitude is null or new.longitude is null then
      raise exception 'Activa el GPS antes de conectarte';
    end if;

    v_detected:=public.service_zone_id_for_point(
      new.latitude::numeric,
      new.longitude::numeric
    );

    if v_detected is null then
      raise exception 'Express todavía no está disponible en esta zona';
    end if;

    if new.zone_id is null or new.zone_id is distinct from v_detected then
      raise exception
        'Tu ubicación actual no coincide con tu zona de conductor';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists driver_active_coverage_on_online
on public.driver_profiles;
create trigger driver_active_coverage_on_online
before update of online_status on public.driver_profiles
for each row
execute function public.enforce_driver_active_coverage_on_online();

revoke all on function public.enforce_driver_active_coverage_on_online()
from public,anon,authenticated;

create or replace function public.force_driver_offline_outside_active_coverage()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_detected uuid;
begin
  if new.online_status='online'
     and (
       old.latitude is distinct from new.latitude
       or old.longitude is distinct from new.longitude
     ) then
    if new.latitude is null or new.longitude is null then
      new.online_status:='offline';
      return new;
    end if;

    v_detected:=public.service_zone_id_for_point(
      new.latitude::numeric,
      new.longitude::numeric
    );

    if v_detected is null
       or new.zone_id is null
       or v_detected is distinct from new.zone_id then
      new.online_status:='offline';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists driver_offline_outside_active_coverage
on public.driver_profiles;
create trigger driver_offline_outside_active_coverage
before update of latitude,longitude on public.driver_profiles
for each row
execute function public.force_driver_offline_outside_active_coverage();

revoke all on function public.force_driver_offline_outside_active_coverage()
from public,anon,authenticated;

create or replace function public.force_drivers_offline_when_coverage_disabled()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if tg_table_name='service_countries' then
    if old.active=true and new.active=false then
      update public.driver_profiles
      set online_status='offline',updated_at=now()
      where upper(coalesce(country_code,''))=new.country_code
        and online_status<>'offline';
    end if;
  elsif tg_table_name='service_zones' then
    if old.active=true and new.active=false then
      update public.driver_profiles
      set online_status='offline',updated_at=now()
      where zone_id=new.id
        and online_status<>'offline';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists country_force_drivers_offline
on public.service_countries;
create trigger country_force_drivers_offline
after update of active on public.service_countries
for each row
execute function public.force_drivers_offline_when_coverage_disabled();

drop trigger if exists zone_force_drivers_offline
on public.service_zones;
create trigger zone_force_drivers_offline
after update of active on public.service_zones
for each row
execute function public.force_drivers_offline_when_coverage_disabled();

revoke all on function public.force_drivers_offline_when_coverage_disabled()
from public,anon,authenticated;

create or replace function public.available_ride_requests_for_driver_v3(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_base jsonb;
  v_accepted text[];
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists(
    select 1
    from public.driver_profiles d
    join public.service_zones z
      on z.id=d.zone_id and z.active=true
    join public.service_countries c
      on c.country_code=upper(coalesce(z.country_code,''))
     and c.active=true
    where d.id=v_uid
      and d.approval_status='approved'
      and d.online_status='online'
      and d.latitude is not null
      and d.longitude is not null
      and public.service_zone_id_for_point(
        d.latitude::numeric,d.longitude::numeric
      )=d.zone_id
  ) then
    return '[]'::jsonb;
  end if;

  v_base:=public.available_ride_requests_for_driver_v2(p_channel);

  select d.accepted_payment_methods
  into v_accepted
  from public.driver_profiles d
  where d.id=v_uid;

  if v_accepted is null or cardinality(v_accepted)=0 then
    return coalesce(v_base,'[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(item),'[]'::jsonb)
  into v_result
  from jsonb_array_elements(coalesce(v_base,'[]'::jsonb)) item
  where item->>'payment_method'=any(v_accepted);

  return coalesce(v_result,'[]'::jsonb);
end;
$$;

revoke all on function public.available_ride_requests_for_driver_v3(text)
from public,anon;
grant execute on function public.available_ride_requests_for_driver_v3(text)
to authenticated;

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
    select 1
    from public.driver_profiles dp
    join public.service_zones z
      on z.id=dp.zone_id and z.active=true
    join public.service_countries c
      on c.country_code=upper(coalesce(z.country_code,''))
     and c.active=true
    where dp.id=v_uid
      and dp.approval_status='approved'
      and dp.online_status='online'
      and dp.latitude is not null
      and dp.longitude is not null
      and public.service_zone_id_for_point(
        dp.latitude::numeric,dp.longitude::numeric
      )=dp.zone_id
  ) then
    return;
  end if;

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

revoke all on function public.available_deliveries_for_driver_v2(text)
from public,anon;
grant execute on function public.available_deliveries_for_driver_v2(text)
to authenticated;
