-- 2026-10-13 Preview-first: explicit per-active-vehicle parcel authorization.
-- This migration does not enable any zone, user, parcel type or production channel.
-- Taxi dispatch logic is left unchanged.
alter table public.ride_requests
  add column if not exists parcel_kind text;
alter table public.ride_requests
  drop constraint if exists ride_requests_parcel_kind_check;
alter table public.ride_requests
  add constraint ride_requests_parcel_kind_check
  check (parcel_kind is null or parcel_kind in ('moto','auto','carga'));

create table if not exists public.driver_parcel_vehicle_grants (
  driver_id uuid not null references public.driver_profiles(id) on delete cascade,
  vehicle_id uuid not null references public.driver_vehicles(id) on delete cascade,
  zone_id uuid not null references public.service_zones(id),
  channel text not null check (channel in ('preview','production')),
  parcel_kind text not null check (parcel_kind in ('moto','auto','carga')),
  enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key(driver_id,vehicle_id,channel,parcel_kind)
);
create index if not exists driver_parcel_vehicle_grants_lookup
  on public.driver_parcel_vehicle_grants(driver_id,channel,vehicle_id,parcel_kind)
  where enabled;
alter table public.driver_parcel_vehicle_grants enable row level security;
revoke all on public.driver_parcel_vehicle_grants from anon,authenticated;
grant select on public.driver_parcel_vehicle_grants to authenticated;
drop policy if exists parcel_vehicle_grants_read_self on public.driver_parcel_vehicle_grants;
create policy parcel_vehicle_grants_read_self
  on public.driver_parcel_vehicle_grants for select to authenticated
  using (driver_id=(select auth.uid()) or public.is_admin());

-- The vehicle size is an upper bound, never an automatic permission.
-- Unknown vehicle types have rank zero: fail closed, never classify as car.
create or replace function public.parcel_vehicle_capacity(p_type text)
returns integer language sql immutable as $$
  select case lower(trim(coalesce(p_type,'')))
    when 'motorcycle' then 1
    when 'moto' then 1
    when 'car' then 2
    when 'auto' then 2
    when 'xl' then 2
    when 'van' then 3
    when 'truck' then 3
    when 'camioneta' then 3
    when 'camion' then 3
    else 0 end;
$$;
create or replace function public.parcel_kind_capacity(p_kind text)
returns integer language sql immutable as $$
  select case p_kind when 'moto' then 1 when 'auto' then 2
    when 'carga' then 3 else 999 end;
$$;

-- Check identity, operational scope, active vehicle, zone, approved parcel
-- permission, and the exact explicit grant. Do not use current client's auth.uid
-- in the helper: triggers for new requests execute as the passenger.
create or replace function public.parcel_driver_can_carry(
  p_driver_id uuid, p_ride_id uuid
) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1
      from public.ride_requests r
      join public.driver_profiles dp
        on dp.id=p_driver_id and dp.zone_id=r.zone_id
      join public.driver_vehicles dv
        on dv.driver_id=dp.id and dv.is_active=true
      join public.driver_parcel_vehicle_grants g
        on g.driver_id=dp.id and g.vehicle_id=dv.id
        and g.zone_id=dp.zone_id and g.channel=r.channel
        and g.parcel_kind=r.parcel_kind and g.enabled
      join public.driver_work_permissions wp
        on wp.driver_id=dp.id and wp.zone_id=dp.zone_id
        and wp.channel=r.channel and wp.service_key='parcel'
        and wp.status='approved'
     where r.id=p_ride_id and r.service_mode='parcel'
       and r.parcel_kind in ('moto','auto','carga')
       and public.admin_user_runtime_environment(dp.id)=r.channel
       and public.parcel_vehicle_capacity(dv.vehicle_type)
           >= public.parcel_kind_capacity(r.parcel_kind)
  );
$$;
revoke execute on function public.parcel_driver_can_carry(uuid,uuid)
  from public,anon,authenticated;

-- Admin grants are per active, reviewed vehicle; even an admin cannot assign
-- "carga" to a motorcycle. Never derive grants from vehicle type alone.
create or replace function public.admin_set_driver_parcel_vehicle_grant(
  p_driver_id uuid, p_vehicle_id uuid, p_channel text,
  p_parcel_kind text, p_enabled boolean
) returns jsonb language plpgsql security definer
set search_path=public as $$
declare
  v_zone uuid;
  v_vehicle_type text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Solo el administrador puede asignar tipos de envío';
  end if;
  -- Initial rollout is intentionally Preview only.
  if p_channel is distinct from 'preview' then
    raise exception 'La asignación de Envíos está habilitada solo en Preview';
  end if;
  if p_parcel_kind not in ('moto','auto','carga') or p_parcel_kind is null then
    raise exception 'Tipo de envío no válido';
  end if;
  select dp.zone_id,dv.vehicle_type into v_zone,v_vehicle_type
  from public.driver_profiles dp
  join public.driver_vehicles dv on dv.driver_id=dp.id
  where dp.id=p_driver_id and dv.id=p_vehicle_id and dv.is_active=true;
  if v_zone is null then
    raise exception 'Vehículo activo y zona del conductor requeridos';
  end if;
  if public.admin_user_runtime_environment(p_driver_id) <> p_channel then
    raise exception 'La cuenta del conductor no pertenece a Preview';
  end if;
  if coalesce(p_enabled,false) and
      public.parcel_vehicle_capacity(v_vehicle_type)
        < public.parcel_kind_capacity(p_parcel_kind) then
    raise exception 'Este vehículo no tiene capacidad para ese envío';
  end if;
  insert into public.driver_parcel_vehicle_grants(
    driver_id,vehicle_id,zone_id,channel,parcel_kind,enabled,updated_by)
  values (p_driver_id,p_vehicle_id,v_zone,p_channel,
    p_parcel_kind,coalesce(p_enabled,false),auth.uid())
  on conflict(driver_id,vehicle_id,channel,parcel_kind) do update set
    zone_id=excluded.zone_id,enabled=excluded.enabled,
    updated_by=auth.uid(),updated_at=now();
  return jsonb_build_object('driver_id',p_driver_id,'vehicle_id',p_vehicle_id,
    'channel',p_channel,'parcel_kind',p_parcel_kind,'enabled',coalesce(p_enabled,false));
end;
$$;
revoke execute on function public.admin_set_driver_parcel_vehicle_grant(
 uuid,uuid,text,text,boolean) from public,anon;
grant execute on function public.admin_set_driver_parcel_vehicle_grant(
 uuid,uuid,text,text,boolean) to authenticated;

-- No offer, assignment, feed or push for a non-matching driver.
-- Keep the exact canonical Taxi SQL; inject *only* parcel predicates.
do $patch$
declare
  v_sql text;
  v_anchor text;
  v_replacement text;
begin
  v_sql:=pg_get_functiondef('public.available_ride_requests_for_driver()'::regprocedure);
  v_anchor:='and public.same_operational_scope(r.passenger_id,v_uid)';
  v_replacement:=v_anchor||E'\n'||
    '      and (r.service_mode <> ''parcel'' or public.parcel_driver_can_carry(v_uid,r.id))';
  if position('public.parcel_driver_can_carry' in v_sql)=0 then
    if position(v_anchor in v_sql)=0 then
      raise exception 'Unexpected available_ride_requests_for_driver version';
    end if;
    execute replace(v_sql,v_anchor,v_replacement);
  end if;

  v_sql:=pg_get_functiondef('public.notify_available_ride_to_drivers()'::regprocedure);
  v_anchor:='and public.same_operational_scope(dp.id, new.passenger_id)';
  v_replacement:=v_anchor||E'\n'||
    '      and (new.service_mode <> ''parcel'' or public.parcel_driver_can_carry(dp.id,new.id))';
  if position('public.parcel_driver_can_carry' in v_sql)=0 then
    if position(v_anchor in v_sql)=0 then
      raise exception 'Unexpected notify_available_ride_to_drivers version';
    end if;
    execute replace(v_sql,v_anchor,v_replacement);
  end if;

  v_sql:=pg_get_functiondef('public.guard_parcel_ride_offer_permission()'::regprocedure);
  v_anchor:='IF v_mode=''parcel'' AND (';
  v_replacement:=v_anchor||E'\n'||
    '   NOT public.parcel_driver_can_carry(new.driver_id,new.ride_request_id) OR';
  if position('public.parcel_driver_can_carry' in v_sql)=0 then
    if position(v_anchor in v_sql)=0 then
      raise exception 'Unexpected guard_parcel_ride_offer_permission version';
    end if;
    execute replace(v_sql,v_anchor,v_replacement);
  end if;

  v_sql:=pg_get_functiondef('public.guard_parcel_trip_assignment()'::regprocedure);
  v_anchor:='IF v_mode=''parcel'' THEN';
  v_replacement:=v_anchor||E'\n'||
    '  IF NOT public.parcel_driver_can_carry(new.driver_id,new.ride_request_id)'||
    ' THEN RAISE EXCEPTION ''Vehículo no autorizado para este tipo de envío''; END IF;';
  if position('public.parcel_driver_can_carry' in v_sql)=0 then
    if position(v_anchor in v_sql)=0 then
      raise exception 'Unexpected guard_parcel_trip_assignment version';
    end if;
    execute replace(v_sql,v_anchor,v_replacement);
  end if;
end;
$patch$;

-- New parcel requests must select a size; existing Taxi rows are unaffected.
create or replace function public.guard_parcel_kind_required()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.service_mode='parcel'
     and new.parcel_kind not in ('moto','auto','carga') then
    raise exception 'Elige el tipo de envío antes de solicitarlo';
  end if;
  if new.service_mode='parcel' and new.parcel_kind is null then
    raise exception 'Elige el tipo de envío antes de solicitarlo';
  end if;
  if new.service_mode='taxi' and new.parcel_kind is not null then
    raise exception 'Taxi no admite tipo de carga';
  end if;
  return new;
end;
$$;
drop trigger if exists guard_parcel_kind_required on public.ride_requests;
create trigger guard_parcel_kind_required
before insert or update of service_mode,parcel_kind
on public.ride_requests for each row
execute function public.guard_parcel_kind_required();
