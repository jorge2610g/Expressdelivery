-- Location reliability + privacy hardening.
-- Keeps exact coordinates available only for active service counterparts,
-- makes pre-booking driver markers coarse, tracks GPS freshness separately,
-- clears exact coordinates when a driver goes offline, and removes runtime
-- roles' schema-level privileges that are not needed by the app.

alter table public.driver_profiles
  add column if not exists location_updated_at timestamptz;

update public.driver_profiles
set location_updated_at=updated_at
where latitude is not null
  and longitude is not null
  and location_updated_at is null;

create index if not exists driver_profiles_online_location_fresh_idx
  on public.driver_profiles(online_status,location_updated_at desc)
  where latitude is not null and longitude is not null;

create or replace function public.guard_driver_profile_location_integrity()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if (new.latitude is null) <> (new.longitude is null) then
    raise exception 'Latitud y longitud deben actualizarse juntas';
  end if;

  if new.latitude is not null then
    if new.latitude < -90 or new.latitude > 90
       or new.longitude < -180 or new.longitude > 180 then
      raise exception 'Coordenadas fuera de rango';
    end if;
  end if;

  if new.heading_degrees is not null
     and (new.heading_degrees < 0 or new.heading_degrees > 360) then
    raise exception 'Rumbo GPS fuera de rango';
  end if;

  if tg_op='INSERT' then
    if new.latitude is not null then
      new.location_updated_at:=coalesce(new.location_updated_at,now());
    else
      new.location_updated_at:=null;
      new.heading_degrees:=null;
    end if;
    return new;
  end if;

  if new.latitude is distinct from old.latitude
     or new.longitude is distinct from old.longitude then
    if new.latitude is null then
      new.location_updated_at:=null;
      new.heading_degrees:=null;
    else
      new.location_updated_at:=now();
    end if;
  end if;

  -- Exact live coordinates are operational data, not profile history.
  -- Remove them as soon as the driver explicitly leaves the live state.
  if old.online_status is distinct from new.online_status
     and new.online_status='offline' then
    new.latitude:=null;
    new.longitude:=null;
    new.heading_degrees:=null;
    new.location_updated_at:=null;
  end if;

  if old.approval_status is distinct from new.approval_status
     and new.approval_status<>'approved' then
    new.latitude:=null;
    new.longitude:=null;
    new.heading_degrees:=null;
    new.location_updated_at:=null;
  end if;

  return new;
end;
$$;

drop trigger if exists driver_profile_location_integrity
  on public.driver_profiles;
create trigger driver_profile_location_integrity
before insert or update on public.driver_profiles
for each row execute function public.guard_driver_profile_location_integrity();

-- Direct driver_profiles reads may expose exact current coordinates, so only
-- the driver, admins, or the counterpart of an active service may read the row.
-- Historical counterpart details are served by the scoped summary RPC below.
create or replace function public.can_read_driver_profile(
  p_viewer_id uuid,
  p_driver_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select
    p_viewer_id is not null
    and (
      p_viewer_id=p_driver_id
      or public.is_admin()
      or exists(
        select 1
        from public.trips t
        where t.driver_id=p_driver_id
          and t.passenger_id=p_viewer_id
          and t.status not in ('completed','cancelled')
      )
      or exists(
        select 1
        from public.delivery_requests d
        where d.courier_id=p_driver_id
          and d.customer_id=p_viewer_id
          and d.status not in ('delivered','cancelled')
      )
    );
$$;

create or replace function public.driver_profile_for_viewer(
  p_driver_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_allowed boolean:=false;
  v_live boolean:=false;
  v_row public.driver_profiles%rowtype;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_live:=public.can_read_driver_profile(v_uid,p_driver_id);

  v_allowed:=
    v_live
    or exists(
      select 1 from public.trips t
      where t.driver_id=p_driver_id and t.passenger_id=v_uid
    )
    or exists(
      select 1 from public.delivery_requests d
      where d.courier_id=p_driver_id and d.customer_id=v_uid
    )
    or exists(
      select 1
      from public.driver_offers o
      join public.ride_requests r on r.id=o.ride_request_id
      where o.driver_id=p_driver_id and r.passenger_id=v_uid
    );

  if not v_allowed then
    return null;
  end if;

  select * into v_row
  from public.driver_profiles
  where id=p_driver_id
  limit 1;

  if not found then return null; end if;

  return jsonb_build_object(
    'id',v_row.id,
    'rating',v_row.rating,
    'completed_trips',v_row.completed_trips,
    'vehicle_summary',v_row.vehicle_summary,
    'city',v_row.city,
    'approval_status',v_row.approval_status,
    'online_status',case when v_live then v_row.online_status else null end,
    'latitude',case when v_live then v_row.latitude else null end,
    'longitude',case when v_live then v_row.longitude else null end,
    'heading_degrees',case when v_live then v_row.heading_degrees else null end,
    'location_updated_at',case when v_live then v_row.location_updated_at else null end
  );
end;
$$;

revoke all on function public.driver_profile_for_viewer(uuid)
from public,anon;
grant execute on function public.driver_profile_for_viewer(uuid)
to authenticated;

-- Pre-booking map markers should prove supply exists without disclosing a
-- driver's house-level exact position. Exact live position remains available
-- to the assigned counterpart through driver_profile_for_viewer().
create or replace function public.nearby_online_driver_markers(
  p_lat numeric,
  p_lng numeric,
  p_radius_km numeric default 5,
  p_vehicle_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result jsonb;
  v_requested text:=nullif(lower(trim(coalesce(p_vehicle_type,''))),'');
  v_uid uuid:=auth.uid();
  v_audit boolean:=false;
  v_limit integer:=16;
  v_zone_id uuid;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90
     or p_lng < -180 or p_lng > 180 then
    raise exception 'Coordenadas inválidas';
  end if;

  v_zone_id:=public.service_zone_id_for_point(p_lat,p_lng);

  select exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid and m.enabled=true and g.active=true
  ) into v_audit;
  if v_audit then v_limit:=250; end if;

  with candidates as(
    select
      round(dp.latitude::numeric,3) latitude,
      round(dp.longitude::numeric,3) longitude,
      coalesce(dp.heading_degrees,0) heading_degrees,
      coalesce(
        (
          select dv.vehicle_type
          from public.driver_vehicles dv
          where dv.driver_id=dp.id and dv.is_active=true
          order by dv.updated_at desc
          limit 1
        ),
        case
          when lower(coalesce(dp.vehicle_summary,'')) like '%moto%' then 'motorcycle'
          when lower(coalesce(dp.vehicle_summary,'')) like '%xl%' then 'xl'
          else 'car'
        end
      ) vehicle_type,
      public.geo_distance_km(
        p_lat,p_lng,dp.latitude,dp.longitude
      ) distance_km
    from public.driver_profiles dp
    where dp.approval_status='approved'
      and dp.online_status='online'
      and dp.latitude is not null
      and dp.longitude is not null
      and dp.location_updated_at>=now()-interval '3 minutes'
      and public.same_operational_scope(v_uid,dp.id)
      and (v_zone_id is null or dp.zone_id is null or dp.zone_id=v_zone_id)
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'latitude',latitude,
        'longitude',longitude,
        'vehicle_type',vehicle_type,
        'heading_degrees',heading_degrees,
        'distance_km',round(distance_km::numeric,1)
      )
      order by distance_km
    ),
    '[]'::jsonb
  )
  into v_result
  from(
    select *
    from candidates
    where distance_km<=greatest(0.5,least(coalesce(p_radius_km,5),20))
      and (v_requested is null or vehicle_type=v_requested)
    order by distance_km
    limit v_limit
  ) q;

  return v_result;
end;
$$;

revoke all on function public.nearby_online_driver_markers(
  numeric,numeric,numeric,text
) from public,anon;
grant execute on function public.nearby_online_driver_markers(
  numeric,numeric,numeric,text
) to authenticated;

-- Runtime clients never need schema-changing/table-wide capabilities.
revoke truncate,trigger,references
on table public.driver_profiles,
         public.ride_requests,
         public.delivery_requests,
         public.saved_addresses,
         public.emergency_events,
         public.marketplace_merchants
from anon,authenticated;

revoke delete on table public.driver_profiles from authenticated;

comment on column public.driver_profiles.location_updated_at is
  'Timestamp of the last accepted GPS coordinate update; separate from general profile updated_at.';
comment on function public.driver_profile_for_viewer(uuid) is
  'Returns non-sensitive historical driver summary and exact location only for an active service counterpart/self/admin.';
