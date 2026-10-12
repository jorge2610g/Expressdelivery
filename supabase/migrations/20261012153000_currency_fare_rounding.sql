-- Express currency rounding: authoritative fares, not presentation-only.
-- Compatibility: no existing amount changes until an administrator chooses an increment.
-- Runtime remains account-scoped; Preview and Production have independent settings.
begin;
create table if not exists public.fare_rounding_currency_policies (
  channel text not null check (channel in ('preview','production')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  increment numeric(4,2) not null check (increment in (0.01,0.50,1.00)),
  updated_at timestamptz not null default now(),
  primary key (channel,currency)
);
alter table public.fare_rounding_currency_policies enable row level security;
revoke all on public.fare_rounding_currency_policies from public,anon,authenticated;

create or replace function public.fare_rounding_increment(
  p_currency text, p_channel text
) returns numeric language sql stable security definer set search_path=public as $$
  select coalesce((
    select p.increment from public.fare_rounding_currency_policies p
    where p.channel=case when p_channel='preview' then 'preview' else 'production' end
      and p.currency=upper(trim(coalesce(p_currency,'BOB')))
  ),0.01)::numeric;
$$;
revoke all on function public.fare_rounding_increment(text,text) from public,anon,authenticated;

create or replace function public.fare_round_value(
  p_amount numeric,p_increment numeric
) returns numeric language sql immutable set search_path=public as $$
  select case when p_amount is null then null
    else round(round(p_amount/coalesce(nullif(p_increment,0),0.01))
      *coalesce(nullif(p_increment,0),0.01),2)
    end;
$$;
revoke all on function public.fare_round_value(numeric,numeric) from public,anon,authenticated;

-- All externally visible quote fields use exactly the same persisted granularity.
create or replace function public.fare_round_quote(
  p_quote jsonb,p_channel text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
 v_result jsonb:=p_quote;
 v_step numeric;
 v_key text;
begin
 if p_quote is null then return null; end if;
 v_step:=public.fare_rounding_increment(p_quote->>'currency',p_channel);
 foreach v_key in array array[
   'amount','recommended_fare','minimum_allowed_fare','base_amount','minimum_fare'
 ] loop
   if v_result ? v_key and v_result->>v_key is not null then
     v_result:=jsonb_set(v_result,array[v_key],
       to_jsonb(public.fare_round_value((v_result->>v_key)::numeric,v_step)));
   end if;
 end loop;
 return v_result||jsonb_build_object('fare_rounding_increment',v_step);
end $$;
revoke all on function public.fare_round_quote(jsonb,text) from public,anon,authenticated;

create or replace function public.admin_fare_rounding_get(
  p_currency text,p_channel text default 'production'
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
 v_currency text:=upper(trim(coalesce(p_currency,'')));
 v_increment numeric;
 v_explicit boolean;
begin
 if auth.uid() is null or not public.is_admin()
    or p_channel not in ('preview','production')
    or not public.admin_environment_allowed(p_channel) then
   raise exception 'Acceso no autorizado a redondeo de tarifas';
 end if;
 if v_currency !~ '^[A-Z]{3}$' then
   raise exception 'Código de moneda no válido';
 end if;
 select increment into v_increment
   from public.fare_rounding_currency_policies
   where channel=p_channel and currency=v_currency;
 v_explicit:=found;
 return jsonb_build_object(
   'currency',v_currency,'channel',p_channel,
   'increment',coalesce(v_increment,0.01),
   'configured',v_explicit
 );
end $$;

create or replace function public.admin_fare_rounding_set(
 p_currency text,p_increment numeric,p_channel text default 'production'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_currency text:=upper(trim(coalesce(p_currency,'')));
begin
 if auth.uid() is null or not public.is_admin()
   or p_channel not in ('preview','production')
   or not public.admin_environment_allowed(p_channel)
   or coalesce(public.admin_access_context()->>'role','') <> 'super_admin' then
   raise exception 'Solo un superadministrador del entorno puede modificar el redondeo';
 end if;
 if v_currency !~ '^[A-Z]{3}$' or p_increment is null
    or p_increment not in (0.01,0.50,1.00) then
   raise exception 'Moneda o incremento no válido';
 end if;
 insert into public.fare_rounding_currency_policies(
   channel,currency,increment,updated_at
 ) values (p_channel,v_currency,p_increment,now())
 on conflict(channel,currency) do update
   set increment=excluded.increment,updated_at=now();
 return public.admin_fare_rounding_get(v_currency,p_channel);
end $$;
revoke all on function public.admin_fare_rounding_get(text,text) from public,anon;
revoke all on function public.admin_fare_rounding_set(text,numeric,text) from public,anon;
grant execute on function public.admin_fare_rounding_get(text,text) to authenticated;
grant execute on function public.admin_fare_rounding_set(text,numeric,text) to authenticated;

-- Both web and Android quote clients receive the same rounded server amount.
create or replace function public.quote_service_fare_for_location(
  p_service_key text,p_distance_km numeric,p_duration_minutes numeric,
  p_lat numeric,p_lng numeric
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
 v_channel text:='production';
 v_quote jsonb;
begin
 if auth.uid() is null then raise exception 'No autenticado'; end if;
 -- Account binding, not a URL or a hardcoded app mode, selects Preview/Production.
 select b.environment into v_channel
   from public.account_runtime_bindings b where b.user_id=auth.uid();
 if v_channel is null then
   v_channel:=case when coalesce(public.is_active_audit_user(auth.uid()),false)
     then 'preview' else 'production' end;
 end if;
 v_quote:=public.dynamic_pricing_quote_internal(
   p_service_key,p_distance_km,p_duration_minutes,p_lat,p_lng,v_channel
 );
 return public.fare_round_quote(v_quote,v_channel);
end $$;
revoke all on function public.quote_service_fare_for_location(text,numeric,numeric,numeric,numeric)
 from public,anon;
grant execute on function public.quote_service_fare_for_location(text,numeric,numeric,numeric,numeric)
 to authenticated;

create or replace function public.dynamic_pricing_quote(
 p_service_key text,p_distance_km numeric,p_duration_minutes numeric,
 p_pickup_lat numeric,p_pickup_lng numeric,p_preview boolean default false
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_channel text:=case when p_preview then 'preview' else 'production' end;
begin
 if auth.uid() is null then raise exception 'No autenticado'; end if;
 return public.fare_round_quote(public.dynamic_pricing_quote_internal(
  p_service_key,p_distance_km,p_duration_minutes,p_pickup_lat,p_pickup_lng,
  v_channel
 ),v_channel);
end $$;
revoke all on function public.dynamic_pricing_quote(text,numeric,numeric,numeric,numeric,boolean)
 from public,anon;
grant execute on function public.dynamic_pricing_quote(text,numeric,numeric,numeric,numeric,boolean)
 to authenticated;

-- Persist the increment on each new request, preventing mid-trip re-pricing.
alter table public.ride_requests
  add column if not exists fare_rounding_increment numeric(4,2);
alter table public.delivery_requests
  add column if not exists fare_rounding_increment numeric(4,2);

-- Existing requests keep legacy cent precision when subsequently edited.
create or replace function public.enforce_ride_recommended_fare_floor()
returns trigger language plpgsql security definer set search_path=public as $$
declare
 v_quote jsonb;
 v_floor numeric;
 v_currency text;
 v_increment numeric;
begin
 v_currency:=coalesce(
   (select currency_code from public.service_zones where id=new.zone_id),
   new.currency,'BOB'
 );
 if tg_op='INSERT' then
   v_increment:=public.fare_rounding_increment(v_currency,new.channel);
 else
   v_increment:=coalesce(old.fare_rounding_increment,0.01);
 end if;
 new.fare_rounding_increment:=v_increment;
 new.proposed_fare:=public.fare_round_value(new.proposed_fare,v_increment);
 if new.base_fare is not null then
   new.base_fare:=public.fare_round_value(new.base_fare,v_increment);
 end if;
 if coalesce(new.pricing_mode,'offer')='fixed' then
   new.base_fare:=new.proposed_fare;
   return new;
 end if;
 if new.pickup_latitude is null or new.pickup_longitude is null then
   return new;
 end if;
 v_quote:=public.dynamic_pricing_quote_internal(
   new.category,
   coalesce(new.route_distance_km,0),
   coalesce(new.route_duration_minutes,0),
   new.pickup_latitude,new.pickup_longitude,new.channel
 );
 v_currency:=coalesce(v_quote->>'currency',v_currency);
 v_floor:=public.fare_round_value(
   coalesce((v_quote->>'minimum_allowed_fare')::numeric,0),v_increment
 );
 if new.proposed_fare is null or new.proposed_fare<v_floor then
   raise exception 'La tarifa mínima recomendada actual es % %',
     trim(to_char(v_floor,'FM999999990.00')),v_currency;
 end if;
 new.base_fare:=public.fare_round_value(
   coalesce((v_quote->>'base_amount')::numeric,new.base_fare),v_increment
 );
 new.demand_multiplier:=coalesce((v_quote->>'demand_multiplier')::numeric,1);
 new.demand_level:=coalesce(v_quote->>'demand_level','normal');
 new.demand_requests:=coalesce((v_quote->>'demand_requests')::integer,0);
 new.demand_drivers:=coalesce((v_quote->>'demand_drivers')::integer,0);
 new.demand_sector_key:=v_quote->>'demand_sector_key';
 new.currency:=v_currency;
 return new;
end $$;
revoke all on function public.enforce_ride_recommended_fare_floor()
 from public,anon,authenticated;

-- Driver offers, accepted trips and deliveries store the same payable value.
create or replace function public.round_driver_offer_fare()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_increment numeric;
begin
 select coalesce(r.fare_rounding_increment,0.01)
   into v_increment from public.ride_requests r
   where r.id=new.ride_request_id;
 new.proposed_fare:=public.fare_round_value(
   new.proposed_fare,coalesce(v_increment,0.01));
 return new;
end $$;
drop trigger if exists zzz_round_driver_offer_fare on public.driver_offers;
create trigger zzz_round_driver_offer_fare
 before insert or update of proposed_fare on public.driver_offers
 for each row execute function public.round_driver_offer_fare();

create or replace function public.round_trip_final_fare()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_increment numeric;
begin
 if tg_op='UPDATE' and old.status='completed' then
   return new;
 end if;
 select coalesce(r.fare_rounding_increment,0.01)
   into v_increment from public.ride_requests r
   where r.id=new.ride_request_id;
 new.final_fare:=public.fare_round_value(
   new.final_fare,coalesce(v_increment,0.01));
 return new;
end $$;
drop trigger if exists zzz_round_trip_final_fare on public.trips;
create trigger zzz_round_trip_final_fare
 before insert or update of final_fare on public.trips
 for each row execute function public.round_trip_final_fare();

create or replace function public.round_delivery_proposed_fare()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_increment numeric;
begin
 if tg_op='UPDATE' and old.status='completed' then
   return new;
 end if;
 if tg_op='INSERT' then
   v_increment:=public.fare_rounding_increment(new.currency,new.channel);
 else
   v_increment:=coalesce(old.fare_rounding_increment,0.01);
 end if;
 new.fare_rounding_increment:=v_increment;
 new.proposed_fare:=public.fare_round_value(new.proposed_fare,v_increment);
 return new;
end $$;
drop trigger if exists zzz_round_delivery_proposed_fare on public.delivery_requests;
create trigger zzz_round_delivery_proposed_fare
 before insert or update of proposed_fare on public.delivery_requests
 for each row execute function public.round_delivery_proposed_fare();
commit;
