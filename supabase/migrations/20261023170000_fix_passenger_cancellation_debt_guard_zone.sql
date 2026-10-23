-- The debt guard runs alphabetically before trg_ride_zone_from_pickup, so NEW.zone_id
-- is still null on insert. Resolve the pickup zone directly before checking debts.
create or replace function public.guard_ride_request_cancellation_debt()
returns trigger language plpgsql security definer
set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_zone uuid;
  v_country text;
  v_currency text;
  v_due numeric:=0;
  v_has_debt boolean:=false;
begin
  if v_uid is null or new.passenger_id<>v_uid
     or coalesce(new.service_mode,'taxi')<>'taxi' then return new; end if;

  -- Do not depend on NEW.zone_id: the zone-assignment trigger runs later.
  v_zone:=coalesce(
    new.zone_id,
    public.service_zone_id_for_point(new.pickup_latitude,new.pickup_longitude)
  );
  select country_code,upper(currency_code)
    into v_country,v_currency
    from public.service_zones where id=v_zone;

  if v_country is not null then
    select coalesce(sum(d.amount),0) into v_due
      from public.cancellation_fee_debts d
      where d.user_id=v_uid and d.country_code=v_country
        and d.channel=new.channel and d.paid_at is null;
  else
    -- A missing/unresolvable zone must not let an indebted passenger bypass
    -- the guard by submitting a request without usable pickup coordinates.
    select exists(
      select 1 from public.cancellation_fee_debts d
      where d.user_id=v_uid and d.channel=new.channel and d.paid_at is null
    ) into v_has_debt;
    if v_has_debt then
      raise exception 'Tienes una deuda por cancelación pendiente. Págala desde Pagos y billetera antes de solicitar otro viaje.';
    end if;
  end if;

  if v_due>0 then
    v_currency:=coalesce(v_currency,case v_country when 'CL' then 'CLP' when 'BO' then 'BOB' end,'');
    raise exception 'Tienes una deuda por cancelación pendiente de % %. Págala desde Pagos y billetera antes de solicitar otro viaje.',
      case when v_currency='CLP'
        then trim(to_char(v_due,'FM999999990'))
        else trim(to_char(v_due,'FM999999990.00')) end,
      v_currency;
  end if;
  return new;
end $$;

-- Recreate only this trigger so the function replacement also repairs databases
-- where an older trigger definition may use a different name.
drop trigger if exists ride_requests_guard_cancellation_debt on public.ride_requests;
create trigger ride_requests_guard_cancellation_debt
before insert on public.ride_requests
for each row execute function public.guard_ride_request_cancellation_debt();
revoke all on function public.guard_ride_request_cancellation_debt() from public,anon,authenticated;
