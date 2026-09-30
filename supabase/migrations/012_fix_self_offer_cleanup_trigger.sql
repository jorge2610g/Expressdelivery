-- Prevent historical self-offer cleanup from breaking passenger home.
-- Applied to production Supabase project zgpijrznvaskgcmauwxx on 2026-09-30.

create or replace function public.notify_ride_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_passenger uuid;
  v_driver_name text;
  v_amount text;
begin
  -- Status cleanup on old offers must not be treated as a new offer.
  if new.status <> 'pending' then
    return new;
  end if;

  select r.passenger_id
    into v_passenger
  from public.ride_requests r
  where r.id = new.ride_request_id;

  if v_passenger is null then
    return new;
  end if;

  if new.driver_id = v_passenger then
    raise exception 'No puedes ofertar en tu propia solicitud';
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'pending'
     and old.proposed_fare is not distinct from new.proposed_fare
     and old.eta_minutes is not distinct from new.eta_minutes
     and old.expires_at is not distinct from new.expires_at then
    return new;
  end if;

  update public.ride_requests
  set status = 'offers_received', updated_at = now()
  where id = new.ride_request_id
    and status = 'searching';

  select nullif(trim(u.full_name), '')
    into v_driver_name
  from public.users u
  where u.id = new.driver_id;

  v_amount := trim(to_char(new.proposed_fare, 'FM999999990.00'));

  insert into public.notifications(user_id, title, body, type)
  values
    (
      v_passenger,
      'Nueva oferta',
      coalesce(v_driver_name, 'Un conductor') ||
        ' ofertó Bs ' || v_amount || ' para tu viaje.',
      'ride_offer'
    ),
    (
      new.driver_id,
      'Oferta enviada',
      'Tu oferta de Bs ' || v_amount ||
        ' fue enviada al pasajero.',
      'ride_offer_sent'
    );

  return new;
end;
$$;

revoke execute on function public.notify_ride_offer()
  from public, anon, authenticated;

update public.driver_offers o
set status = 'declined'
from public.ride_requests r
where r.id = o.ride_request_id
  and o.driver_id = r.passenger_id
  and o.status = 'pending';
