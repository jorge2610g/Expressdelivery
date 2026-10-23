-- Server-side enforcement and app-owned debt visibility for administrative
-- wallet adjustments. Negative commission balances remain a separate concept.

create or replace function public.has_pending_admin_adjustment_debt(
  p_user_id uuid,p_country_code text,p_channel text
) returns boolean language sql stable security definer set search_path=''
as $fn$
  select exists(
    select 1 from public.admin_wallet_adjustment_debts d
    where d.user_id=p_user_id and d.country_code=upper(p_country_code)
      and d.channel=public.normalize_runtime_channel(p_channel)
      and d.remaining_amount>0
  );
$fn$;
revoke all on function public.has_pending_admin_adjustment_debt(uuid,text,text)
  from public,anon,authenticated;

create or replace function public.my_admin_wallet_adjustment_debts_v1(
  p_channel text default 'production'
) returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_context jsonb;
  v_country text;
  v_rows jsonb;
  v_total numeric;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if v_channel='preview' and not public.is_active_audit_user(v_uid) then
    raise exception 'Preview requiere una cuenta QA activa';
  end if;
  if v_channel='production' and public.is_active_audit_user(v_uid) then
    raise exception 'Una cuenta QA no puede consultar deudas de Producción';
  end if;
  if public.admin_user_runtime_environment(v_uid) is distinct from v_channel then
    raise exception 'Entorno no autorizado';
  end if;
  v_context:=public.current_operating_context();
  v_country:=v_context->>'country_code';
  select coalesce(jsonb_agg(jsonb_build_object(
      'id',d.id,'amount',d.remaining_amount,'currency_code',d.currency_code,
      'reason',d.reason,'created_at',d.created_at) order by d.created_at),'[]'::jsonb),
      coalesce(sum(d.remaining_amount),0)
    into v_rows,v_total
    from public.admin_wallet_adjustment_debts d
    where d.user_id=v_uid and d.country_code=v_country
      and d.channel=v_channel and d.remaining_amount>0;
  return jsonb_build_object('country_code',v_country,'channel',v_channel,
    'debts',v_rows,'total',v_total);
end;
$fn$;
revoke all on function public.my_admin_wallet_adjustment_debts_v1(text) from public,anon;
grant execute on function public.my_admin_wallet_adjustment_debts_v1(text) to authenticated;

create or replace function public.preview_settle_admin_adjustment_debts_v1()
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare
  v_uid uuid:=auth.uid(); v_context jsonb; v_country text;
  v_currency text; v_total numeric:=0; v_count integer:=0;
begin
  if v_uid is null or not public.is_account_active()
     or not public.is_active_audit_user(v_uid)
     or public.admin_user_runtime_environment(v_uid) is distinct from 'preview' then
    raise exception 'Solo cuentas QA activas pueden simular pagos Preview';
  end if;
  v_context:=public.current_operating_context();
  v_country:=v_context->>'country_code';
  v_currency:=upper(coalesce(v_context->>'currency_code',''));
  select coalesce(sum(remaining_amount),0),count(*) into v_total,v_count
    from public.admin_wallet_adjustment_debts
    where user_id=v_uid and country_code=v_country and channel='preview'
      and remaining_amount>0;
  if v_total<=0 then return jsonb_build_object('paid',true,'simulated',true,'amount',0); end if;
  perform public.apply_admin_adjustment_debt_credit(v_uid,v_country,'preview',v_total);
  perform set_config('app.runtime_channel','preview',true);
  insert into public.wallet_transactions(user_id,amount,type,status,reference,country_code,channel)
    values(v_uid,v_total,'adjustment','completed',
      'Pago simulado de deuda administrativa',v_country,'preview');
  return jsonb_build_object('paid',true,'simulated',true,'amount',v_total,
    'currency_code',v_currency,'debt_count',v_count);
end;
$fn$;
revoke all on function public.preview_settle_admin_adjustment_debts_v1()
  from public,anon;
grant execute on function public.preview_settle_admin_adjustment_debts_v1()
  to authenticated;

-- Include admin adjustment debt in the passenger request guard while keeping
-- the existing cancellation-debt behavior and pickup-zone fallback intact.
create or replace function public.guard_ride_request_cancellation_debt()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=new.passenger_id;
  v_zone uuid;
  v_country text;
  v_currency text;
  v_due numeric:=0;
  v_has_debt boolean:=false;
  v_adjustment_due numeric:=0;
begin
  v_zone:=coalesce(new.zone_id,public.service_zone_id_for_point(
    new.pickup_latitude,new.pickup_longitude));
  select country_code,upper(currency_code) into v_country,v_currency
    from public.service_zones where id=v_zone;

  -- Debt restrictions affect Taxi requests; keep parcel/Delivery flows intact.
  if coalesce(new.service_mode,'taxi')<>'taxi' then return new; end if;

  if v_country is null then
    select exists(select 1 from public.admin_wallet_adjustment_debts d
      where d.user_id=v_uid and d.channel=new.channel and d.remaining_amount>0)
      into v_has_debt;
  else
    select coalesce(sum(d.remaining_amount),0) into v_adjustment_due
      from public.admin_wallet_adjustment_debts d
      where d.user_id=v_uid and d.country_code=v_country
        and d.channel=new.channel and d.remaining_amount>0;
  end if;
  if v_adjustment_due>0 or v_has_debt then
    raise exception 'Tienes un ajuste de billetera pendiente. Regulariza tu saldo desde Pagos y billetera antes de solicitar otro viaje.';
  end if;

  if v_country is not null then
    select coalesce(sum(d.amount),0) into v_due
      from public.cancellation_fee_debts d
      where d.user_id=v_uid and d.country_code=v_country
        and d.channel=new.channel and d.paid_at is null;
  else
    select exists(select 1 from public.cancellation_fee_debts d
      where d.user_id=v_uid and d.channel=new.channel and d.paid_at is null)
      into v_has_debt;
    if v_has_debt then
      raise exception 'Tienes una deuda por cancelación pendiente. Págala desde Pagos y billetera antes de solicitar otro viaje.';
    end if;
  end if;
  if v_due>0 then
    v_currency:=coalesce(v_currency,case v_country when 'CL' then 'CLP' when 'BO' then 'BOB' end,'');
    raise exception 'Tienes una deuda por cancelación pendiente de % %. Págala desde Pagos y billetera antes de solicitar otro viaje.',
      case when v_currency='CLP' then trim(to_char(v_due,'FM999999990'))
        else trim(to_char(v_due,'FM999999990.00')) end,v_currency;
  end if;
  return new;
end $$;
drop trigger if exists ride_requests_guard_cancellation_debt on public.ride_requests;
create trigger ride_requests_guard_cancellation_debt
before insert on public.ride_requests
for each row execute function public.guard_ride_request_cancellation_debt();
revoke all on function public.guard_ride_request_cancellation_debt() from public,anon,authenticated;

-- Existing taxi offer/trip guards also reject drivers with admin debts.
create or replace function public.guard_driver_cancellation_debt()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_mode text; v_country text; v_debt boolean:=false;
begin
  select r.service_mode,z.country_code into v_mode,v_country
    from public.ride_requests r join public.service_zones z on z.id=r.zone_id
    where r.id=new.ride_request_id;
  if exists(select 1 from public.driver_profiles dp
      join public.service_zones z on z.id=dp.zone_id
      where dp.id=new.driver_id and public.has_pending_admin_adjustment_debt(
        new.driver_id,z.country_code,new.channel)) then
    raise exception 'Tienes un ajuste pendiente en tu billetera. Regulariza tu saldo desde Pagos y billetera antes de aceptar viajes.';
  end if;
  if coalesce(v_mode,'taxi')<>'taxi' or v_country is null then return new; end if;
  if exists(select 1 from public.cancellation_fee_debts d
      where d.user_id=new.driver_id and d.channel=new.channel
        and d.country_code=v_country and d.paid_at is null) then
    raise exception 'Tienes una deuda por cancelación pendiente. Págala desde Pagos y billetera antes de aceptar otro viaje.';
  end if;
  return new;
end $$;
drop trigger if exists driver_offers_guard_cancellation_debt on public.driver_offers;
create trigger driver_offers_guard_cancellation_debt before insert on public.driver_offers
for each row execute function public.guard_driver_cancellation_debt();
drop trigger if exists trips_guard_driver_cancellation_debt on public.trips;
create trigger trips_guard_driver_cancellation_debt before insert on public.trips
for each row execute function public.guard_driver_cancellation_debt();
revoke all on function public.guard_driver_cancellation_debt() from public,anon,authenticated;

create or replace function public.guard_driver_online_adjustment_debt()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_country text;
begin
  if new.online_status='online' and old.online_status is distinct from new.online_status then
    select country_code into v_country from public.service_zones where id=new.zone_id;
    if public.has_pending_admin_adjustment_debt(new.id,v_country,
        public.admin_user_runtime_environment(new.id)) then
      raise exception 'Tienes un ajuste pendiente en tu billetera. Regulariza tu saldo antes de conectarte.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists driver_online_adjustment_debt on public.driver_profiles;
create trigger driver_online_adjustment_debt before update of online_status
on public.driver_profiles for each row execute function public.guard_driver_online_adjustment_debt();
revoke all on function public.guard_driver_online_adjustment_debt() from public,anon,authenticated;

-- A driver who is idle is taken offline as soon as the admin debt is created.
-- Active rides/deliveries are allowed to finish; claim guards stop new work.
create or replace function public.force_driver_offline_for_admin_debt()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.remaining_amount>0 and (tg_op='INSERT' or coalesce(old.remaining_amount,0)=0) then
    update public.driver_profiles dp set online_status='offline',updated_at=now()
    where dp.id=new.user_id and dp.online_status='online'
      and not exists(select 1 from public.trips t where t.driver_id=dp.id
        and t.status not in ('completed','cancelled'))
      and not exists(select 1 from public.delivery_requests d where d.courier_id=dp.id
        and d.status not in ('delivered','cancelled'));
  end if;
  return new;
end $$;
drop trigger if exists admin_adjustment_debt_force_offline
  on public.admin_wallet_adjustment_debts;
create trigger admin_adjustment_debt_force_offline
after insert or update of remaining_amount on public.admin_wallet_adjustment_debts
for each row execute function public.force_driver_offline_for_admin_debt();
revoke all on function public.force_driver_offline_for_admin_debt() from public,anon,authenticated;

-- Cover Delivery offers and the accepted courier assignment, not just Taxi.
create or replace function public.guard_delivery_admin_adjustment_debt()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_country text; v_channel text;
begin
  if tg_table_name='delivery_driver_offers' then
    v_user:=new.driver_id; v_channel:=new.channel;
    select country_code into v_country from public.delivery_requests where id=new.delivery_id;
  else
    if new.courier_id is null or old.courier_id is not null then return new; end if;
    v_user:=new.courier_id; v_channel:=new.channel; v_country:=new.country_code;
  end if;
  if v_country is null then
    select z.country_code into v_country from public.driver_profiles dp
      join public.service_zones z on z.id=dp.zone_id where dp.id=v_user;
  end if;
  if public.has_pending_admin_adjustment_debt(v_user,v_country,v_channel) then
    raise exception 'Tienes un ajuste pendiente en tu billetera. Regulariza tu saldo antes de aceptar trabajos.';
  end if;
  return new;
end $$;
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

revoke all on function public.guard_delivery_admin_adjustment_debt() from public,anon,authenticated;

-- Verified wallet credits and admin credits settle outstanding adjustment debt
-- in the same database transaction, so the backend gate clears atomically.
create or replace function public.service_finalize_verified_wallet_gateway(
  p_checkout_id uuid,p_provider_order_id text,
  p_verified_amount numeric,p_verified_currency text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_item public.wallet_gateway_checkouts%rowtype;
  v_topup_id uuid;
  v_debt_paid numeric:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Solo disponible para el servicio de pagos'; end if;
  select * into v_item from public.wallet_gateway_checkouts where id=p_checkout_id for update;
  if not found then raise exception 'Operación no encontrada'; end if;
  if v_item.status='paid' then return jsonb_build_object('paid',true,'already_processed',true); end if;
  if v_item.status<>'pending' then raise exception 'Recarga no pendiente'; end if;
  if v_item.provider_order_id is null or v_item.provider_order_id<>p_provider_order_id
     or v_item.amount<>round(p_verified_amount,2)
     or v_item.currency_code<>upper(trim(p_verified_currency)) then
    raise exception 'No coinciden referencia, monto o moneda verificados';
  end if;
  if v_item.channel<>'production' or public.is_active_audit_user(v_item.user_id)
     or not public.is_production_runtime_user(v_item.user_id) then
    raise exception 'Las cuentas Preview no pueden recibir dinero real';
  end if;
  update public.wallet_gateway_checkouts set status='paid',paid_at=now() where id=v_item.id;
  insert into public.wallet_topup_requests(user_id,amount,currency,country_code,channel,
    method,provider_reference,status,resolved_at)
  values(v_item.user_id,v_item.amount,v_item.currency_code,v_item.country_code,
    v_item.channel,v_item.provider,v_item.provider_order_id,'approved',now())
  returning id into v_topup_id;
  perform set_config('app.runtime_channel','production',true);
  insert into public.wallet_transactions(user_id,amount,type,status,reference,country_code,channel)
  values(v_item.user_id,v_item.amount,'topup','completed',
    'Recarga pasarela:'||v_item.id::text,v_item.country_code,'production');
  v_debt_paid:=public.apply_admin_adjustment_debt_credit(
    v_item.user_id,v_item.country_code,'production',v_item.amount);
  perform public.mirror_legacy_wallet_delta(v_item.user_id,v_item.currency_code,v_item.amount);
  insert into public.notifications(user_id,title,body,type,metadata,channel)
  values(v_item.user_id,'Recarga confirmada',
    'Se confirmó tu pago. El saldo abonado se aplicó primero a cualquier ajuste pendiente.',
    'wallet_topup',jsonb_build_object('checkout_id',v_item.id,
      'country_code',v_item.country_code,'channel','production',
      'admin_adjustment_debt_paid',v_debt_paid),'production');
  return jsonb_build_object('paid',true,'already_processed',false,
    'topup_id',v_topup_id,'checkout_id',v_item.id,
    'admin_adjustment_debt_paid',v_debt_paid);
end $$;
revoke all on function public.service_finalize_verified_wallet_gateway(uuid,text,numeric,text)
  from public,anon,authenticated;
grant execute on function public.service_finalize_verified_wallet_gateway(uuid,text,numeric,text)
  to service_role;
