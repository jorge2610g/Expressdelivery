-- Return actionable, localized debt details when a driver or passenger is
-- blocked from starting another Taxi action. No balances or trip state change.
create or replace function public.guard_ride_request_cancellation_debt()
returns trigger language plpgsql security definer
set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_currency text;
  v_due numeric;
  v_amount text;
  v_provider text;
begin
  if v_uid is null or new.passenger_id<>v_uid
     or coalesce(new.service_mode,'taxi')<>'taxi' then return new; end if;
  select country_code,upper(currency_code)
    into v_country,v_currency
    from public.service_zones where id=new.zone_id;
  select coalesce(sum(d.amount),0) into v_due
    from public.cancellation_fee_debts d
    where d.user_id=v_uid and d.country_code=v_country
      and d.channel=new.channel and d.paid_at is null;
  if v_due>0 then
    v_currency:=coalesce(v_currency,case v_country when 'CL' then 'CLP' when 'BO' then 'BOB' end);
    v_amount:=case when v_currency='CLP'
      then trim(to_char(v_due,'FM999999990'))
      else trim(to_char(v_due,'FM999999990.00')) end;
    v_provider:=case v_country when 'CL' then 'Mercado Pago'
      when 'BO' then 'VeriPagos' else 'el QR de pago' end;
    raise exception 'Tienes una deuda por cancelación pendiente de % %. Págala con % desde Pagos y billetera > Pagar deuda con QR antes de solicitar otro viaje.',
      v_currency,v_amount,v_provider;
  end if;
  return new;
end $$;

create or replace function public.guard_driver_cancellation_debt()
returns trigger language plpgsql security definer
set search_path=public as $$
declare
  v_mode text;
  v_country text;
  v_currency text;
  v_due numeric;
  v_amount text;
  v_provider text;
begin
  select r.service_mode,z.country_code,upper(z.currency_code)
    into v_mode,v_country,v_currency
    from public.ride_requests r
    join public.service_zones z on z.id=r.zone_id
    where r.id=new.ride_request_id;
  if coalesce(v_mode,'taxi')<>'taxi' or v_country is null then
    return new;
  end if;
  select coalesce(sum(d.amount),0) into v_due
    from public.cancellation_fee_debts d
    where d.user_id=new.driver_id and d.channel=new.channel
      and d.country_code=v_country and d.paid_at is null;
  if v_due>0 then
    v_currency:=coalesce(v_currency,case v_country when 'CL' then 'CLP' when 'BO' then 'BOB' end);
    v_amount:=case when v_currency='CLP'
      then trim(to_char(v_due,'FM999999990'))
      else trim(to_char(v_due,'FM999999990.00')) end;
    v_provider:=case v_country when 'CL' then 'Mercado Pago'
      when 'BO' then 'VeriPagos' else 'el QR de pago' end;
    raise exception 'Tienes una deuda por cancelación pendiente de % %. Págala con % desde Pagos y billetera > Pagar deuda con QR antes de aceptar viajes.',
      v_currency,v_amount,v_provider;
  end if;
  return new;
end $$;
