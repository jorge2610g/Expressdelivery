-- Enforce role-specific, zone-scoped debt thresholds on the server. A missing
-- setting means zero tolerance, preserving the previous any-debt block.
create or replace function public.wallet_debt_limit_status_v1(
  p_user_id uuid,p_zone_id uuid,p_channel text,p_role text
) returns table(debt_total numeric,debt_limit numeric,currency_code text)
language plpgsql stable security definer set search_path=''
as $fn$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_country text;
  v_currency text;
begin
  if p_role not in ('passenger','driver') then
    raise exception 'Rol de billetera inválido';
  end if;
  select upper(z.country_code),upper(z.currency_code)
    into v_country,v_currency from public.service_zones z where z.id=p_zone_id;

  if v_country is null then
    -- A missing operating zone has no currency-safe threshold. Any open debt
    -- for this role/channel remains blocked until a valid zone is known.
    return query select
      case when exists(
        select 1 from public.admin_wallet_adjustment_debts d
        where d.user_id=p_user_id and d.role=p_role and d.channel=v_channel
          and (p_zone_id is null or d.zone_id=p_zone_id)
          and d.remaining_amount>0
        union all
        select 1 from public.cancellation_fee_debts d
        where d.user_id=p_user_id and d.role=p_role and d.channel=v_channel
          and (p_zone_id is null or d.zone_id=p_zone_id)
          and d.paid_at is null
      ) then 0.01::numeric else 0::numeric end,
      0::numeric,
      null::text;
    return;
  end if;

  return query select
    coalesce((select sum(d.remaining_amount)
      from public.admin_wallet_adjustment_debts d
      where d.user_id=p_user_id and d.role=p_role
        and d.zone_id=p_zone_id and d.channel=v_channel
        and d.remaining_amount>0),0)
    + coalesce((select sum(d.amount)
      from public.cancellation_fee_debts d
      where d.user_id=p_user_id and d.role=p_role
        and d.zone_id=p_zone_id and d.channel=v_channel
        and d.paid_at is null),0),
    case when p_role='passenger' then coalesce((
      select l.passenger_limit from public.zone_wallet_debt_limits l
      where l.zone_id=p_zone_id and l.channel=v_channel
    ),0) else coalesce((
      select l.driver_limit from public.zone_wallet_debt_limits l
      where l.zone_id=p_zone_id and l.channel=v_channel
    ),0) end,
    v_currency;
end;
$fn$;
revoke all on function public.wallet_debt_limit_status_v1(uuid,uuid,text,text)
  from public,anon,authenticated;

create or replace function public.wallet_debt_exceeds_limit_v1(
  p_user_id uuid,p_zone_id uuid,p_channel text,p_role text
) returns boolean language sql stable security definer set search_path=''
as $fn$
  select s.debt_total>s.debt_limit
  from public.wallet_debt_limit_status_v1(
    p_user_id,p_zone_id,p_channel,p_role
  ) s;
$fn$;
revoke all on function public.wallet_debt_exceeds_limit_v1(uuid,uuid,text,text)
  from public,anon,authenticated;

create or replace function public.guard_ride_request_cancellation_debt()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_zone uuid;
  v_total numeric;
  v_limit numeric;
  v_currency text;
  v_total_text text;
  v_limit_text text;
begin
  if coalesce(new.service_mode,'taxi')<>'taxi' then return new; end if;
  v_zone:=coalesce(new.zone_id,public.service_zone_id_for_point(
    new.pickup_latitude,new.pickup_longitude));
  select s.debt_total,s.debt_limit,s.currency_code
    into v_total,v_limit,v_currency
    from public.wallet_debt_limit_status_v1(
      new.passenger_id,v_zone,new.channel,'passenger'
    ) s;
  if v_total>v_limit then
    if v_currency is null then
      raise exception 'Tienes deuda pendiente en tu billetera y supera el tope configurado. Revisa Pagos y billetera antes de solicitar otro viaje.';
    end if;
    v_total_text:=case when v_currency='CLP'
      then trim(to_char(v_total,'FM999999999999990'))
      else trim(to_char(v_total,'FM999999999999990.00')) end;
    v_limit_text:=case when v_currency='CLP'
      then trim(to_char(v_limit,'FM999999999999990'))
      else trim(to_char(v_limit,'FM999999999999990.00')) end;
    raise exception 'Tu deuda de billetera es % % y supera el tope permitido de % %. Paga desde Pagos y billetera antes de solicitar otro viaje.',
      v_currency,v_total_text,v_currency,v_limit_text;
  end if;
  return new;
end;
$fn$;
drop trigger if exists ride_requests_guard_cancellation_debt on public.ride_requests;
create trigger ride_requests_guard_cancellation_debt
before insert on public.ride_requests
for each row execute function public.guard_ride_request_cancellation_debt();
revoke all on function public.guard_ride_request_cancellation_debt()
  from public,anon,authenticated;

create or replace function public.guard_driver_cancellation_debt()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_mode text;
  v_zone uuid;
  v_total numeric;
  v_limit numeric;
  v_currency text;
  v_total_text text;
  v_limit_text text;
begin
  select r.service_mode,r.zone_id into v_mode,v_zone
    from public.ride_requests r where r.id=new.ride_request_id;
  if coalesce(v_mode,'taxi')<>'taxi' then return new; end if;
  if v_zone is null then
    select dp.zone_id into v_zone from public.driver_profiles dp
      where dp.id=new.driver_id;
  end if;
  select s.debt_total,s.debt_limit,s.currency_code
    into v_total,v_limit,v_currency
    from public.wallet_debt_limit_status_v1(
      new.driver_id,v_zone,new.channel,'driver'
    ) s;
  if v_total>v_limit then
    if v_currency is null then
      raise exception 'Tienes deuda pendiente en tu billetera y supera el tope configurado. Revisa Pagos y billetera antes de aceptar viajes.';
    end if;
    v_total_text:=case when v_currency='CLP'
      then trim(to_char(v_total,'FM999999999999990'))
      else trim(to_char(v_total,'FM999999999999990.00')) end;
    v_limit_text:=case when v_currency='CLP'
      then trim(to_char(v_limit,'FM999999999999990'))
      else trim(to_char(v_limit,'FM999999999999990.00')) end;
    raise exception 'Tu deuda de billetera es % % y supera el tope permitido de % %. Paga desde Pagos y billetera antes de aceptar viajes.',
      v_currency,v_total_text,v_currency,v_limit_text;
  end if;
  return new;
end;
$fn$;
drop trigger if exists driver_offers_guard_cancellation_debt on public.driver_offers;
create trigger driver_offers_guard_cancellation_debt
before insert on public.driver_offers
for each row execute function public.guard_driver_cancellation_debt();
drop trigger if exists trips_guard_driver_cancellation_debt on public.trips;
create trigger trips_guard_driver_cancellation_debt
before insert on public.trips
for each row execute function public.guard_driver_cancellation_debt();
revoke all on function public.guard_driver_cancellation_debt()
  from public,anon,authenticated;

create or replace function public.guard_driver_online_adjustment_debt()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_total numeric;
  v_limit numeric;
  v_currency text;
begin
  if new.online_status='online'
     and old.online_status is distinct from new.online_status then
    select s.debt_total,s.debt_limit,s.currency_code
      into v_total,v_limit,v_currency
      from public.wallet_debt_limit_status_v1(
        new.id,new.zone_id,public.admin_user_runtime_environment(new.id),'driver'
      ) s;
    if v_total>v_limit then
      raise exception 'Tu deuda pendiente supera el tope configurado. Págala desde Pagos y billetera antes de conectarte.';
    end if;
  end if;
  return new;
end;
$fn$;
drop trigger if exists driver_online_adjustment_debt on public.driver_profiles;
create trigger driver_online_adjustment_debt
before update of online_status on public.driver_profiles
for each row execute function public.guard_driver_online_adjustment_debt();
revoke all on function public.guard_driver_online_adjustment_debt()
  from public,anon,authenticated;

create or replace function public.force_driver_offline_for_wallet_debt()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_user uuid;
  v_zone uuid;
  v_channel text;
begin
  if tg_table_name='admin_wallet_adjustment_debts' then
    v_user:=new.user_id; v_zone:=new.zone_id; v_channel:=new.channel;
  else
    if new.role<>'driver' or new.paid_at is not null then return new; end if;
    v_user:=new.user_id; v_zone:=new.zone_id; v_channel:=new.channel;
  end if;
  if v_zone is null then
    select dp.zone_id into v_zone from public.driver_profiles dp
      where dp.id=v_user;
  end if;
  if public.wallet_debt_exceeds_limit_v1(v_user,v_zone,v_channel,'driver') then
    update public.driver_profiles dp set online_status='offline',updated_at=now()
    where dp.id=v_user and dp.online_status='online'
      and not exists(select 1 from public.trips t where t.driver_id=dp.id
        and t.status not in ('completed','cancelled'))
      and not exists(select 1 from public.delivery_requests d where d.courier_id=dp.id
        and d.status not in ('delivered','cancelled'));
  end if;
  return new;
end;
$fn$;
drop trigger if exists admin_adjustment_debt_force_offline
  on public.admin_wallet_adjustment_debts;
create trigger admin_adjustment_debt_force_offline
after insert or update of remaining_amount on public.admin_wallet_adjustment_debts
for each row execute function public.force_driver_offline_for_wallet_debt();
drop trigger if exists cancellation_debt_force_driver_offline
  on public.cancellation_fee_debts;
create trigger cancellation_debt_force_driver_offline
after insert or update of paid_at on public.cancellation_fee_debts
for each row execute function public.force_driver_offline_for_wallet_debt();
revoke all on function public.force_driver_offline_for_wallet_debt()
  from public,anon,authenticated;

create or replace function public.guard_delivery_admin_adjustment_debt()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare
  v_user uuid;
  v_zone uuid;
  v_channel text;
  v_country text;
  v_over_limit boolean;
begin
  if tg_table_name='delivery_driver_offers' then
    v_user:=new.driver_id; v_channel:=new.channel;
    select d.country_code into v_country from public.delivery_requests d
      where d.id=new.delivery_id;
  else
    if new.courier_id is null or old.courier_id is not null then return new; end if;
    v_user:=new.courier_id; v_channel:=new.channel; v_country:=new.country_code;
  end if;
  select dp.zone_id into v_zone from public.driver_profiles dp
    join public.service_zones z on z.id=dp.zone_id
    where dp.id=v_user and (v_country is null or z.country_code=v_country);
  v_over_limit:=public.wallet_debt_exceeds_limit_v1(
    v_user,v_zone,v_channel,'driver'
  );
  if v_over_limit then
    raise exception 'Tu deuda pendiente supera el tope configurado. Págala desde Pagos y billetera antes de aceptar trabajos.';
  end if;
  return new;
end;
$fn$;
drop trigger if exists delivery_offers_guard_admin_adjustment_debt
  on public.delivery_driver_offers;
create trigger delivery_offers_guard_admin_adjustment_debt
before insert on public.delivery_driver_offers
for each row execute function public.guard_delivery_admin_adjustment_debt();
drop trigger if exists delivery_claim_guard_admin_adjustment_debt
  on public.delivery_requests;
create trigger delivery_claim_guard_admin_adjustment_debt
before update of courier_id on public.delivery_requests
for each row execute function public.guard_delivery_admin_adjustment_debt();
revoke all on function public.guard_delivery_admin_adjustment_debt()
  from public,anon,authenticated;
