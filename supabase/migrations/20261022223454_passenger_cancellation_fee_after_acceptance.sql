-- Cancellation policy correction: a passenger fee applies whenever they
-- cancel after a driver accepts, regardless of elapsed time. The five-minute
-- grace period belongs only to a driver who marked the passenger as waiting.
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
  v_waiting_at timestamptz;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
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
  if v_uid=v_trip.passenger_id then v_role:='passenger';
  else v_role:='driver'; end if;
  select h.created_at into v_waiting_at from public.trip_status_history h
    where h.trip_id=p_trip_id and h.status='driver_waiting'
    order by h.created_at desc limit 1;
  if v_role='passenger' then
    if v_trip.status in ('driver_assigned','driver_arriving','driver_waiting') then
      select case when enabled then passenger_fee else 0 end into v_amount
        from public.zone_cancellation_fee_rules
        where zone_id=v_zone and channel=v_channel;
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
      when v_role='driver' and v_trip.status='driver_waiting'
           and v_waiting_at is not null
        then greatest(0,300-floor(extract(epoch from(now()-v_waiting_at)))::integer)
      else 0 end,
    'fee_enabled',coalesce(v_amount,0)>0
  );
end $$;
