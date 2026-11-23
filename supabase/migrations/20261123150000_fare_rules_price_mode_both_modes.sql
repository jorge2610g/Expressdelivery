-- Dos modos de precio por servicio: ofertas y precio fijo, con tarifa propia cada uno.
-- zone_service_catalog.price_mode: offer | fixed | both (el pasajero elige).
-- fare_rules.price_mode: offer | fixed (si no hay tarifa fija se usa la de ofertas).
-- Aplicada en Supabase como fare_rules_price_mode_both_modes.
alter table public.fare_rules add column if not exists price_mode text not null default 'offer';
alter table public.fare_rules drop constraint if exists fare_rules_price_mode_check;
alter table public.fare_rules add constraint fare_rules_price_mode_check check (price_mode in ('offer','fixed'));
drop index if exists public.fare_rules_zone_service_unique;
drop index if exists public.fare_rules_service_unique;
create unique index fare_rules_zone_service_unique on public.fare_rules (zone_id, service_key, price_mode) where scope_type='zone_service';
create unique index fare_rules_service_unique on public.fare_rules (service_key, price_mode) where scope_type='service';
alter table public.zone_service_catalog drop constraint if exists zone_service_catalog_price_mode_check;
alter table public.zone_service_catalog add constraint zone_service_catalog_price_mode_check check (price_mode in ('offer','fixed','both'));

drop function if exists public.quote_service_fare_for_location_base(text, numeric, numeric, numeric, numeric, numeric, numeric);
create or replace function public.quote_service_fare_for_location_base(
  p_service_key text, p_distance_km numeric, p_duration_minutes numeric,
  p_lat numeric, p_lng numeric,
  p_dest_lat numeric default null, p_dest_lng numeric default null,
  p_price_mode text default 'offer')
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
  v_rule := public.effective_fare_rule_at(nullif(trim(coalesce(p_service_key,'')),''), v_zone_id, now(), p_price_mode);

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


revoke all on function public.quote_service_fare_for_location_base(text,numeric,numeric,numeric,numeric,numeric,numeric,text) from public, anon;
grant execute on function public.quote_service_fare_for_location_base(text,numeric,numeric,numeric,numeric,numeric,numeric,text) to authenticated, service_role;

drop function if exists public.dynamic_pricing_quote_internal(text, numeric, numeric, numeric, numeric, text, numeric, numeric);
create or replace function public.dynamic_pricing_quote_internal(
  p_service_key text, p_distance_km numeric, p_duration_minutes numeric,
  p_pickup_lat numeric, p_pickup_lng numeric, p_channel text default 'production',
  p_dest_lat numeric default null, p_dest_lng numeric default null,
  p_price_mode text default 'offer')
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
    v_base_quote:=public.quote_service_fare_for_location_base(p_service_key,p_distance_km,p_duration_minutes,p_pickup_lat,p_pickup_lng,p_dest_lat,p_dest_lng,p_price_mode);
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

revoke all on function public.dynamic_pricing_quote_internal(text,numeric,numeric,numeric,numeric,text,numeric,numeric,text) from public, anon;
grant execute on function public.dynamic_pricing_quote_internal(text,numeric,numeric,numeric,numeric,text,numeric,numeric,text) to authenticated, service_role;

create or replace function public.admin_set_zone_service_price_mode_v1(p_zone_id uuid, p_service_key text, p_price_mode text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_old text;
begin
  perform public.admin_assert_environment('production');
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  p_zone_id := public.admin_scope_zone(p_zone_id);
  if p_price_mode not in ('offer','fixed','both') then raise exception 'Modo de precio inválido'; end if;
  select price_mode into v_old from public.zone_service_catalog where zone_id=p_zone_id and service_key=p_service_key for update;
  if not found then raise exception 'El servicio no está configurado en esta zona'; end if;
  update public.zone_service_catalog set price_mode=p_price_mode, updated_at=now() where zone_id=p_zone_id and service_key=p_service_key;
  perform public.admin_log_action('zone_service_price_mode','zone_service',p_zone_id::text||':'||p_service_key,
    jsonb_build_object('zone_id',p_zone_id,'service_key',p_service_key,'from',v_old,'to',p_price_mode));
  return jsonb_build_object('ok',true,'price_mode',p_price_mode);
end; $$;

drop function if exists public.admin_upsert_fare_rule(uuid, text, text, uuid, numeric, numeric, numeric, numeric, numeric, numeric, boolean);
create or replace function public.admin_upsert_fare_rule(
  p_id uuid, p_scope_type text, p_service_key text, p_zone_id uuid,
  p_base_fare numeric, p_per_km numeric, p_per_minute numeric, p_minimum_fare numeric,
  p_surge_multiplier numeric, p_commission_percent numeric, p_active boolean,
  p_price_mode text default 'offer')
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid; v_mode text := coalesce(nullif(trim(p_price_mode),''),'offer');
begin
  perform public.admin_assert_environment('production');
  perform public.is_admin();
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_scope_type not in ('global','service','zone_service') then raise exception 'Scope inválido'; end if;
  if v_mode not in ('offer','fixed') then raise exception 'Modo de precio inválido'; end if;
  if p_scope_type='global' then
    p_service_key := null; p_zone_id := null; v_mode := 'offer';
  elsif p_scope_type='service' then
    p_zone_id := null;
    if trim(coalesce(p_service_key,''))='' then raise exception 'Servicio requerido'; end if;
  else
    if trim(coalesce(p_service_key,''))='' or p_zone_id is null then raise exception 'Servicio y zona requeridos'; end if;
  end if;
  if p_id is null then
    insert into public.fare_rules(scope_type, service_key, zone_id, base_fare, per_km, per_minute,
      minimum_fare, surge_multiplier, commission_percent, active, price_mode)
    values(p_scope_type, nullif(trim(coalesce(p_service_key,'')),''), p_zone_id,
      greatest(coalesce(p_base_fare,0),0), greatest(coalesce(p_per_km,0),0), greatest(coalesce(p_per_minute,0),0),
      greatest(coalesce(p_minimum_fare,0),0), greatest(coalesce(p_surge_multiplier,1),1),
      least(greatest(coalesce(p_commission_percent,0),0),100), coalesce(p_active,true), v_mode)
    returning id into v_id;
  else
    update public.fare_rules
    set scope_type=p_scope_type, service_key=nullif(trim(coalesce(p_service_key,'')),''), zone_id=p_zone_id,
        base_fare=greatest(coalesce(p_base_fare,0),0), per_km=greatest(coalesce(p_per_km,0),0),
        per_minute=greatest(coalesce(p_per_minute,0),0), minimum_fare=greatest(coalesce(p_minimum_fare,0),0),
        surge_multiplier=greatest(coalesce(p_surge_multiplier,1),1),
        commission_percent=least(greatest(coalesce(p_commission_percent,0),0),100),
        active=coalesce(p_active,true), price_mode=v_mode
    where id=p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Tarifa no encontrada'; end if;
  return v_id;
end; $$;
revoke all on function public.admin_upsert_fare_rule(uuid,text,text,uuid,numeric,numeric,numeric,numeric,numeric,numeric,boolean,text) from public, anon;
grant execute on function public.admin_upsert_fare_rule(uuid,text,text,uuid,numeric,numeric,numeric,numeric,numeric,numeric,boolean,text) to authenticated, service_role;

drop function if exists public.effective_fare_rule_at(text, uuid, timestamp with time zone);
create or replace function public.effective_fare_rule_at(
  p_service_key text, p_zone_id uuid, p_at timestamp with time zone, p_price_mode text default 'offer')
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_base jsonb; v_time public.fare_time_rules%rowtype; v_local timestamp;
  v_service text := nullif(btrim(coalesce(p_service_key, '')), '');
  v_mode text := case when p_price_mode = 'fixed' then 'fixed' else 'offer' end;
begin
  select to_jsonb(x) into v_base from (
    select f.id, f.scope_type, f.service_key, f.zone_id, f.base_fare, f.per_km, f.per_minute,
      f.minimum_fare, f.surge_multiplier, f.commission_percent, f.price_mode
    from public.fare_rules f
    where f.active = true
      and f.price_mode in ('offer', v_mode)
      and ((p_zone_id is not null and f.scope_type = 'zone_service' and f.zone_id = p_zone_id and f.service_key = p_service_key)
        or (f.scope_type = 'service' and f.service_key = p_service_key)
        or f.scope_type = 'global')
    order by case when f.scope_type = 'zone_service' then 3 when f.scope_type = 'service' then 2 else 1 end desc,
             (f.price_mode = v_mode) desc
    limit 1
  ) x;
  if p_zone_id is null or v_service is null then return v_base; end if;
  select p_at at time zone coalesce(z.timezone, 'America/La_Paz') into v_local from public.service_zones z where z.id = p_zone_id;
  if v_local is null then return v_base; end if;
  select t.* into v_time from public.fare_time_rules t
  where t.active and t.zone_id = p_zone_id and t.service_key = v_service
    and public.fare_time_rule_matches(t.start_time, t.end_time, t.days_of_week, v_local)
  order by t.created_at desc, t.id limit 1;
  if not found then return v_base; end if;
  return coalesce(v_base, jsonb_build_object('scope_type','zone_service','service_key',v_service,'zone_id',p_zone_id,'surge_multiplier',1,'commission_percent',0))
    || jsonb_build_object('base_fare',v_time.base_fare,'per_km',v_time.per_km,'per_minute',v_time.per_minute,
       'minimum_fare',v_time.minimum_fare,'time_rule_id',v_time.id,'time_rule_name',v_time.name);
end; $$;
revoke all on function public.effective_fare_rule_at(text,uuid,timestamptz,text) from public, anon;
grant execute on function public.effective_fare_rule_at(text,uuid,timestamptz,text) to authenticated, service_role;

drop function if exists public.quote_service_fare_for_location(text, numeric, numeric, numeric, numeric, numeric, numeric);
create or replace function public.quote_service_fare_for_location(
  p_service_key text, p_distance_km numeric, p_duration_minutes numeric, p_lat numeric, p_lng numeric,
  p_dest_lat numeric default null, p_dest_lng numeric default null, p_price_mode text default 'offer')
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_channel text:='production'; v_quote jsonb;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  v_quote:=public.dynamic_pricing_quote_internal(p_service_key,p_distance_km,p_duration_minutes,p_lat,p_lng,v_channel,p_dest_lat,p_dest_lng,p_price_mode);
  v_quote:=public.fare_round_quote(v_quote,v_channel);
  return v_quote || jsonb_build_object('price_mode', coalesce((
    select zs.price_mode from public.zone_service_catalog zs
    where zs.zone_id = nullif(v_quote->>'zone_id','')::uuid and zs.service_key = p_service_key),'offer'));
end $$;
revoke all on function public.quote_service_fare_for_location(text,numeric,numeric,numeric,numeric,numeric,numeric,text) from public, anon;
grant execute on function public.quote_service_fare_for_location(text,numeric,numeric,numeric,numeric,numeric,numeric,text) to authenticated;

create or replace function public.apply_service_fixed_price()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_mode text; v_quote jsonb; v_increment numeric; v_fare numeric;
begin
  if new.service_mode = 'parcel' or new.zone_id is null or new.scheduled_for is not null then
    if new.pricing_mode = 'fixed' then new.pricing_mode := 'offer'; end if;
    return new;
  end if;
  select zs.price_mode into v_mode from public.zone_service_catalog zs where zs.zone_id = new.zone_id and zs.service_key = new.category;
  v_mode := coalesce(v_mode, 'offer');
  -- 'offer': siempre ofertas. 'both': precio fijo solo si el pasajero lo eligió. 'fixed': siempre fijo.
  if v_mode = 'offer' or (v_mode = 'both' and coalesce(new.pricing_mode,'offer') <> 'fixed') then
    new.pricing_mode := 'offer';
    return new;
  end if;
  if new.pickup_latitude is null or new.pickup_longitude is null or coalesce(new.route_distance_km, 0) <= 0 then
    raise exception 'Faltan los datos de la ruta para calcular el precio fijo';
  end if;
  v_quote := public.dynamic_pricing_quote_internal(new.category, new.route_distance_km, coalesce(new.route_duration_minutes, 0),
    new.pickup_latitude, new.pickup_longitude, new.channel, new.destination_latitude, new.destination_longitude, 'fixed');
  v_increment := public.fare_rounding_increment(coalesce(v_quote->>'currency', new.currency), new.channel);
  v_fare := public.fare_round_value(coalesce((v_quote->>'minimum_allowed_fare')::numeric, (v_quote->>'amount')::numeric), v_increment);
  if v_fare is null or v_fare <= 0 then raise exception 'No se pudo calcular el precio fijo'; end if;
  new.proposed_fare := v_fare; new.base_fare := v_fare; new.pricing_mode := 'fixed'; new.dispatch_style := 'sequential';
  new.currency := coalesce(v_quote->>'currency', new.currency); new.fare_rounding_increment := v_increment;
  new.demand_multiplier := coalesce((v_quote->>'demand_multiplier')::numeric, 1);
  new.demand_level := coalesce(v_quote->>'demand_level', 'normal');
  return new;
end; $$;
