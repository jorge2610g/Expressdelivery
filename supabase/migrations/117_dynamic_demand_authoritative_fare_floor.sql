alter table public.dynamic_pricing_settings
  add column if not exists low_ratio numeric not null default 0.50,
  add column if not exists low_multiplier numeric not null default 0.90,
  add column if not exists low_min_drivers integer not null default 2;

alter table public.dynamic_pricing_settings
  drop constraint if exists dynamic_pricing_settings_low_ratio_check,
  add constraint dynamic_pricing_settings_low_ratio_check
    check (low_ratio between 0 and 1),
  drop constraint if exists dynamic_pricing_settings_low_multiplier_check,
  add constraint dynamic_pricing_settings_low_multiplier_check
    check (low_multiplier between 0.50 and 1),
  drop constraint if exists dynamic_pricing_settings_low_min_drivers_check,
  add constraint dynamic_pricing_settings_low_min_drivers_check
    check (low_min_drivers between 1 and 1000);

-- Base location quote, deliberately free of dynamic-demand recursion.
create or replace function public.quote_service_fare_for_location_base(
  p_service_key text,
  p_distance_km numeric,
  p_duration_minutes numeric,
  p_lat numeric,
  p_lng numeric
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_zone_id uuid;
  v_rule jsonb;
  v_base numeric := 0;
  v_per_km numeric := 0;
  v_per_minute numeric := 0;
  v_minimum numeric := 0;
  v_surge numeric := 1;
  v_amount numeric := 0;
  v_currency text := 'BOB';
  v_zone_key text;
begin
  v_zone_id := public.service_zone_id_for_point(p_lat,p_lng);
  if v_zone_id is null then
    raise exception 'Fuera de una zona activa de Express';
  end if;

  select zone_key,currency_code into v_zone_key,v_currency
  from public.service_zones where id=v_zone_id;

  if not exists(
    select 1
    from public.zone_service_catalog zs
    where zs.zone_id=v_zone_id
      and zs.service_key=p_service_key
      and zs.enabled=true
      and zs.passenger_visible=true
  ) then
    raise exception 'Servicio no disponible en esta zona';
  end if;

  v_rule := public.effective_fare_rule(
    nullif(trim(coalesce(p_service_key,'')),''),
    v_zone_id
  );

  if v_rule is null then
    select coalesce(
      case when p_service_key='delivery' then min_delivery_fare else min_ride_fare end,
      0
    )
    into v_minimum
    from public.app_settings where id=true;
    v_amount := v_minimum;
  else
    v_base := coalesce((v_rule->>'base_fare')::numeric,0);
    v_per_km := coalesce((v_rule->>'per_km')::numeric,0);
    v_per_minute := coalesce((v_rule->>'per_minute')::numeric,0);
    v_minimum := coalesce((v_rule->>'minimum_fare')::numeric,0);
    v_surge := greatest(coalesce((v_rule->>'surge_multiplier')::numeric,1),1);

    v_amount := greatest(
      v_minimum,
      (
        v_base
        + v_per_km * greatest(coalesce(p_distance_km,0),0)
        + v_per_minute * greatest(coalesce(p_duration_minutes,0),0)
      ) * v_surge
    );
  end if;

  return jsonb_build_object(
    'amount',round(v_amount,2),
    'base_amount',round(v_amount,2),
    'minimum_fare',round(v_minimum,2),
    'currency',coalesce(v_currency,'BOB'),
    'zone_id',v_zone_id,
    'zone_key',v_zone_key,
    'distance_km',round(greatest(coalesce(p_distance_km,0),0),2),
    'duration_minutes',greatest(round(coalesce(p_duration_minutes,0)),0),
    'rule',v_rule
  );
end;
$$;

revoke all on function public.quote_service_fare_for_location_base(text,numeric,numeric,numeric,numeric)
from public,anon,authenticated;

-- Internal authoritative quote. It is used by both public quote RPCs and the
-- database trigger, so direct API writes cannot bypass the recommended floor.
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
  v_settings public.dynamic_pricing_settings%rowtype;
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
  from public.dynamic_pricing_settings
  where id=true;

  v_enabled:=case
    when v_preview then coalesce(v_settings.preview_enabled,false)
    else coalesce(v_settings.production_enabled,false)
  end;

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
stable security definer
set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  return public.dynamic_pricing_quote_internal(
    p_service_key,p_distance_km,p_duration_minutes,
    p_pickup_lat,p_pickup_lng,
    case when p_preview then 'preview' else 'production' end
  );
end;
$$;

revoke all on function public.dynamic_pricing_quote(text,numeric,numeric,numeric,numeric,boolean)
from public,anon;
grant execute on function public.dynamic_pricing_quote(text,numeric,numeric,numeric,numeric,boolean)
to authenticated;

-- Existing app RPC now returns the authoritative zone + demand quote, so the
-- current Passenger UI receives the adjusted amount without requiring a new
-- native build.
create or replace function public.quote_service_fare_for_location(
  p_service_key text,
  p_distance_km numeric,
  p_duration_minutes numeric,
  p_lat numeric,
  p_lng numeric
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_channel text:='production';
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if coalesce(public.is_active_audit_user(auth.uid()),false) then
    v_channel:='preview';
  end if;
  return public.dynamic_pricing_quote_internal(
    p_service_key,p_distance_km,p_duration_minutes,p_lat,p_lng,v_channel
  );
end;
$$;

revoke all on function public.quote_service_fare_for_location(text,numeric,numeric,numeric,numeric)
from public,anon;
grant execute on function public.quote_service_fare_for_location(text,numeric,numeric,numeric,numeric)
to authenticated;

create or replace function public.enforce_ride_recommended_fare_floor()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_quote jsonb;
  v_floor numeric;
  v_currency text;
begin
  if coalesce(new.pricing_mode,'offer')='fixed' then
    return new;
  end if;

  if new.pickup_latitude is null or new.pickup_longitude is null then
    return new;
  end if;

  v_quote:=public.dynamic_pricing_quote_internal(
    new.category,
    coalesce(new.route_distance_km,0),
    coalesce(new.route_duration_minutes,0),
    new.pickup_latitude,
    new.pickup_longitude,
    new.channel
  );

  v_floor:=coalesce((v_quote->>'minimum_allowed_fare')::numeric,0);
  v_currency:=coalesce(v_quote->>'currency',new.currency,'BOB');

  if new.proposed_fare is null or new.proposed_fare<v_floor then
    raise exception 'La tarifa mínima recomendada actual es % %',
      trim(to_char(v_floor,'FM999999990.00')),v_currency;
  end if;

  new.base_fare:=coalesce((v_quote->>'base_amount')::numeric,new.base_fare);
  new.demand_multiplier:=coalesce((v_quote->>'demand_multiplier')::numeric,1);
  new.demand_level:=coalesce(v_quote->>'demand_level','normal');
  new.demand_requests:=coalesce((v_quote->>'demand_requests')::integer,0);
  new.demand_drivers:=coalesce((v_quote->>'demand_drivers')::integer,0);
  new.demand_sector_key:=v_quote->>'demand_sector_key';
  new.currency:=v_currency;
  return new;
end;
$$;

revoke all on function public.enforce_ride_recommended_fare_floor()
from public,anon,authenticated;

drop trigger if exists zzz_ride_recommended_fare_floor on public.ride_requests;
create trigger zzz_ride_recommended_fare_floor
before insert or update of category,pickup_latitude,pickup_longitude,
  route_distance_km,route_duration_minutes,proposed_fare,channel
on public.ride_requests
for each row execute function public.enforce_ride_recommended_fare_floor();

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
  v_level text:=lower(trim(coalesce(p_level,'automatic')));
  v_multiplier numeric:=1;
  v_requests integer:=0;
  v_drivers integer:=0;
  v_active boolean:=true;
  v_row public.dynamic_pricing_qa_overrides%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_city_key not in ('trinidad','iquique') then raise exception 'Ciudad QA inválida'; end if;

  case v_level
    when 'automatic' then v_active:=false; v_multiplier:=1; v_requests:=0; v_drivers:=0;
    when 'low' then v_multiplier:=0.90; v_requests:=1; v_drivers:=5;
    when 'normal' then v_multiplier:=1.00; v_requests:=3; v_drivers:=8;
    when 'medium' then v_multiplier:=1.10; v_requests:=8; v_drivers:=5;
    when 'high' then v_multiplier:=1.20; v_requests:=12; v_drivers:=4;
    when 'very_high' then v_multiplier:=1.35; v_requests:=18; v_drivers:=4;
    when 'critical' then v_multiplier:=1.50; v_requests:=25; v_drivers:=3;
    else raise exception 'Nivel QA inválido';
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
  v_row public.dynamic_pricing_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  update public.dynamic_pricing_settings
  set preview_enabled=case when v_channel='preview' then coalesce(p_enabled,preview_enabled) else preview_enabled end,
      production_enabled=case when v_channel='production' then coalesce(p_enabled,production_enabled) else production_enabled end,
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
  where id=true
  returning * into v_row;

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

-- Preview stays enabled for QA. Production remains deliberately disabled until
-- the exact Preview candidate passes the release gate and is promoted.
update public.dynamic_pricing_settings
set preview_enabled=true,
    production_enabled=false,
    low_ratio=coalesce(low_ratio,0.50),
    low_multiplier=coalesce(low_multiplier,0.90),
    low_min_drivers=coalesce(low_min_drivers,2),
    updated_at=now()
where id=true;