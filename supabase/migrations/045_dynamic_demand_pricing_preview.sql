
-- Dynamic demand pricing foundation. Production multiplier remains disabled
-- until explicitly enabled from administration after Preview/QA validation.

alter table public.driver_profiles
  add column if not exists heading_degrees numeric;

alter table public.ride_requests
  add column if not exists base_fare numeric,
  add column if not exists demand_multiplier numeric not null default 1,
  add column if not exists demand_level text,
  add column if not exists demand_requests integer,
  add column if not exists demand_drivers integer,
  add column if not exists demand_sector_key text;

create table if not exists public.dynamic_pricing_settings (
  id boolean primary key default true check (id),
  production_enabled boolean not null default false,
  preview_enabled boolean not null default true,
  radius_km numeric not null default 0.75 check (radius_km between 0.25 and 5),
  window_minutes integer not null default 5 check (window_minutes between 1 and 30),
  min_requests integer not null default 3 check (min_requests between 1 and 100),
  elevated_ratio numeric not null default 1.20,
  high_ratio numeric not null default 2.00,
  critical_ratio numeric not null default 3.00,
  elevated_multiplier numeric not null default 1.10,
  high_multiplier numeric not null default 1.20,
  critical_multiplier numeric not null default 1.35,
  max_multiplier numeric not null default 1.50,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

insert into public.dynamic_pricing_settings(id)
values(true)
on conflict(id) do nothing;

create table if not exists public.dynamic_pricing_qa_overrides (
  city_key text primary key,
  city_name text not null,
  center_latitude numeric not null,
  center_longitude numeric not null,
  active boolean not null default false,
  level text not null default 'automatic',
  multiplier numeric not null default 1,
  synthetic_requests integer not null default 0,
  synthetic_drivers integer not null default 0,
  expires_at timestamptz,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

insert into public.dynamic_pricing_qa_overrides(
  city_key,city_name,center_latitude,center_longitude
)
values
  ('trinidad','Trinidad',-14.8333,-64.9000),
  ('iquique','Iquique',-20.2307,-70.1357)
on conflict(city_key) do nothing;

alter table public.dynamic_pricing_settings enable row level security;
alter table public.dynamic_pricing_qa_overrides enable row level security;

drop policy if exists "dynamic pricing settings authenticated read"
  on public.dynamic_pricing_settings;
create policy "dynamic pricing settings authenticated read"
on public.dynamic_pricing_settings for select
to authenticated
using (true);

drop policy if exists "dynamic pricing settings admin manage"
  on public.dynamic_pricing_settings;
create policy "dynamic pricing settings admin manage"
on public.dynamic_pricing_settings for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "dynamic pricing qa admin read"
  on public.dynamic_pricing_qa_overrides;
create policy "dynamic pricing qa admin read"
on public.dynamic_pricing_qa_overrides for select
to authenticated
using (public.is_admin());

drop policy if exists "dynamic pricing qa admin manage"
  on public.dynamic_pricing_qa_overrides;
create policy "dynamic pricing qa admin manage"
on public.dynamic_pricing_qa_overrides for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

grant select on public.dynamic_pricing_settings to authenticated;
grant select,insert,update,delete on public.dynamic_pricing_qa_overrides to authenticated;

create or replace function public.dynamic_pricing_quote(
  p_service_key text,
  p_distance_km numeric,
  p_duration_minutes numeric,
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_preview boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base_quote jsonb;
  v_settings public.dynamic_pricing_settings%rowtype;
  v_base_amount numeric := 0;
  v_multiplier numeric := 1;
  v_level text := 'normal';
  v_requests integer := 0;
  v_drivers integer := 0;
  v_ratio numeric := 0;
  v_enabled boolean := false;
  v_override public.dynamic_pricing_qa_overrides%rowtype;
  v_has_override boolean := false;
  v_sector text;
begin
  if auth.uid() is null then
    raise exception 'No autenticado';
  end if;

  v_base_quote := public.quote_service_fare(
    p_service_key,
    p_distance_km,
    p_duration_minutes
  );
  v_base_amount := coalesce((v_base_quote->>'amount')::numeric,0);

  select * into v_settings
  from public.dynamic_pricing_settings
  where id=true;

  v_enabled := case
    when p_preview then coalesce(v_settings.preview_enabled,false)
    else coalesce(v_settings.production_enabled,false)
  end;

  v_sector := concat(
    round(coalesce(p_pickup_lat,0)::numeric,3),
    ':',
    round(coalesce(p_pickup_lng,0)::numeric,3)
  );

  if not v_enabled or p_pickup_lat is null or p_pickup_lng is null then
    return v_base_quote || jsonb_build_object(
      'base_amount', round(v_base_amount,2),
      'demand_multiplier', 1,
      'demand_level', 'normal',
      'demand_requests', 0,
      'demand_drivers', 0,
      'demand_ratio', 0,
      'demand_sector_key', v_sector,
      'dynamic_pricing_enabled', v_enabled,
      'preview_mode', p_preview,
      'amount', round(v_base_amount,2)
    );
  end if;

  if p_preview then
    select o.* into v_override
    from public.dynamic_pricing_qa_overrides o
    where o.active=true
      and (o.expires_at is null or o.expires_at > now())
      and (
        6371 * acos(
          least(1,greatest(-1,
            cos(radians(p_pickup_lat::double precision))
            * cos(radians(o.center_latitude::double precision))
            * cos(radians(o.center_longitude::double precision)-radians(p_pickup_lng::double precision))
            + sin(radians(p_pickup_lat::double precision))
            * sin(radians(o.center_latitude::double precision))
          ))
        )
      ) <= 30
    order by (
      6371 * acos(
        least(1,greatest(-1,
          cos(radians(p_pickup_lat::double precision))
          * cos(radians(o.center_latitude::double precision))
          * cos(radians(o.center_longitude::double precision)-radians(p_pickup_lng::double precision))
          + sin(radians(p_pickup_lat::double precision))
          * sin(radians(o.center_latitude::double precision))
        ))
      )
    )
    limit 1;
    v_has_override := found;
  end if;

  if v_has_override and v_override.level <> 'automatic' then
    v_multiplier := greatest(1,least(v_override.multiplier,v_settings.max_multiplier));
    v_level := v_override.level;
    v_requests := v_override.synthetic_requests;
    v_drivers := v_override.synthetic_drivers;
    v_ratio := case
      when v_drivers <= 0 then v_requests
      else v_requests::numeric / v_drivers::numeric
    end;
    v_sector := 'qa:' || v_override.city_key;
  else
    select count(*)::integer into v_requests
    from public.ride_requests rr
    where rr.status in ('searching')
      and rr.category = coalesce(nullif(trim(p_service_key),''),rr.category)
      and rr.created_at >= now() - make_interval(mins => v_settings.window_minutes)
      and rr.pickup_latitude is not null
      and rr.pickup_longitude is not null
      and rr.pickup_address not like '[LOADTEST:%'
      and not exists (
        select 1
        from public.audit_load_test_entities e
        join public.audit_load_test_runs r on r.id=e.run_id
        where e.ride_request_id=rr.id
          and r.status in ('creating','active','failed','cleaning')
      )
      and (
        6371 * acos(
          least(1,greatest(-1,
            cos(radians(p_pickup_lat::double precision))
            * cos(radians(rr.pickup_latitude::double precision))
            * cos(radians(rr.pickup_longitude::double precision)-radians(p_pickup_lng::double precision))
            + sin(radians(p_pickup_lat::double precision))
            * sin(radians(rr.pickup_latitude::double precision))
          ))
        )
      ) <= v_settings.radius_km;

    select count(*)::integer into v_drivers
    from public.driver_profiles dp
    where dp.approval_status='approved'
      and dp.online_status='online'
      and dp.latitude is not null
      and dp.longitude is not null
      and dp.updated_at >= now() - interval '10 minutes'
      and not exists (
        select 1
        from public.audit_load_test_entities e
        join public.audit_load_test_runs r on r.id=e.run_id
        where e.user_id=dp.id
          and e.entity_type='driver'
          and r.status in ('creating','active','failed','cleaning')
      )
      and (
        p_service_key <> 'motorcycle'
        or exists (
          select 1 from public.driver_vehicles dv
          where dv.driver_id=dp.id
            and dv.is_active=true
            and dv.vehicle_type='motorcycle'
        )
      )
      and (
        6371 * acos(
          least(1,greatest(-1,
            cos(radians(p_pickup_lat::double precision))
            * cos(radians(dp.latitude::double precision))
            * cos(radians(dp.longitude::double precision)-radians(p_pickup_lng::double precision))
            + sin(radians(p_pickup_lat::double precision))
            * sin(radians(dp.latitude::double precision))
          ))
        )
      ) <= v_settings.radius_km;

    if v_requests < v_settings.min_requests then
      v_ratio := case when v_drivers > 0 then v_requests::numeric/v_drivers else v_requests end;
      v_multiplier := 1;
      v_level := 'normal';
    else
      v_ratio := case when v_drivers > 0 then v_requests::numeric/v_drivers else v_requests end;
      if v_drivers = 0 or v_ratio >= v_settings.critical_ratio then
        v_multiplier := v_settings.max_multiplier;
        v_level := 'critical';
      elsif v_ratio >= v_settings.high_ratio then
        v_multiplier := least(v_settings.critical_multiplier,v_settings.max_multiplier);
        v_level := 'high';
      elsif v_ratio >= v_settings.elevated_ratio then
        v_multiplier := least(v_settings.high_multiplier,v_settings.max_multiplier);
        v_level := 'medium';
      else
        v_multiplier := least(v_settings.elevated_multiplier,v_settings.max_multiplier);
        v_level := 'elevated';
      end if;
    end if;
  end if;

  return v_base_quote || jsonb_build_object(
    'base_amount', round(v_base_amount,2),
    'demand_multiplier', round(v_multiplier,2),
    'demand_level', v_level,
    'demand_requests', v_requests,
    'demand_drivers', v_drivers,
    'demand_ratio', round(v_ratio,2),
    'demand_sector_key', v_sector,
    'dynamic_pricing_enabled', true,
    'preview_mode', p_preview,
    'amount', round(v_base_amount * v_multiplier,2)
  );
end;
$$;

grant execute on function public.dynamic_pricing_quote(text,numeric,numeric,numeric,numeric,boolean)
to authenticated;

create or replace function public.admin_set_dynamic_pricing_qa_override(
  p_city_key text,
  p_level text,
  p_minutes integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_level text := lower(trim(coalesce(p_level,'automatic')));
  v_multiplier numeric := 1;
  v_requests integer := 0;
  v_drivers integer := 0;
  v_active boolean := true;
  v_row public.dynamic_pricing_qa_overrides%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_city_key not in ('trinidad','iquique') then raise exception 'Ciudad QA inválida'; end if;

  case v_level
    when 'automatic' then
      v_active := false;
      v_multiplier := 1;
      v_requests := 0;
      v_drivers := 0;
    when 'normal' then
      v_multiplier := 1.00;
      v_requests := 3;
      v_drivers := 8;
    when 'medium' then
      v_multiplier := 1.10;
      v_requests := 8;
      v_drivers := 5;
    when 'high' then
      v_multiplier := 1.20;
      v_requests := 12;
      v_drivers := 4;
    when 'very_high' then
      v_multiplier := 1.35;
      v_requests := 18;
      v_drivers := 4;
    when 'critical' then
      v_multiplier := 1.50;
      v_requests := 25;
      v_drivers := 3;
    else
      raise exception 'Nivel QA inválido';
  end case;

  update public.dynamic_pricing_qa_overrides
  set active=v_active,
      level=v_level,
      multiplier=v_multiplier,
      synthetic_requests=v_requests,
      synthetic_drivers=v_drivers,
      expires_at=case when v_active then now()+make_interval(mins=>greatest(5,least(coalesce(p_minutes,60),240))) else null end,
      updated_at=now(),
      updated_by=auth.uid()
  where city_key=p_city_key
  returning * into v_row;

  return jsonb_build_object(
    'city_key',v_row.city_key,
    'city_name',v_row.city_name,
    'active',v_row.active,
    'level',v_row.level,
    'multiplier',v_row.multiplier,
    'synthetic_requests',v_row.synthetic_requests,
    'synthetic_drivers',v_row.synthetic_drivers,
    'expires_at',v_row.expires_at
  );
end;
$$;

revoke all on function public.admin_set_dynamic_pricing_qa_override(text,text,integer)
from public,anon;
grant execute on function public.admin_set_dynamic_pricing_qa_override(text,text,integer)
to authenticated;

create or replace function public.admin_dynamic_pricing_qa_state()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return jsonb_build_object(
    'settings',(select to_jsonb(s) from public.dynamic_pricing_settings s where id=true),
    'cities',coalesce((
      select jsonb_agg(to_jsonb(o) order by o.city_name)
      from public.dynamic_pricing_qa_overrides o
    ),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_dynamic_pricing_qa_state() from public,anon;
grant execute on function public.admin_dynamic_pricing_qa_state() to authenticated;

-- Return driver heading to the rider map.
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
  v_requested text := nullif(lower(trim(coalesce(p_vehicle_type,''))),'');
  v_uid uuid := auth.uid();
  v_audit boolean := false;
  v_limit integer := 16;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;

  select exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid and m.enabled=true and g.active=true
  ) into v_audit;
  if v_audit then v_limit := 250; end if;

  with candidates as (
    select
      round(dp.latitude::numeric,5) as latitude,
      round(dp.longitude::numeric,5) as longitude,
      coalesce(dp.heading_degrees,0) as heading_degrees,
      coalesce(
        (select dv.vehicle_type from public.driver_vehicles dv
         where dv.driver_id=dp.id and dv.is_active=true
         order by dv.updated_at desc limit 1),
        case
          when lower(coalesce(dp.vehicle_summary,'')) like '%moto%' then 'motorcycle'
          when lower(coalesce(dp.vehicle_summary,'')) like '%xl%' then 'xl'
          else 'car'
        end
      ) as vehicle_type,
      (6371*acos(least(1,greatest(-1,
        cos(radians(p_lat::double precision))
        * cos(radians(dp.latitude::double precision))
        * cos(radians(dp.longitude::double precision)-radians(p_lng::double precision))
        + sin(radians(p_lat::double precision))
        * sin(radians(dp.latitude::double precision))
      )))) as distance_km
    from public.driver_profiles dp
    where dp.approval_status='approved'
      and dp.online_status='online'
      and dp.latitude is not null
      and dp.longitude is not null
      and public.same_operational_scope(v_uid,dp.id)
  )
  select coalesce(
    jsonb_agg(jsonb_build_object(
      'latitude',latitude,
      'longitude',longitude,
      'vehicle_type',vehicle_type,
      'heading_degrees',heading_degrees,
      'distance_km',round(distance_km::numeric,1)
    ) order by distance_km),'[]'::jsonb
  )
  into v_result
  from (
    select * from candidates
    where distance_km <= greatest(0.5,least(coalesce(p_radius_km,5),20))
      and (v_requested is null or vehicle_type=v_requested)
    order by distance_km
    limit v_limit
  ) q;

  return v_result;
end;
$$;

grant execute on function public.nearby_online_driver_markers(numeric,numeric,numeric,text)
to authenticated;
