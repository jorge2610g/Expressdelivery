-- Cancellation fee routines must read country and currency from the related
-- service zone. ride_requests stores zone_id/currency, but has no country_code.
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
  select r.zone_id,z.country_code,z.currency_code,r.service_mode
    into v_zone,v_country,v_currency,v_mode
    from public.ride_requests r
    join public.service_zones z on z.id=r.zone_id
    where r.id=v_trip.ride_request_id and r.channel=v_channel;
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

create or replace function public.cancel_trip_v2(
  p_trip_id uuid, p_reason text default null,
  p_channel text default 'production', p_confirmed_fee numeric default 0
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
    select r.zone_id,z.country_code,z.currency_code
      into v_zone,v_country,v_currency
      from public.ride_requests r
      join public.service_zones z on z.id=r.zone_id
      where r.id=v_trip.ride_request_id and r.channel=v_channel;
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
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if (v_channel='preview' and not public.is_active_audit_user(v_uid)) or
     (v_channel='production' and public.is_active_audit_user(v_uid)) then
    raise exception 'La solicitud pertenece a otro entorno';
  end if;
  select zone_id into v_zone from public.ride_requests
    where id=p_ride_request_id and passenger_id=v_uid and channel=v_channel
    for update;
  if not found then raise exception 'Solicitud no disponible'; end if;
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
    select r.zone_id,z.country_code,z.currency_code
      into v_zone,v_country,v_currency
      from public.ride_requests r
      join public.service_zones z on z.id=r.zone_id
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
