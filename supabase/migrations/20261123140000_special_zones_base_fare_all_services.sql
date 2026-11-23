alter table public.fare_special_zones drop constraint if exists fare_special_zones_service_key_fkey;
create or replace function public.fare_special_zones_check_service() returns trigger language plpgsql as $$
begin
  if new.service_key <> '*' and not exists(select 1 from public.service_catalog where service_key=new.service_key) then
    raise exception 'Servicio inexistente: %', new.service_key;
  end if;
  return new;
end $$;
drop trigger if exists fare_special_zones_check_service on public.fare_special_zones;
create trigger fare_special_zones_check_service before insert or update of service_key on public.fare_special_zones
  for each row execute function public.fare_special_zones_check_service();

-- Zonas especiales (aeropuerto, terminal): cambian la TARIFA BASE, no el precio total.
-- El viaje se cotiza igual que uno normal (base + km + minutos, mínimo, demanda),
-- pero la base y el mínimo son los de la zona especial cuando el origen o el
-- destino caen dentro de su polígono. service_key '*' = todos los servicios.

create or replace function public.special_fare_for_route(
  p_zone_id uuid, p_service_key text,
  p_pickup_lat numeric, p_pickup_lng numeric,
  p_destination_lat numeric, p_destination_lng numeric)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select to_jsonb(x) from (
    select s.id, s.zone_id, s.name, s.zone_type, s.service_key, s.fixed_fare, s.priority,
      case when p_pickup_lat is not null and p_pickup_lng is not null
            and public.point_in_json_polygon(p_pickup_lat,p_pickup_lng,s.polygon) then true else false end as pickup_inside,
      case when p_destination_lat is not null and p_destination_lng is not null
            and public.point_in_json_polygon(p_destination_lat,p_destination_lng,s.polygon) then true else false end as destination_inside
    from public.fare_special_zones s
    where s.active=true and s.zone_id=p_zone_id
      and (s.service_key=p_service_key or s.service_key='*')
      and ((p_pickup_lat is not null and p_pickup_lng is not null and public.point_in_json_polygon(p_pickup_lat,p_pickup_lng,s.polygon))
        or (p_destination_lat is not null and p_destination_lng is not null and public.point_in_json_polygon(p_destination_lat,p_destination_lng,s.polygon)))
    order by s.priority desc, (s.service_key <> '*') desc, s.fixed_fare desc, s.created_at
    limit 1
  ) x;
$$;

drop function if exists public.quote_service_fare_for_location_base(text, numeric, numeric, numeric, numeric);
create or replace function public.quote_service_fare_for_location_base(
  p_service_key text, p_distance_km numeric, p_duration_minutes numeric,
  p_lat numeric, p_lng numeric,
  p_dest_lat numeric default null, p_dest_lng numeric default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_zone_id uuid; v_rule jsonb; v_base numeric := 0; v_per_km numeric := 0; v_per_minute numeric := 0;
  v_minimum numeric := 0; v_surge numeric := 1; v_amount numeric := 0; v_currency text := 'BOB';
  v_zone_key text; v_tier_price numeric; v_tier_distance numeric; v_last_distance numeric;
  v_last_fare numeric; v_prev_distance numeric; v_prev_fare numeric; v_tier_applied boolean := false;
  v_special jsonb; v_special_base numeric;
begin
  v_zone_id := public.service_zone_id_for_point(p_lat,p_lng);
  if v_zone_id is null then raise exception 'Fuera de una zona activa de Express'; end if;
  select zone_key,currency_code into v_zone_key,v_currency from public.service_zones where id=v_zone_id;
  if not exists(select 1 from public.zone_service_catalog zs where zs.zone_id=v_zone_id and zs.service_key=p_service_key and zs.enabled=true and zs.passenger_visible=true) then
    raise exception 'Servicio no disponible en esta zona';
  end if;
  v_rule := public.effective_fare_rule(nullif(trim(coalesce(p_service_key,'')),''), v_zone_id);

  -- Zona especial (aeropuerto, terminal): reemplaza solo la tarifa base y el mínimo.
  v_special := public.special_fare_for_route(v_zone_id, p_service_key, p_lat, p_lng, p_dest_lat, p_dest_lng);
  if v_special is not null then v_special_base := (v_special->>'fixed_fare')::numeric; end if;
  if v_special_base is not null then
    if v_rule is null then
      v_rule := jsonb_build_object('scope_type','special','service_key',p_service_key,'zone_id',v_zone_id,
        'base_fare',v_special_base,'per_km',0,'per_minute',0,'minimum_fare',v_special_base,
        'surge_multiplier',1,'commission_percent',0);
    else
      v_rule := v_rule || jsonb_build_object('base_fare',v_special_base,
        'minimum_fare',greatest(coalesce((v_rule->>'minimum_fare')::numeric,0),v_special_base));
    end if;
  end if;

  if v_rule is null then
    select coalesce(case when p_service_key='delivery' then min_delivery_fare else min_ride_fare end,0)
      into v_minimum from public.app_settings where id=true;
    v_amount := v_minimum;
  else
    v_base := coalesce((v_rule->>'base_fare')::numeric,0);
    v_per_km := coalesce((v_rule->>'per_km')::numeric,0);
    v_per_minute := coalesce((v_rule->>'per_minute')::numeric,0);
    v_minimum := coalesce((v_rule->>'minimum_fare')::numeric,0);
    v_surge := greatest(coalesce((v_rule->>'surge_multiplier')::numeric,1),1);
    v_amount := greatest(v_minimum, (v_base + v_per_km * greatest(coalesce(p_distance_km,0),0) + v_per_minute * greatest(coalesce(p_duration_minutes,0),0)) * v_surge);
  end if;

  if v_special_base is null then
    select t.up_to_km,t.fare into v_tier_distance,v_tier_price from public.zone_distance_fare_steps t
      where t.zone_id=v_zone_id and t.service_key=p_service_key and t.up_to_km >= greatest(coalesce(p_distance_km,0),0)
      order by t.up_to_km limit 1;
    if v_tier_price is null then
      select t.up_to_km,t.fare into v_last_distance,v_last_fare from public.zone_distance_fare_steps t
        where t.zone_id=v_zone_id and t.service_key=p_service_key order by t.up_to_km desc limit 1;
      if v_last_fare is not null then
        select t.up_to_km,t.fare into v_prev_distance,v_prev_fare from public.zone_distance_fare_steps t
          where t.zone_id=v_zone_id and t.service_key=p_service_key and t.up_to_km < v_last_distance
          order by t.up_to_km desc limit 1;
        v_tier_distance := v_last_distance;
        v_tier_price := v_last_fare + ceil(greatest(coalesce(p_distance_km,0)-v_last_distance,0))
          * case when v_prev_distance is not null then greatest(0,(v_last_fare-v_prev_fare)/nullif(v_last_distance-v_prev_distance,0)) else 0 end;
      end if;
    end if;
    if v_tier_price is not null then
      v_amount := round(v_tier_price,2); v_minimum := v_amount; v_tier_applied := true;
    end if;
  end if;

  return jsonb_build_object(
    'pricing_mode',case when v_tier_applied then 'distance_steps' else 'legacy' end,
    'distance_step_up_to_km',v_tier_distance,
    'amount',round(v_amount,2), 'base_amount',round(v_amount,2), 'minimum_fare',round(v_minimum,2),
    'currency',coalesce(v_currency,'BOB'), 'zone_id',v_zone_id, 'zone_key',v_zone_key,
    'special_zone', v_special->>'name',
    'distance_km',round(greatest(coalesce(p_distance_km,0),0),2),
    'duration_minutes',greatest(round(coalesce(p_duration_minutes,0)),0),
    'rule',v_rule);
end; $$;

drop function if exists public.dynamic_pricing_quote_internal(text, numeric, numeric, numeric, numeric, text);
create or replace function public.dynamic_pricing_quote_internal(
  p_service_key text, p_distance_km numeric, p_duration_minutes numeric,
  p_pickup_lat numeric, p_pickup_lng numeric, p_channel text default 'production',
  p_dest_lat numeric default null, p_dest_lng numeric default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_channel text:='production';
  v_preview boolean:=v_channel='preview';
  v_base_quote jsonb; v_settings record; v_base_amount numeric:=0; v_minimum numeric:=0;
  v_multiplier numeric:=1; v_level text:='normal'; v_requests integer:=0; v_drivers integer:=0;
  v_ratio numeric:=0; v_enabled boolean:=false;
  v_override public.dynamic_pricing_qa_overrides%rowtype; v_has_override boolean:=false;
  v_sector text; v_amount numeric:=0; v_currency text:='BOB';
begin
  if p_pickup_lat is not null and p_pickup_lng is not null then
    v_base_quote:=public.quote_service_fare_for_location_base(p_service_key,p_distance_km,p_duration_minutes,p_pickup_lat,p_pickup_lng,p_dest_lat,p_dest_lng);
  else
    v_base_quote:=public.quote_service_fare(p_service_key,p_distance_km,p_duration_minutes);
  end if;
  v_base_amount:=coalesce((v_base_quote->>'amount')::numeric,0);
  v_minimum:=coalesce(nullif(v_base_quote->>'minimum_fare','')::numeric,nullif(v_base_quote->'rule'->>'minimum_fare','')::numeric,v_base_amount);
  v_currency:=coalesce(nullif(v_base_quote->>'currency',''),'BOB');
  select * into v_settings from public.dynamic_pricing_channel_settings where channel=v_channel;
  if not found then raise exception 'Configuración de demanda dinámica no disponible para %', v_channel; end if;
  v_enabled:=coalesce(v_settings.enabled,false);
  v_sector:=concat(round(coalesce(p_pickup_lat,0)::numeric,3),':',round(coalesce(p_pickup_lng,0)::numeric,3));
  if not v_enabled or p_pickup_lat is null or p_pickup_lng is null then
    return v_base_quote || jsonb_build_object('base_amount',round(v_base_amount,2),'recommended_fare',round(v_base_amount,2),
      'minimum_allowed_fare',round(v_base_amount,2),'demand_multiplier',1,'demand_level','normal','demand_requests',0,
      'demand_drivers',0,'demand_ratio',0,'demand_sector_key',v_sector,'dynamic_pricing_enabled',v_enabled,
      'channel',v_channel,'amount',round(v_base_amount,2));
  end if;
  if v_preview then
    select o.* into v_override from public.dynamic_pricing_qa_overrides o
    where o.active=true and (o.expires_at is null or o.expires_at>now())
      and (6371*acos(least(1,greatest(-1,cos(radians(p_pickup_lat::double precision))*cos(radians(o.center_latitude::double precision))*cos(radians(o.center_longitude::double precision)-radians(p_pickup_lng::double precision))+sin(radians(p_pickup_lat::double precision))*sin(radians(o.center_latitude::double precision))))))<=30
    order by (6371*acos(least(1,greatest(-1,cos(radians(p_pickup_lat::double precision))*cos(radians(o.center_latitude::double precision))*cos(radians(o.center_longitude::double precision)-radians(p_pickup_lng::double precision))+sin(radians(p_pickup_lat::double precision))*sin(radians(o.center_latitude::double precision)))))) limit 1;
    v_has_override:=found;
  end if;
  if v_has_override and v_override.level<>'automatic' then
    v_multiplier:=greatest(greatest(v_settings.low_multiplier,0.50),least(v_override.multiplier,v_settings.max_multiplier));
    v_level:=v_override.level; v_requests:=v_override.synthetic_requests; v_drivers:=v_override.synthetic_drivers;
    v_ratio:=case when v_drivers<=0 then v_requests else v_requests::numeric/v_drivers end;
    v_sector:='qa:'||v_override.city_key;
  else
    select count(*)::integer into v_requests from public.ride_requests rr
    where rr.status='searching' and rr.channel=v_channel
      and rr.category=coalesce(nullif(trim(p_service_key),''),rr.category)
      and rr.created_at>=now()-make_interval(mins=>v_settings.window_minutes)
      and rr.pickup_latitude is not null and rr.pickup_longitude is not null
      and rr.pickup_address not like '[LOADTEST:%'
      and not exists(select 1 from public.audit_load_test_entities e join public.audit_load_test_runs r on r.id=e.run_id
        where e.ride_request_id=rr.id and r.status in ('creating','active','failed','cleaning'))
      and (6371*acos(least(1,greatest(-1,cos(radians(p_pickup_lat::double precision))*cos(radians(rr.pickup_latitude::double precision))*cos(radians(rr.pickup_longitude::double precision)-radians(p_pickup_lng::double precision))+sin(radians(p_pickup_lat::double precision))*sin(radians(rr.pickup_latitude::double precision))))))<=v_settings.radius_km;
    select count(*)::integer into v_drivers from public.driver_profiles dp
    where dp.approval_status='approved' and dp.online_status='online' and dp.latitude is not null and dp.longitude is not null
      and dp.updated_at>=now()-interval '10 minutes'
      and coalesce(public.is_active_audit_user(dp.id),false)=v_preview
      and not exists(select 1 from public.audit_load_test_entities e join public.audit_load_test_runs r on r.id=e.run_id
        where e.user_id=dp.id and e.entity_type='driver' and r.status in ('creating','active','failed','cleaning'))
      and (p_service_key not in ('motorcycle','xl') or exists(select 1 from public.driver_vehicles dv where dv.driver_id=dp.id and dv.is_active=true
        and ((p_service_key='motorcycle' and dv.vehicle_type='motorcycle') or (p_service_key='xl' and dv.vehicle_type='xl'))))
      and (6371*acos(least(1,greatest(-1,cos(radians(p_pickup_lat::double precision))*cos(radians(dp.latitude::double precision))*cos(radians(dp.longitude::double precision)-radians(p_pickup_lng::double precision))+sin(radians(p_pickup_lat::double precision))*sin(radians(dp.latitude::double precision))))))<=v_settings.radius_km;
    v_ratio:=case when v_drivers>0 then v_requests::numeric/v_drivers else v_requests end;
    if v_drivers>=v_settings.low_min_drivers and v_ratio<=v_settings.low_ratio then v_multiplier:=v_settings.low_multiplier; v_level:='low';
    elsif v_requests<v_settings.min_requests then v_multiplier:=1; v_level:='normal';
    elsif v_drivers=0 or v_ratio>=v_settings.critical_ratio then v_multiplier:=v_settings.max_multiplier; v_level:='critical';
    elsif v_ratio>=v_settings.high_ratio then v_multiplier:=least(v_settings.critical_multiplier,v_settings.max_multiplier); v_level:='high';
    elsif v_ratio>=v_settings.elevated_ratio then v_multiplier:=least(v_settings.high_multiplier,v_settings.max_multiplier); v_level:='medium';
    else v_multiplier:=least(v_settings.elevated_multiplier,v_settings.max_multiplier); v_level:='elevated';
    end if;
  end if;
  v_amount:=v_base_amount*v_multiplier;
  if v_multiplier<1 then v_amount:=greatest(v_minimum,v_amount); end if;
  v_amount:=round(v_amount,2);
  return v_base_quote || jsonb_build_object('base_amount',round(v_base_amount,2),'recommended_fare',v_amount,'minimum_allowed_fare',v_amount,
    'demand_multiplier',round(v_multiplier,2),'demand_level',v_level,'demand_requests',v_requests,'demand_drivers',v_drivers,
    'demand_ratio',round(v_ratio,2),'demand_sector_key',v_sector,'dynamic_pricing_enabled',true,'channel',v_channel,
    'currency',v_currency,'amount',v_amount);
end; $$;

drop function if exists public.quote_service_fare_for_location(text, numeric, numeric, numeric, numeric);
create or replace function public.quote_service_fare_for_location(
  p_service_key text, p_distance_km numeric, p_duration_minutes numeric, p_lat numeric, p_lng numeric,
  p_dest_lat numeric default null, p_dest_lng numeric default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_channel text:='production'; v_quote jsonb;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  select 'production' into v_channel from public.account_runtime_bindings b where b.user_id=auth.uid();
  if v_channel is null then v_channel:='production'; end if;
  v_quote:=public.dynamic_pricing_quote_internal(p_service_key,p_distance_km,p_duration_minutes,p_lat,p_lng,v_channel,p_dest_lat,p_dest_lng);
  v_quote:=public.fare_round_quote(v_quote,v_channel);
  return v_quote || jsonb_build_object('price_mode', coalesce((
    select zs.price_mode from public.zone_service_catalog zs
    where zs.zone_id = nullif(v_quote->>'zone_id','')::uuid and zs.service_key = p_service_key),'offer'));
end $$;
revoke all on function public.quote_service_fare_for_location(text,numeric,numeric,numeric,numeric,numeric,numeric) from public, anon;
grant execute on function public.quote_service_fare_for_location(text,numeric,numeric,numeric,numeric,numeric,numeric) to authenticated;

-- La zona especial ya no fija el precio: solo se anota en el viaje.
create or replace function public.apply_special_fixed_fare()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_zone_id uuid; v_special jsonb;
begin
  if new.pickup_latitude is null or new.pickup_longitude is null
     or new.destination_latitude is null or new.destination_longitude is null then
    new.special_fare_zone_id:=null; new.special_fare_zone_name:=null; return new;
  end if;
  v_zone_id:=coalesce(new.zone_id, public.service_zone_id_for_point(new.pickup_latitude,new.pickup_longitude));
  if v_zone_id is null then return new; end if;
  v_special:=public.special_fare_for_route(v_zone_id,new.category,new.pickup_latitude,new.pickup_longitude,new.destination_latitude,new.destination_longitude);
  if v_special is null then
    new.special_fare_zone_id:=null; new.special_fare_zone_name:=null; return new;
  end if;
  new.zone_id:=v_zone_id;
  new.special_fare_zone_id:=(v_special->>'id')::uuid;
  new.special_fare_zone_name:=v_special->>'name';
  return new;
end; $$;

create or replace function public.enforce_ride_recommended_fare_floor()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_quote jsonb; v_floor numeric; v_currency text; v_increment numeric;
begin
  v_currency:=coalesce((select currency_code from public.service_zones where id=new.zone_id),new.currency,'BOB');
  if tg_op='INSERT' then v_increment:=public.fare_rounding_increment(v_currency,new.channel);
  else v_increment:=coalesce(old.fare_rounding_increment,0.01); end if;
  new.fare_rounding_increment:=v_increment;
  new.proposed_fare:=public.fare_round_value(new.proposed_fare,v_increment);
  if new.base_fare is not null then new.base_fare:=public.fare_round_value(new.base_fare,v_increment); end if;
  if coalesce(new.pricing_mode,'offer')='fixed' then new.base_fare:=new.proposed_fare; return new; end if;
  if new.pickup_latitude is null or new.pickup_longitude is null then return new; end if;
  v_quote:=public.dynamic_pricing_quote_internal(new.category,coalesce(new.route_distance_km,0),coalesce(new.route_duration_minutes,0),
    new.pickup_latitude,new.pickup_longitude,new.channel,new.destination_latitude,new.destination_longitude);
  v_currency:=coalesce(v_quote->>'currency',v_currency);
  v_floor:=public.fare_round_value(coalesce((v_quote->>'minimum_allowed_fare')::numeric,0),v_increment);
  if new.proposed_fare is null or new.proposed_fare<v_floor then
    -- Zona especial: una app que cotizó sin destino sube al mínimo de la zona en vez de fallar.
    if new.special_fare_zone_id is not null and tg_op='INSERT' then
      new.proposed_fare:=v_floor;
    else
      raise exception 'La tarifa mínima recomendada actual es % %',trim(to_char(v_floor,'FM999999990.00')),v_currency;
    end if;
  end if;
  new.base_fare:=public.fare_round_value(coalesce((v_quote->>'base_amount')::numeric,new.base_fare),v_increment);
  new.demand_multiplier:=coalesce((v_quote->>'demand_multiplier')::numeric,1);
  new.demand_level:=coalesce(v_quote->>'demand_level','normal');
  new.demand_requests:=coalesce((v_quote->>'demand_requests')::integer,0);
  new.demand_drivers:=coalesce((v_quote->>'demand_drivers')::integer,0);
  new.demand_sector_key:=v_quote->>'demand_sector_key';
  new.currency:=v_currency;
  return new;
end $$;

-- El precio fijo uno a uno también respeta la base de la zona especial.
create or replace function public.apply_service_fixed_price()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_mode text; v_quote jsonb; v_increment numeric; v_fare numeric;
begin
  if new.service_mode = 'parcel' or new.zone_id is null or new.scheduled_for is not null then return new; end if;
  select zs.price_mode into v_mode from public.zone_service_catalog zs where zs.zone_id = new.zone_id and zs.service_key = new.category;
  if coalesce(v_mode, 'offer') <> 'fixed' then return new; end if;
  if new.pickup_latitude is null or new.pickup_longitude is null or coalesce(new.route_distance_km, 0) <= 0 then
    raise exception 'Faltan los datos de la ruta para calcular el precio fijo';
  end if;
  v_quote := public.dynamic_pricing_quote_internal(new.category, new.route_distance_km, coalesce(new.route_duration_minutes, 0),
    new.pickup_latitude, new.pickup_longitude, new.channel, new.destination_latitude, new.destination_longitude);
  v_increment := public.fare_rounding_increment(coalesce(v_quote->>'currency', new.currency), new.channel);
  v_fare := public.fare_round_value(coalesce((v_quote->>'minimum_allowed_fare')::numeric, (v_quote->>'amount')::numeric), v_increment);
  if v_fare is null or v_fare <= 0 then raise exception 'No se pudo calcular el precio fijo'; end if;
  new.proposed_fare := v_fare; new.base_fare := v_fare; new.pricing_mode := 'fixed'; new.dispatch_style := 'sequential';
  new.currency := coalesce(v_quote->>'currency', new.currency); new.fare_rounding_increment := v_increment;
  new.demand_multiplier := coalesce((v_quote->>'demand_multiplier')::numeric, 1);
  new.demand_level := coalesce(v_quote->>'demand_level', 'normal');
  return new;
end; $$;

-- Datos: ambas zonas con base Bs 10 y para todos los servicios.
update public.fare_special_zones set service_key='*', fixed_fare=10, updated_at=now() where zone_type in ('airport','terminal');
update public.fare_special_zones set name='Aeropuerto', updated_at=now() where name='Aereopuerto';
