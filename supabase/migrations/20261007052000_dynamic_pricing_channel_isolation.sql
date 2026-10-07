-- Strict Preview/Production isolation for dynamic pricing parameters.
-- Existing values are copied into both channels so behavior is unchanged at migration time.

create table if not exists public.dynamic_pricing_channel_settings (
  channel text primary key check (channel in ('preview','production')),
  enabled boolean not null,
  radius_km numeric not null check (radius_km between 0.25 and 5),
  window_minutes integer not null check (window_minutes between 1 and 30),
  min_requests integer not null check (min_requests between 1 and 100),
  elevated_ratio numeric not null,
  high_ratio numeric not null,
  critical_ratio numeric not null,
  elevated_multiplier numeric not null,
  high_multiplier numeric not null,
  critical_multiplier numeric not null,
  max_multiplier numeric not null,
  low_ratio numeric not null check (low_ratio between 0 and 1),
  low_multiplier numeric not null check (low_multiplier between 0.50 and 1),
  low_min_drivers integer not null check (low_min_drivers between 1 and 1000),
  updated_at timestamptz not null default now(),
  updated_by uuid
);

insert into public.dynamic_pricing_channel_settings(
  channel,enabled,radius_km,window_minutes,min_requests,
  elevated_ratio,high_ratio,critical_ratio,
  elevated_multiplier,high_multiplier,critical_multiplier,max_multiplier,
  low_ratio,low_multiplier,low_min_drivers,updated_at,updated_by
)
select
  'preview',
  preview_enabled,
  radius_km,window_minutes,min_requests,
  elevated_ratio,high_ratio,critical_ratio,
  elevated_multiplier,high_multiplier,critical_multiplier,max_multiplier,
  low_ratio,low_multiplier,low_min_drivers,updated_at,updated_by
from public.dynamic_pricing_settings
where id=true
on conflict(channel) do nothing;

insert into public.dynamic_pricing_channel_settings(
  channel,enabled,radius_km,window_minutes,min_requests,
  elevated_ratio,high_ratio,critical_ratio,
  elevated_multiplier,high_multiplier,critical_multiplier,max_multiplier,
  low_ratio,low_multiplier,low_min_drivers,updated_at,updated_by
)
select
  'production',
  production_enabled,
  radius_km,window_minutes,min_requests,
  elevated_ratio,high_ratio,critical_ratio,
  elevated_multiplier,high_multiplier,critical_multiplier,max_multiplier,
  low_ratio,low_multiplier,low_min_drivers,updated_at,updated_by
from public.dynamic_pricing_settings
where id=true
on conflict(channel) do nothing;

alter table public.dynamic_pricing_channel_settings enable row level security;

drop policy if exists "dynamic pricing channel settings admin read"
  on public.dynamic_pricing_channel_settings;
create policy "dynamic pricing channel settings admin read"
on public.dynamic_pricing_channel_settings for select
to authenticated
using (public.is_admin());

drop policy if exists "dynamic pricing channel settings admin manage"
  on public.dynamic_pricing_channel_settings;
create policy "dynamic pricing channel settings admin manage"
on public.dynamic_pricing_channel_settings for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

revoke all on public.dynamic_pricing_channel_settings from public, anon;
grant select,insert,update,delete on public.dynamic_pricing_channel_settings
to authenticated;

create or replace function public.dynamic_pricing_quote_internal(
  p_service_key text,
  p_distance_km numeric,
  p_duration_minutes numeric,
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_preview boolean:=v_channel='preview';
  v_base_quote jsonb;
  v_settings record;
  v_base_amount numeric:=0;
  v_minimum numeric:=0;
  v_multiplier numeric:=1;
  v_level text:='normal';
  v_requests integer:=0;
  v_drivers integer:=0;
  v_ratio numeric:=0;
  v_enabled boolean:=false;
  v_override public.dynamic_pricing_qa_overrides%rowtype;
  v_has_override boolean:=false;
  v_sector text;
  v_amount numeric:=0;
  v_currency text:='BOB';
begin
  if p_pickup_lat is not null and p_pickup_lng is not null then
    v_base_quote:=public.quote_service_fare_for_location_base(
      p_service_key,p_distance_km,p_duration_minutes,p_pickup_lat,p_pickup_lng
    );
  else
    v_base_quote:=public.quote_service_fare(
      p_service_key,p_distance_km,p_duration_minutes
    );
  end if;

  v_base_amount:=coalesce((v_base_quote->>'amount')::numeric,0);
  v_minimum:=coalesce(
    nullif(v_base_quote->>'minimum_fare','')::numeric,
    nullif(v_base_quote->'rule'->>'minimum_fare','')::numeric,
    v_base_amount
  );
  v_currency:=coalesce(nullif(v_base_quote->>'currency',''),'BOB');

  select * into v_settings
  from public.dynamic_pricing_channel_settings
  where channel=v_channel;

  if not found then
    raise exception 'Configuración de demanda dinámica no disponible para %', v_channel;
  end if;

  v_enabled:=coalesce(v_settings.enabled,false);

  v_sector:=concat(
    round(coalesce(p_pickup_lat,0)::numeric,3),':',
    round(coalesce(p_pickup_lng,0)::numeric,3)
  );

  if not v_enabled or p_pickup_lat is null or p_pickup_lng is null then
    return v_base_quote || jsonb_build_object(
      'base_amount',round(v_base_amount,2),
      'recommended_fare',round(v_base_amount,2),
      'minimum_allowed_fare',round(v_base_amount,2),
      'demand_multiplier',1,
      'demand_level','normal',
      'demand_requests',0,
      'demand_drivers',0,
      'demand_ratio',0,
      'demand_sector_key',v_sector,
      'dynamic_pricing_enabled',v_enabled,
      'channel',v_channel,
      'amount',round(v_base_amount,2)
    );
  end if;

  if v_preview then
    select o.* into v_override
    from public.dynamic_pricing_qa_overrides o
    where o.active=true
      and (o.expires_at is null or o.expires_at>now())
      and (
        6371*acos(least(1,greatest(-1,
          cos(radians(p_pickup_lat::double precision))
          *cos(radians(o.center_latitude::double precision))
          *cos(radians(o.center_longitude::double precision)-radians(p_pickup_lng::double precision))
          +sin(radians(p_pickup_lat::double precision))
          *sin(radians(o.center_latitude::double precision))
        )))
      )<=30
    order by (
      6371*acos(least(1,greatest(-1,
        cos(radians(p_pickup_lat::double precision))
        *cos(radians(o.center_latitude::double precision))
        *cos(radians(o.center_longitude::double precision)-radians(p_pickup_lng::double precision))
        +sin(radians(p_pickup_lat::double precision))
        *sin(radians(o.center_latitude::double precision))
      )))
    )
    limit 1;
    v_has_override:=found;
  end if;

  if v_has_override and v_override.level<>'automatic' then
    v_multiplier:=greatest(
      greatest(v_settings.low_multiplier,0.50),
      least(v_override.multiplier,v_settings.max_multiplier)
    );
    v_level:=v_override.level;
    v_requests:=v_override.synthetic_requests;
    v_drivers:=v_override.synthetic_drivers;
    v_ratio:=case when v_drivers<=0 then v_requests else v_requests::numeric/v_drivers end;
    v_sector:='qa:'||v_override.city_key;
  else
    select count(*)::integer into v_requests
    from public.ride_requests rr
    where rr.status='searching'
      and rr.channel=v_channel
      and rr.category=coalesce(nullif(trim(p_service_key),''),rr.category)
      and rr.created_at>=now()-make_interval(mins=>v_settings.window_minutes)
      and rr.pickup_latitude is not null
      and rr.pickup_longitude is not null
      and rr.pickup_address not like '[LOADTEST:%'
      and not exists(
        select 1
        from public.audit_load_test_entities e
        join public.audit_load_test_runs r on r.id=e.run_id
        where e.ride_request_id=rr.id
          and r.status in ('creating','active','failed','cleaning')
      )
      and (
        6371*acos(least(1,greatest(-1,
          cos(radians(p_pickup_lat::double precision))
          *cos(radians(rr.pickup_latitude::double precision))
          *cos(radians(rr.pickup_longitude::double precision)-radians(p_pickup_lng::double precision))
          +sin(radians(p_pickup_lat::double precision))
          *sin(radians(rr.pickup_latitude::double precision))
        )))
      )<=v_settings.radius_km;

    select count(*)::integer into v_drivers
    from public.driver_profiles dp
    where dp.approval_status='approved'
      and dp.online_status='online'
      and dp.latitude is not null
      and dp.longitude is not null
      and dp.updated_at>=now()-interval '10 minutes'
      and coalesce(public.is_active_audit_user(dp.id),false)=v_preview
      and not exists(
        select 1
        from public.audit_load_test_entities e
        join public.audit_load_test_runs r on r.id=e.run_id
        where e.user_id=dp.id
          and e.entity_type='driver'
          and r.status in ('creating','active','failed','cleaning')
      )
      and (
        p_service_key not in ('motorcycle','xl')
        or exists(
          select 1 from public.driver_vehicles dv
          where dv.driver_id=dp.id
            and dv.is_active=true
            and (
              (p_service_key='motorcycle' and dv.vehicle_type='motorcycle')
              or (p_service_key='xl' and dv.vehicle_type='xl')
            )
        )
      )
      and (
        6371*acos(least(1,greatest(-1,
          cos(radians(p_pickup_lat::double precision))
          *cos(radians(dp.latitude::double precision))
          *cos(radians(dp.longitude::double precision)-radians(p_pickup_lng::double precision))
          +sin(radians(p_pickup_lat::double precision))
          *sin(radians(dp.latitude::double precision))
        )))
      )<=v_settings.radius_km;

    v_ratio:=case when v_drivers>0 then v_requests::numeric/v_drivers else v_requests end;

    if v_drivers>=v_settings.low_min_drivers
       and v_ratio<=v_settings.low_ratio then
      v_multiplier:=v_settings.low_multiplier;
      v_level:='low';
    elsif v_requests<v_settings.min_requests then
      v_multiplier:=1;
      v_level:='normal';
    elsif v_drivers=0 or v_ratio>=v_settings.critical_ratio then
      v_multiplier:=v_settings.max_multiplier;
      v_level:='critical';
    elsif v_ratio>=v_settings.high_ratio then
      v_multiplier:=least(v_settings.critical_multiplier,v_settings.max_multiplier);
      v_level:='high';
    elsif v_ratio>=v_settings.elevated_ratio then
      v_multiplier:=least(v_settings.high_multiplier,v_settings.max_multiplier);
      v_level:='medium';
    else
      v_multiplier:=least(v_settings.elevated_multiplier,v_settings.max_multiplier);
      v_level:='elevated';
    end if;
  end if;

  v_amount:=v_base_amount*v_multiplier;
  if v_multiplier<1 then
    v_amount:=greatest(v_minimum,v_amount);
  end if;
  v_amount:=round(v_amount,2);

  return v_base_quote || jsonb_build_object(
    'base_amount',round(v_base_amount,2),
    'recommended_fare',v_amount,
    'minimum_allowed_fare',v_amount,
    'demand_multiplier',round(v_multiplier,2),
    'demand_level',v_level,
    'demand_requests',v_requests,
    'demand_drivers',v_drivers,
    'demand_ratio',round(v_ratio,2),
    'demand_sector_key',v_sector,
    'dynamic_pricing_enabled',true,
    'channel',v_channel,
    'currency',v_currency,
    'amount',v_amount
  );
end;
$$;

revoke all on function public.dynamic_pricing_quote_internal(text,numeric,numeric,numeric,numeric,text)
from public,anon,authenticated;

create or replace function public.admin_update_dynamic_pricing_settings(
  p_channel text,
  p_enabled boolean,
  p_low_ratio numeric default null,
  p_low_multiplier numeric default null,
  p_low_min_drivers integer default null,
  p_radius_km numeric default null,
  p_window_minutes integer default null,
  p_min_requests integer default null,
  p_elevated_ratio numeric default null,
  p_high_ratio numeric default null,
  p_critical_ratio numeric default null,
  p_elevated_multiplier numeric default null,
  p_high_multiplier numeric default null,
  p_critical_multiplier numeric default null,
  p_max_multiplier numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_row public.dynamic_pricing_channel_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  update public.dynamic_pricing_channel_settings
  set enabled=coalesce(p_enabled,enabled),
      low_ratio=coalesce(p_low_ratio,low_ratio),
      low_multiplier=coalesce(p_low_multiplier,low_multiplier),
      low_min_drivers=coalesce(p_low_min_drivers,low_min_drivers),
      radius_km=coalesce(p_radius_km,radius_km),
      window_minutes=coalesce(p_window_minutes,window_minutes),
      min_requests=coalesce(p_min_requests,min_requests),
      elevated_ratio=coalesce(p_elevated_ratio,elevated_ratio),
      high_ratio=coalesce(p_high_ratio,high_ratio),
      critical_ratio=coalesce(p_critical_ratio,critical_ratio),
      elevated_multiplier=coalesce(p_elevated_multiplier,elevated_multiplier),
      high_multiplier=coalesce(p_high_multiplier,high_multiplier),
      critical_multiplier=coalesce(p_critical_multiplier,critical_multiplier),
      max_multiplier=coalesce(p_max_multiplier,max_multiplier),
      updated_at=now(),
      updated_by=auth.uid()
  where channel=v_channel
  returning * into v_row;

  if not found then
    raise exception 'Configuración de demanda dinámica no disponible para %', v_channel;
  end if;

  update public.dynamic_pricing_settings
  set preview_enabled=case
        when v_channel='preview' then v_row.enabled
        else preview_enabled
      end,
      production_enabled=case
        when v_channel='production' then v_row.enabled
        else production_enabled
      end,
      updated_at=now(),
      updated_by=auth.uid()
  where id=true;

  return to_jsonb(v_row);
end;
$$;

revoke all on function public.admin_update_dynamic_pricing_settings(
  text,boolean,numeric,numeric,integer,numeric,integer,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,numeric
) from public,anon;
grant execute on function public.admin_update_dynamic_pricing_settings(
  text,boolean,numeric,numeric,integer,numeric,integer,integer,
  numeric,numeric,numeric,numeric,numeric,numeric,numeric
) to authenticated;

create or replace function public.admin_dynamic_pricing_qa_state_scoped(
  p_zone_id uuid,
  p_channel text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_zone_key text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select zone_key into v_zone_key
  from public.service_zones
  where id=p_zone_id
  limit 1;

  return jsonb_build_object(
    'settings',(
      select to_jsonb(s)
      from public.dynamic_pricing_channel_settings s
      where s.channel=v_channel
    ),
    'cities',case
      when v_channel='preview' then coalesce((
        select jsonb_agg(to_jsonb(o) order by o.city_name)
        from public.dynamic_pricing_qa_overrides o
        where o.city_key=v_zone_key
      ),'[]'::jsonb)
      else '[]'::jsonb
    end
  );
end;
$$;

revoke all on function public.admin_dynamic_pricing_qa_state_scoped(uuid,text)
from public,anon;
grant execute on function public.admin_dynamic_pricing_qa_state_scoped(uuid,text)
to authenticated;

comment on table public.dynamic_pricing_channel_settings is
  'Authoritative dynamic pricing parameters isolated by runtime channel.';

comment on function public.admin_dynamic_pricing_qa_state_scoped(uuid,text) is
  'Returns only the selected runtime channel dynamic-pricing settings and the selected zone QA override.';
