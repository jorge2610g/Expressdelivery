-- Zone-scoped cancellation fees. All zones start disabled; no existing zone is
-- seeded or charged by this migration. Preview and Production use separate rows.
create table if not exists public.zone_cancellation_fee_rules (
  channel text not null check (channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  enabled boolean not null default false,
  passenger_fee numeric(14,2) not null default 0 check (passenger_fee >= 0),
  driver_fee numeric(14,2) not null default 0 check (driver_fee >= 0),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key(channel,zone_id)
);
revoke all on public.zone_cancellation_fee_rules from public,anon,authenticated;

create table if not exists public.cancellation_fee_debts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  trip_id uuid not null references public.trips(id),
  zone_id uuid not null references public.service_zones(id),
  channel text not null check (channel in ('preview','production')),
  country_code text not null,
  currency_code text not null,
  role text not null check (role in ('passenger','driver')),
  amount numeric(14,2) not null check (amount >= 1 and amount <= 5000),
  reason text not null,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  payment_checkout_id uuid,
  unique(trip_id,user_id)
);
create index if not exists cancellation_fee_debts_open_user_idx
  on public.cancellation_fee_debts(user_id,channel,country_code,created_at)
  where paid_at is null;
alter table public.cancellation_fee_debts enable row level security;
revoke all on public.cancellation_fee_debts from public,anon,authenticated;
grant select on public.cancellation_fee_debts to authenticated;
drop policy if exists cancellation_fee_debts_owner_read
  on public.cancellation_fee_debts;
create policy cancellation_fee_debts_owner_read
  on public.cancellation_fee_debts for select to authenticated
  using (
    user_id=auth.uid() and (
      (channel='preview' and public.is_active_audit_user(auth.uid())) or
      (channel='production' and public.is_production_runtime_user(auth.uid())
        and not public.is_active_audit_user(auth.uid()))
    )
  );

create or replace function public.admin_zone_cancellation_fee_get(
  p_zone_id uuid, p_channel text default 'production'
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare
  v_context jsonb;
  v_currency text;
  v_rule public.zone_cancellation_fee_rules%rowtype;
begin
  if auth.uid() is null or not public.is_admin()
     or p_channel not in ('preview','production')
     or not public.admin_environment_allowed(p_channel) then
    raise exception 'Entorno administrativo no autorizado';
  end if;
  v_context:=public.admin_access_context();
  if v_context->>'zone_id' is not null and
     (v_context->>'zone_id')::uuid is distinct from p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  select currency_code into v_currency from public.service_zones where id=p_zone_id;
  if v_currency is null then raise exception 'Zona no encontrada'; end if;
  select * into v_rule from public.zone_cancellation_fee_rules
    where zone_id=p_zone_id and channel=p_channel;
  return jsonb_build_object(
    'zone_id',p_zone_id,'channel',p_channel,'currency',v_currency,
    'enabled',coalesce(v_rule.enabled,false),
    'passenger_fee',coalesce(v_rule.passenger_fee,0),
    'driver_fee',coalesce(v_rule.driver_fee,0),
    'configured',found
  );
end $$;

create or replace function public.admin_zone_cancellation_fee_set(
  p_zone_id uuid, p_enabled boolean, p_passenger_fee numeric,
  p_driver_fee numeric, p_channel text default 'production'
) returns jsonb language plpgsql security definer
set search_path=public as $$
declare
  v_context jsonb;
  v_currency text;
  v_increment numeric;
begin
  if auth.uid() is null or not public.is_admin()
     or p_channel not in ('preview','production')
     or not public.admin_environment_allowed(p_channel) then
    raise exception 'Entorno administrativo no autorizado';
  end if;
  v_context:=public.admin_access_context();
  if coalesce(v_context->>'role','') <> 'super_admin' then
    raise exception 'Solo un superadministrador puede configurar estos cobros';
  end if;
  if v_context->>'zone_id' is not null and
     (v_context->>'zone_id')::uuid is distinct from p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  select currency_code into v_currency from public.service_zones where id=p_zone_id;
  if v_currency is null then raise exception 'Zona no encontrada'; end if;
  if p_enabled is null or p_passenger_fee is null or p_driver_fee is null
     or p_passenger_fee<0 or p_driver_fee<0
     or p_passenger_fee>5000 or p_driver_fee>5000
     or (p_enabled and p_passenger_fee>0 and p_passenger_fee<1)
     or (p_enabled and p_driver_fee>0 and p_driver_fee<1) then
    raise exception 'Estado o monto de cancelación inválido';
  end if;
  v_increment:=case when upper(v_currency)='CLP' then 1 else 0.01 end;
  if mod(p_passenger_fee,v_increment)<>0 or mod(p_driver_fee,v_increment)<>0 then
    raise exception 'El monto debe respetar la unidad mínima de %',v_currency;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'zone-cancellation-fee:'||p_channel||':'||p_zone_id::text,0));
  insert into public.zone_cancellation_fee_rules(
    channel,zone_id,enabled,passenger_fee,driver_fee,updated_by,updated_at
  ) values(p_channel,p_zone_id,p_enabled,p_passenger_fee,p_driver_fee,auth.uid(),now())
  on conflict(channel,zone_id) do update set
    enabled=excluded.enabled,passenger_fee=excluded.passenger_fee,
    driver_fee=excluded.driver_fee,updated_by=excluded.updated_by,
    updated_at=now();
  return public.admin_zone_cancellation_fee_get(p_zone_id,p_channel);
end $$;

create or replace function public.my_cancellation_fee_debts_v1(
  p_channel text default 'production'
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_country text:=(public.current_operating_context()->>'country_code');
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if v_channel='preview' and not public.is_active_audit_user(v_uid) then
    raise exception 'Preview requiere una cuenta QA activa';
  end if;
  if v_channel='production' and public.is_active_audit_user(v_uid) then
    raise exception 'Una cuenta QA no puede consultar deudas de Producción';
  end if;
  return jsonb_build_object(
    'country_code',v_country,
    'debts',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at)
      from public.cancellation_fee_debts d
      where d.user_id=v_uid and d.channel=v_channel
        and d.country_code=v_country and d.paid_at is null),'[]'::jsonb),
    'total',coalesce((select sum(d.amount) from public.cancellation_fee_debts d
      where d.user_id=v_uid and d.channel=v_channel
        and d.country_code=v_country and d.paid_at is null),0)
  );
end $$;

-- QA accounts can clear Preview-only debts to continue flow tests. This never
-- creates a checkout, touches Production, or represents a real payment.
create or replace function public.preview_settle_cancellation_debts_v1()
returns jsonb language plpgsql security definer
set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_country text:=(public.current_operating_context()->>'country_code');
  v_total numeric:=0;
  v_count integer:=0;
begin
  if v_uid is null or not public.is_account_active()
     or not public.is_active_audit_user(v_uid) then
    raise exception 'Solo cuentas QA activas pueden simular pagos Preview';
  end if;
  select coalesce(sum(d.amount),0) into v_total
    from public.cancellation_fee_debts d
    where d.user_id=v_uid and d.channel='preview'
      and d.country_code=v_country and d.paid_at is null;
  update public.cancellation_fee_debts d
    set paid_at=now()
    where d.user_id=v_uid and d.channel='preview'
      and d.country_code=v_country and d.paid_at is null;
  get diagnostics v_count=row_count;
  return jsonb_build_object('paid',true,'simulated',true,
    'debt_count',v_count,'total',coalesce(v_total,0),'country_code',v_country);
end $$;

create or replace function public.cancellation_fee_quote_v1(
  p_trip_id uuid, p_channel text default 'production'
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_trip public.trips%rowtype;
  v_zone uuid;
  v_country text;
  v_currency text;
  v_role text;
  v_mode text;
  v_amount numeric:=0;
  v_assigned_at timestamptz;
  v_waiting_at timestamptz;
  v_grace_seconds integer:=300;
  v_elapsed integer:=0;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if (v_channel='preview' and not public.is_active_audit_user(v_uid)) or
     (v_channel='production' and public.is_active_audit_user(v_uid)) then
    raise exception 'El viaje pertenece a otro entorno';
  end if;
  select t.* into v_trip from public.trips t
    where t.id=p_trip_id and t.channel=v_channel;
  if not found or v_uid not in (v_trip.passenger_id,v_trip.driver_id) then
    raise exception 'Viaje no disponible';
  end if;
  select r.zone_id,r.country_code,r.currency,r.service_mode
    into v_zone,v_country,v_currency,v_mode
    from public.ride_requests r where r.id=v_trip.ride_request_id and r.channel=v_channel;
  if coalesce(v_mode,'taxi')<>'taxi' then
    return jsonb_build_object('trip_id',p_trip_id,'role',
      case when v_uid=v_trip.passenger_id then 'passenger' else 'driver' end,
      'fee',0,'currency',v_currency,'channel',v_channel,
      'grace_seconds',0,'fee_enabled',false);
  end if;
  select h.created_at into v_assigned_at from public.trip_status_history h
    where h.trip_id=p_trip_id and h.status='driver_assigned'
    order by h.created_at asc limit 1;
  v_assigned_at:=coalesce(v_assigned_at,v_trip.created_at);
  if v_uid=v_trip.passenger_id then v_role:='passenger';
  else v_role:='driver'; end if;
  select h.created_at into v_waiting_at from public.trip_status_history h
    where h.trip_id=p_trip_id and h.status='driver_waiting'
    order by h.created_at desc limit 1;
  if v_role='passenger' then
    if v_trip.status='driver_waiting' and v_waiting_at is not null then
      v_elapsed:=greatest(0,floor(extract(epoch from(now()-v_waiting_at)))::integer);
      if v_elapsed<300 then
        select case when enabled then passenger_fee else 0 end into v_amount
          from public.zone_cancellation_fee_rules
          where zone_id=v_zone and channel=v_channel;
      end if;
    elsif v_trip.status in ('driver_assigned','driver_arriving') then
      v_elapsed:=greatest(0,floor(extract(epoch from(now()-v_assigned_at)))::integer);
      if v_elapsed<300 then
        select case when enabled then passenger_fee else 0 end into v_amount
          from public.zone_cancellation_fee_rules
          where zone_id=v_zone and channel=v_channel;
      end if;
    end if;
    v_amount:=coalesce(v_amount,0);
  elsif v_trip.status in ('driver_assigned','driver_arriving') then
    select case when enabled then driver_fee else 0 end into v_amount
      from public.zone_cancellation_fee_rules
      where zone_id=v_zone and channel=v_channel;
    v_amount:=coalesce(v_amount,0);
  elsif v_trip.status='driver_waiting' and v_waiting_at is not null
        and now()<v_waiting_at+interval '5 minutes' then
    select case when enabled then driver_fee else 0 end into v_amount
      from public.zone_cancellation_fee_rules
      where zone_id=v_zone and channel=v_channel;
    v_amount:=coalesce(v_amount,0);
  end if;
  return jsonb_build_object(
    'trip_id',p_trip_id,'role',v_role,'fee',coalesce(v_amount,0),
    'currency',v_currency,'channel',v_channel,
    'grace_seconds',case
      when v_trip.status='driver_waiting' and v_waiting_at is not null
        then greatest(0,300-floor(extract(epoch from(now()-v_waiting_at)))::integer)
      when v_role='passenger' and v_trip.status in ('driver_assigned','driver_arriving')
        then greatest(0,300-v_elapsed)
      else 0 end,
    'fee_enabled',coalesce(v_amount,0)>0
  );
end $$;

create or replace function public.cancellation_fee_quote_for_ride_request_v1(
  p_ride_request_id uuid,p_channel text default 'production'
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_trip_id uuid;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if (v_channel='preview' and not public.is_active_audit_user(v_uid)) or
     (v_channel='production' and public.is_active_audit_user(v_uid)) then
    raise exception 'La solicitud pertenece a otro entorno';
  end if;
  if not exists(select 1 from public.ride_requests r
    where r.id=p_ride_request_id and r.channel=v_channel and r.passenger_id=v_uid) then
    raise exception 'Solicitud no disponible';
  end if;
  select t.id into v_trip_id from public.trips t
    where t.ride_request_id=p_ride_request_id and t.channel=v_channel
    order by t.created_at desc limit 1;
  if v_trip_id is null then
    return jsonb_build_object('fee',0,'currency',null,'grace_seconds',0,
      'fee_enabled',false,'channel',v_channel);
  end if;
  return public.cancellation_fee_quote_v1(v_trip_id,v_channel);
end $$;

-- Remove the earlier three-argument client wrapper before adding the fee-bound
-- signature; otherwise authenticated clients could skip the displayed fee.
drop function if exists public.cancel_trip_v2(uuid,text,text);
drop function if exists public.cancel_ride_request_v2(uuid,text,text);

-- A successful trip cancellation and its fee debt are one transaction. The
-- legacy cancellation keeps ownership, notifications, and driver availability.
create or replace function public.cancel_trip_v2(
  p_trip_id uuid, p_reason text default null, p_channel text default 'production',
  p_confirmed_fee numeric default 0
) returns void language plpgsql security definer
set search_path=public as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_uid uuid:=auth.uid();
  v_trip public.trips%rowtype;
  v_quote jsonb;
  v_fee numeric:=0;
  v_zone uuid;
  v_country text;
  v_currency text;
  v_role text;
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if (v_channel='preview' and not public.is_active_audit_user(v_uid)) or
     (v_channel='production' and public.is_active_audit_user(v_uid)) then
    raise exception 'El viaje pertenece a otro entorno';
  end if;
  select * into v_trip from public.trips
    where id=p_trip_id and channel=v_channel for update;
  if not found or v_uid not in (v_trip.passenger_id,v_trip.driver_id) then
    raise exception 'Viaje no disponible';
  end if;
  if v_trip.status='cancelled' then return; end if;
  if v_trip.status not in ('driver_assigned','driver_arriving','driver_waiting') then
    raise exception 'El viaje ya no se puede cancelar desde este estado';
  end if;
  select r.zone_id into v_zone from public.ride_requests r
    where r.id=v_trip.ride_request_id and r.channel=v_channel;
  perform pg_advisory_xact_lock(hashtextextended(
    'zone-cancellation-fee:'||v_channel||':'||v_zone::text,0));
  v_quote:=public.cancellation_fee_quote_v1(p_trip_id,v_channel);
  v_fee:=coalesce((v_quote->>'fee')::numeric,0);
  if p_confirmed_fee is null or p_confirmed_fee<>v_fee then
    raise exception 'La tarifa de cancelación cambió. Revisa el monto actualizado y confirma otra vez.';
  end if;
  v_role:=v_quote->>'role';
  if v_fee>0 then
    select r.zone_id,r.country_code,r.currency into v_zone,v_country,v_currency
      from public.ride_requests r where r.id=v_trip.ride_request_id;
    insert into public.cancellation_fee_debts(
      user_id,trip_id,zone_id,channel,country_code,currency_code,role,
      amount,reason
    ) values(v_uid,p_trip_id,v_zone,v_channel,v_country,upper(v_currency),
      v_role,v_fee,coalesce(v_reason,'Cancelación de viaje'))
    on conflict(trip_id,user_id) do nothing;
  end if;
  perform set_config('app.runtime_channel',v_channel,true);
  perform public.cancel_trip(p_trip_id,v_reason);
end $$;

-- Passenger cancellation starts from a ride request, including the legacy
-- selected-driver flow. Quote and record any fee before invoking the existing
-- cancellation procedure, in the same transaction.
create or replace function public.cancel_ride_request_v2(
  p_ride_request_id uuid,p_reason text default null,
  p_channel text default 'production',p_confirmed_fee numeric default 0
) returns void language plpgsql security definer
set search_path=public as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_uid uuid:=auth.uid();
  v_quote jsonb;
  v_fee numeric:=0;
  v_trip_id uuid;
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
  v_zone uuid;
  v_country text;
  v_currency text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if (v_channel='preview' and not public.is_active_audit_user(v_uid)) or
     (v_channel='production' and public.is_active_audit_user(v_uid)) then
    raise exception 'La solicitud pertenece a otro entorno';
  end if;
  select zone_id into v_zone from public.ride_requests
    where id=p_ride_request_id and passenger_id=v_uid and channel=v_channel
    for update;
  if not found then raise exception 'Solicitud no disponible'; end if;
  -- Freeze the assigned trip state while comparing the displayed amount with
  -- the transactional quote; arrival/wait transitions must not race consent.
  select id into v_trip_id from public.trips
    where ride_request_id=p_ride_request_id and channel=v_channel
    order by created_at desc limit 1 for update;
  perform pg_advisory_xact_lock(hashtextextended(
    'zone-cancellation-fee:'||v_channel||':'||v_zone::text,0));
  v_quote:=public.cancellation_fee_quote_for_ride_request_v1(
    p_ride_request_id,v_channel);
  v_fee:=coalesce((v_quote->>'fee')::numeric,0);
  if p_confirmed_fee is null or p_confirmed_fee<>v_fee then
    raise exception 'La tarifa de cancelación cambió. Revisa el monto actualizado y confirma otra vez.';
  end if;
  if v_fee>0 then
    select r.zone_id,r.country_code,r.currency
      into v_zone,v_country,v_currency
      from public.ride_requests r
      where r.id=p_ride_request_id and r.channel=v_channel;
    if v_trip_id is null then raise exception 'Viaje no disponible'; end if;
    insert into public.cancellation_fee_debts(
      user_id,trip_id,zone_id,channel,country_code,currency_code,role,
      amount,reason
    ) values(v_uid,v_trip_id,v_zone,v_channel,v_country,upper(v_currency),
      'passenger',v_fee,coalesce(v_reason,'Cancelación de viaje'))
    on conflict(trip_id,user_id) do nothing;
  end if;
  perform set_config('app.runtime_channel',v_channel,true);
  perform public.cancel_ride_request(p_ride_request_id,v_reason);
end $$;

-- Direct legacy RPC calls must pass through the same fee-enforcing wrappers.
revoke all on function public.cancel_trip(uuid,text) from public,anon,authenticated;
revoke all on function public.cancel_ride_request(uuid,text) from public,anon,authenticated;
revoke all on function public.cancel_trip_v2(uuid,text,text,numeric) from public,anon;
revoke all on function public.cancel_ride_request_v2(uuid,text,text,numeric) from public,anon;
grant execute on function public.cancel_trip_v2(uuid,text,text,numeric) to authenticated;
grant execute on function public.cancel_ride_request_v2(uuid,text,text,numeric) to authenticated;
revoke all on function public.admin_zone_cancellation_fee_get(uuid,text) from public,anon;
revoke all on function public.admin_zone_cancellation_fee_set(uuid,boolean,numeric,numeric,text) from public,anon;
revoke all on function public.my_cancellation_fee_debts_v1(text) from public,anon;
revoke all on function public.cancellation_fee_quote_v1(uuid,text) from public,anon;
grant execute on function public.admin_zone_cancellation_fee_get(uuid,text) to authenticated;
grant execute on function public.admin_zone_cancellation_fee_set(uuid,boolean,numeric,numeric,text) to authenticated;
grant execute on function public.my_cancellation_fee_debts_v1(text) to authenticated;
revoke all on function public.preview_settle_cancellation_debts_v1() from public,anon;
grant execute on function public.preview_settle_cancellation_debts_v1() to authenticated;
grant execute on function public.cancellation_fee_quote_v1(uuid,text) to authenticated;
revoke all on function public.cancellation_fee_quote_for_ride_request_v1(uuid,text) from public,anon;
grant execute on function public.cancellation_fee_quote_for_ride_request_v1(uuid,text) to authenticated;

-- A trip debt is captured inside the same transaction that changes the trip to
-- cancelled, including the legacy passenger request cancellation endpoint.
create or replace function public.capture_trip_cancellation_fee_debt()
returns trigger language plpgsql security definer
set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_zone uuid;
  v_country text;
  v_currency text;
  v_fee numeric:=0;
  v_waiting_at timestamptz;
  v_assigned_at timestamptz;
  v_mode text;
begin
  if old.status in ('completed','cancelled') or new.status<>'cancelled'
     or v_uid is null or v_uid not in (new.passenger_id,new.driver_id) then
    return new;
  end if;
  if (new.channel='preview' and not public.is_active_audit_user(v_uid)) or
     (new.channel='production' and public.is_active_audit_user(v_uid)) then
    raise exception 'El viaje pertenece a otro entorno';
  end if;
  if v_uid=new.passenger_id then v_role:='passenger';
  else v_role:='driver'; end if;
  select r.zone_id,z.country_code,z.currency_code,r.service_mode
    into v_zone,v_country,v_currency,v_mode
    from public.ride_requests r
    join public.service_zones z on z.id=r.zone_id
    where r.id=new.ride_request_id;
  if v_zone is null then return new; end if;
  if coalesce(v_mode,'taxi')<>'taxi' then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'zone-cancellation-fee:'||new.channel||':'||v_zone::text,0));
  if v_role='passenger' then
    if old.status='driver_waiting' then
      select h.created_at into v_waiting_at from public.trip_status_history h
        where h.trip_id=new.id and h.status='driver_waiting'
        order by h.created_at desc limit 1;
      if v_waiting_at is not null and v_waiting_at>now()-interval '5 minutes' then
        select case when enabled then passenger_fee else 0 end into v_fee
          from public.zone_cancellation_fee_rules
          where zone_id=v_zone and channel=new.channel;
      end if;
    elsif old.status in ('driver_assigned','driver_arriving') then
      select h.created_at into v_assigned_at from public.trip_status_history h
        where h.trip_id=new.id and h.status='driver_assigned'
        order by h.created_at asc limit 1;
      v_assigned_at:=coalesce(v_assigned_at,old.created_at);
      if v_assigned_at>now()-interval '5 minutes' then
        select case when enabled then passenger_fee else 0 end into v_fee
          from public.zone_cancellation_fee_rules
          where zone_id=v_zone and channel=new.channel;
      end if;
    end if;
  elsif old.status in ('driver_assigned','driver_arriving') then
    select case when enabled then driver_fee else 0 end into v_fee
      from public.zone_cancellation_fee_rules
      where zone_id=v_zone and channel=new.channel;
  elsif old.status='driver_waiting' then
    select h.created_at into v_waiting_at from public.trip_status_history h
      where h.trip_id=new.id and h.status='driver_waiting'
      order by h.created_at desc limit 1;
    if v_waiting_at is not null and v_waiting_at>now()-interval '5 minutes' then
      select case when enabled then driver_fee else 0 end into v_fee
        from public.zone_cancellation_fee_rules
        where zone_id=v_zone and channel=new.channel;
    end if;
  end if;
  if coalesce(v_fee,0)>0 then
    insert into public.cancellation_fee_debts(
      user_id,trip_id,zone_id,channel,country_code,currency_code,role,
      amount,reason
    ) values(
      v_uid,new.id,v_zone,new.channel,v_country,upper(v_currency),v_role,
      v_fee,'Cancelación de viaje'
    ) on conflict(trip_id,user_id) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists trips_capture_cancellation_fee_debt on public.trips;
create trigger trips_capture_cancellation_fee_debt
before update of status on public.trips
for each row execute function public.capture_trip_cancellation_fee_debt();
revoke all on function public.capture_trip_cancellation_fee_debt() from public,anon,authenticated;

-- Unpaid cancellation debt blocks a new ride request. This is server-enforced,
-- and is isolated by runtime channel and country.
create or replace function public.guard_ride_request_cancellation_debt()
returns trigger language plpgsql security definer
set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_due numeric;
begin
  if v_uid is null or new.passenger_id<>v_uid
     or coalesce(new.service_mode,'taxi')<>'taxi' then return new; end if;
  select country_code into v_country from public.service_zones where id=new.zone_id;
  select coalesce(sum(d.amount),0) into v_due
    from public.cancellation_fee_debts d
    where d.user_id=v_uid and d.country_code=v_country
      and d.channel=new.channel and d.paid_at is null;
  if v_due>0 then
    raise exception 'Tienes una deuda de cancelación pendiente de % %. Págala con el QR desde Pagos y billetera para solicitar otro viaje.',
      trim(to_char(v_due,'FM999999990.00')),coalesce((select currency_code from public.service_zones where id=new.zone_id),'');
  end if;
  return new;
end $$;
drop trigger if exists ride_requests_guard_cancellation_debt on public.ride_requests;
create trigger ride_requests_guard_cancellation_debt
before insert on public.ride_requests
for each row execute function public.guard_ride_request_cancellation_debt();
revoke all on function public.guard_ride_request_cancellation_debt() from public,anon,authenticated;

-- Drivers with an unpaid cancellation debt cannot keep accepting Taxi work.
-- The offer guard provides early feedback; the trips guard closes the race
-- where a previously submitted offer is selected after the debt is recorded.
create or replace function public.guard_driver_cancellation_debt()
returns trigger language plpgsql security definer
set search_path=public as $$
declare
  v_mode text;
  v_country text;
begin
  select r.service_mode,z.country_code into v_mode,v_country
    from public.ride_requests r
    join public.service_zones z on z.id=r.zone_id
    where r.id=new.ride_request_id;
  if coalesce(v_mode,'taxi')<>'taxi' or v_country is null then
    return new;
  end if;
  if exists(select 1 from public.cancellation_fee_debts d
    where d.user_id=new.driver_id and d.channel=new.channel
      and d.country_code=v_country and d.paid_at is null) then
    raise exception 'Tienes una deuda de cancelación pendiente. Págala con el QR desde Pagos y billetera antes de aceptar otro viaje.';
  end if;
  return new;
end $$;
drop trigger if exists driver_offers_guard_cancellation_debt on public.driver_offers;
create trigger driver_offers_guard_cancellation_debt
before insert on public.driver_offers
for each row execute function public.guard_driver_cancellation_debt();
drop trigger if exists trips_guard_driver_cancellation_debt on public.trips;
create trigger trips_guard_driver_cancellation_debt
before insert on public.trips
for each row execute function public.guard_driver_cancellation_debt();
revoke all on function public.guard_driver_cancellation_debt() from public,anon,authenticated;

-- Reuse the existing verified provider checkout infrastructure for debt QR
-- settlement without crediting the wallet as a top-up.
alter table public.wallet_gateway_checkouts
  add column if not exists purpose text not null default 'wallet_topup',
  add column if not exists cancellation_debt_ids uuid[] not null default '{}';
alter table public.wallet_gateway_checkouts
  drop constraint if exists wallet_gateway_checkouts_purpose_check;
alter table public.wallet_gateway_checkouts
  add constraint wallet_gateway_checkouts_purpose_check
    check (purpose in ('wallet_topup','cancellation_debt'));
alter table public.wallet_gateway_checkouts
  drop constraint if exists wallet_gateway_checkouts_amount_check;
alter table public.wallet_gateway_checkouts
  add constraint wallet_gateway_checkouts_amount_check check (amount>=1 and amount<=5000);

create or replace function public.service_finalize_verified_cancellation_debt_gateway(
  p_checkout_id uuid,p_provider_order_id text,
  p_verified_amount numeric,p_verified_currency text
) returns jsonb language plpgsql security definer
set search_path=public as $$
declare
  v_item public.wallet_gateway_checkouts%rowtype;
  v_total numeric;
  v_count integer;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then
    raise exception 'Solo disponible para el servicio de pagos';
  end if;
  select * into v_item from public.wallet_gateway_checkouts
    where id=p_checkout_id for update;
  if not found or v_item.purpose<>'cancellation_debt' then
    raise exception 'Pago de deuda no encontrado';
  end if;
  if v_item.status='paid' then
    return jsonb_build_object('paid',true,'already_processed',true);
  end if;
  if v_item.status<>'pending' then
    raise exception 'Pago no pendiente';
  end if;
  if v_item.provider_order_id is null or v_item.provider_order_id<>p_provider_order_id
     or v_item.amount<>round(p_verified_amount,2)
     or v_item.currency_code<>upper(trim(p_verified_currency)) then
    raise exception 'No coinciden referencia, monto o moneda verificados';
  end if;
  if v_item.channel<>'production' or public.is_active_audit_user(v_item.user_id)
     or not public.is_production_runtime_user(v_item.user_id) then
    raise exception 'Las cuentas Preview no pueden realizar pagos reales';
  end if;
  perform 1 from public.cancellation_fee_debts
    where id=any(v_item.cancellation_debt_ids)
      and user_id=v_item.user_id and channel=v_item.channel
      and country_code=v_item.country_code and paid_at is null
    for update;
  select coalesce(sum(amount),0),count(*) into v_total,v_count
    from public.cancellation_fee_debts
    where id=any(v_item.cancellation_debt_ids)
      and user_id=v_item.user_id and channel=v_item.channel
      and country_code=v_item.country_code and paid_at is null;
  if v_count=0 or v_total<>v_item.amount then
    raise exception 'El monto de la deuda cambió; genera un nuevo QR';
  end if;
  update public.cancellation_fee_debts
    set paid_at=now(),payment_checkout_id=v_item.id
    where id=any(v_item.cancellation_debt_ids)
      and user_id=v_item.user_id and channel=v_item.channel
      and country_code=v_item.country_code and paid_at is null;
  update public.wallet_gateway_checkouts
    set status='paid',paid_at=now() where id=v_item.id;
  insert into public.notifications(user_id,title,body,type,metadata,channel)
    values(v_item.user_id,'Deuda de cancelación pagada',
      'Se confirmó el pago de tu deuda por cancelación.',
      'cancellation_fee_paid',jsonb_build_object('checkout_id',v_item.id,
      'country_code',v_item.country_code,'channel',v_item.channel),'production');
  return jsonb_build_object('paid',true,'already_processed',false,
    'checkout_id',v_item.id,'amount',v_item.amount);
end $$;
revoke all on function public.service_finalize_verified_cancellation_debt_gateway(uuid,text,numeric,text)
  from public,anon,authenticated;
grant execute on function public.service_finalize_verified_cancellation_debt_gateway(uuid,text,numeric,text)
  to service_role;
