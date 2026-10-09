-- Additive shared business configuration: staircase pricing. No existing
-- tariff changes until a zone/service is explicitly configured by admin.
create table if not exists public.zone_distance_fare_steps (
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  service_key text not null,
  up_to_km numeric(9,2) not null check (up_to_km>0),
  fare numeric(12,2) not null check (fare>0),
  primary key(zone_id,service_key,up_to_km)
);
create index if not exists zone_distance_fare_steps_lookup
  on public.zone_distance_fare_steps(zone_id,service_key,up_to_km);
alter table public.zone_distance_fare_steps enable row level security;
revoke all on public.zone_distance_fare_steps from public, anon, authenticated;

create or replace function public.admin_distance_fare_steps_get(
  p_zone_id uuid, p_service_key text, p_channel text default 'production'
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
begin
 if auth.uid() is null or not public.is_admin()
  or p_channel not in ('preview','production')
  or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso no autorizado a tarifas';
 end if;
 return jsonb_build_object(
  'zone_id',p_zone_id,'service_key',p_service_key,
  'currency',(select currency_code from public.service_zones where id=p_zone_id),
  'steps',(select coalesce(jsonb_agg(jsonb_build_object(
     'up_to_km',up_to_km,'fare',fare) order by up_to_km),'[]'::jsonb)
   from public.zone_distance_fare_steps
   where zone_id=p_zone_id and service_key=p_service_key)
 );
end $$;

create or replace function public.admin_distance_fare_steps_replace(
  p_zone_id uuid,p_service_key text,p_steps jsonb,
  p_channel text default 'production'
) returns jsonb language plpgsql security definer
set search_path=public as $$
declare v_step jsonb; v_km numeric; v_fare numeric;
  v_prev_km numeric:=0; v_prev_fare numeric:=0;
begin
 if auth.uid() is null or not public.is_admin()
  or p_channel not in ('preview','production')
  or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso no autorizado a tarifas';
 end if;
 if not exists (select 1 from public.service_zones z where z.id=p_zone_id)
  or not exists(select 1 from public.zone_service_catalog z
    where z.zone_id=p_zone_id and z.service_key=p_service_key) then
    raise exception 'La zona o servicio no existe';
 end if;
 if p_steps is null or jsonb_typeof(p_steps)<>'array'
  or jsonb_array_length(p_steps)>100 then
    raise exception 'Ingresa una lista de hasta 100 escalones';
 end if;
 -- Validate before deleting old tiers, reject duplicate or decreasing levels.
 for v_step in select value from jsonb_array_elements(p_steps) loop
   if jsonb_typeof(v_step)<>'object'
      or (v_step->>'up_to_km') is null or (v_step->>'fare') is null then
     raise exception 'Escalón inválido';
   end if;
   begin
     v_km:=(v_step->>'up_to_km')::numeric;
     v_fare:=(v_step->>'fare')::numeric;
   exception when others then
     raise exception 'Distancia y tarifa deben ser numéricas';
   end;
   if v_km<=v_prev_km or v_fare<=0 or v_fare<v_prev_fare
     or v_km>10000 or v_fare>100000000 then
     raise exception 'Las distancias deben subir y el precio no puede bajar';
   end if;
   v_prev_km:=v_km; v_prev_fare:=v_fare;
 end loop;
 delete from public.zone_distance_fare_steps
   where zone_id=p_zone_id and service_key=p_service_key;
 for v_step in select value from jsonb_array_elements(p_steps) loop
   insert into public.zone_distance_fare_steps(zone_id,service_key,up_to_km,fare)
     values(p_zone_id,p_service_key,(v_step->>'up_to_km')::numeric,
       (v_step->>'fare')::numeric);
 end loop;
 return public.admin_distance_fare_steps_get(p_zone_id,p_service_key,p_channel);
end $$;
revoke all on function public.admin_distance_fare_steps_get(uuid,text,text)
  from public,anon;
revoke all on function public.admin_distance_fare_steps_replace(uuid,text,jsonb,text)
  from public,anon;
grant execute on function public.admin_distance_fare_steps_get(uuid,text,text)
  to authenticated;
grant execute on function public.admin_distance_fare_steps_replace(uuid,text,jsonb,text)
  to authenticated;

-- Preserve existing fare model, zone validation and currency; inject only
-- optional tariff tiers into the central base quote used by dynamic pricing.
CREATE OR REPLACE FUNCTION public.quote_service_fare_for_location_base(p_service_key text, p_distance_km numeric, p_duration_minutes numeric, p_lat numeric, p_lng numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_tier_price numeric;
  v_tier_distance numeric;
  v_last_distance numeric;
  v_last_fare numeric;
  v_prev_distance numeric;
  v_prev_fare numeric;
  v_tier_applied boolean := false;
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

  -- Explicit per-zone, per-service staircase price overrides legacy linear base.
  -- Empty tier lists have no effect on any existing journey pricing.
  select t.up_to_km,t.fare into v_tier_distance,v_tier_price
    from public.zone_distance_fare_steps t
    where t.zone_id=v_zone_id and t.service_key=p_service_key
      and t.up_to_km >= greatest(coalesce(p_distance_km,0),0)
    order by t.up_to_km limit 1;

  if v_tier_price is null then
    select t.up_to_km,t.fare into v_last_distance,v_last_fare
      from public.zone_distance_fare_steps t
      where t.zone_id=v_zone_id and t.service_key=p_service_key
      order by t.up_to_km desc limit 1;
    if v_last_fare is not null then
      select t.up_to_km,t.fare into v_prev_distance,v_prev_fare
        from public.zone_distance_fare_steps t
        where t.zone_id=v_zone_id and t.service_key=p_service_key
          and t.up_to_km < v_last_distance
        order by t.up_to_km desc limit 1;
      -- Beyond the last configured bracket: extend the final incremental
      -- step rather than incorrectly reverting to the old legacy price.
      v_tier_distance := v_last_distance;
      v_tier_price := v_last_fare +
        ceil(greatest(coalesce(p_distance_km,0)-v_last_distance,0))
        * case when v_prev_distance is not null then
          greatest(0,(v_last_fare-v_prev_fare)/
            nullif(v_last_distance-v_prev_distance,0))
          else 0 end;
    end if;
  end if;
  if v_tier_price is not null then
    v_amount := round(v_tier_price,2);
    v_minimum := v_amount;
    v_tier_applied := true;
  end if;

  return jsonb_build_object(
    'pricing_mode',case when v_tier_applied then 'distance_steps' else 'legacy' end,
    'distance_step_up_to_km',v_tier_distance,
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
$function$

