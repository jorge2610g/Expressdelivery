-- Realtime ride notifications and self-offer hardening.
-- Applied to production Supabase project zgpijrznvaskgcmauwxx on 2026-09-30.

create or replace function public.available_ride_requests_for_driver()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not public.is_approved_online_driver(v_uid) then
    return '[]'::jsonb;
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(r) order by r.created_at asc),
    '[]'::jsonb
  )
  into v_result
  from public.ride_requests r
  where r.status in ('searching','offers_received')
    and r.expires_at > now()
    and r.passenger_id <> v_uid
    and (
      r.scheduled_for is null
      or r.scheduled_for <= now() + interval '30 minutes'
    );

  return v_result;
end;
$$;

revoke execute on function public.available_ride_requests_for_driver()
  from public, anon;
grant execute on function public.available_ride_requests_for_driver()
  to authenticated;

drop policy if exists offers_insert_approved_driver
  on public.driver_offers;
create policy offers_insert_approved_driver
on public.driver_offers
for insert
to authenticated
with check (
  driver_id = auth.uid()
  and public.is_approved_online_driver(auth.uid())
  and public.ride_request_is_open(ride_request_id)
  and not public.is_ride_request_passenger(ride_request_id, auth.uid())
);

drop policy if exists offers_update_driver
  on public.driver_offers;
create policy offers_update_driver
on public.driver_offers
for update
to authenticated
using (
  driver_id = auth.uid()
  and not public.is_ride_request_passenger(ride_request_id, auth.uid())
)
with check (
  driver_id = auth.uid()
  and not public.is_ride_request_passenger(ride_request_id, auth.uid())
);

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

  if new.status <> 'pending' then
    return new;
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

drop trigger if exists trg_notify_ride_offer
  on public.driver_offers;
create trigger trg_notify_ride_offer
after insert or update
on public.driver_offers
for each row
execute function public.notify_ride_offer();

create or replace function public.notify_available_ride_to_drivers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'searching' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.status = 'searching'
       and old.expires_at is not distinct from new.expires_at
       and old.proposed_fare is not distinct from new.proposed_fare then
      return new;
    end if;
  end if;

  if new.scheduled_for is not null
     and new.scheduled_for > now() + interval '30 minutes' then
    return new;
  end if;

  insert into public.notifications(user_id, title, body, type)
  select
    dp.id,
    'Nueva solicitud disponible',
    'Viaje por Bs ' ||
      trim(to_char(new.proposed_fare, 'FM999999990.00')) ||
      ': ' ||
      left(
        coalesce(nullif(trim(new.pickup_address), ''), 'Origen'),
        54
      ) ||
      ' → ' ||
      left(
        coalesce(nullif(trim(new.destination_address), ''), 'Destino'),
        54
      ),
    'ride_request'
  from public.driver_profiles dp
  where dp.approval_status = 'approved'
    and dp.online_status = 'online'
    and dp.id <> new.passenger_id
    and (
      new.pickup_latitude is null
      or new.pickup_longitude is null
      or dp.latitude is null
      or dp.longitude is null
      or (
        6371 * acos(
          least(1, greatest(-1,
            cos(radians(new.pickup_latitude::double precision))
            * cos(radians(dp.latitude::double precision))
            * cos(
                radians(dp.longitude::double precision)
                - radians(new.pickup_longitude::double precision)
              )
            + sin(radians(new.pickup_latitude::double precision))
            * sin(radians(dp.latitude::double precision))
          ))
        )
      ) <= 10
    );

  return new;
end;
$$;

drop trigger if exists trg_notify_available_ride
  on public.ride_requests;
create trigger trg_notify_available_ride
after insert or update
on public.ride_requests
for each row
execute function public.notify_available_ride_to_drivers();

create or replace function public.select_ride_offer(p_offer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ride_id uuid;
  v_driver_id uuid;
  v_passenger_id uuid;
  v_fare numeric;
  v_trip_id uuid;
  v_pin text;
begin
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  update public.driver_offers
  set status = 'expired'
  where id = p_offer_id
    and status = 'pending'
    and expires_at is not null
    and expires_at <= now();

  select o.ride_request_id, o.driver_id, r.passenger_id, o.proposed_fare
    into v_ride_id, v_driver_id, v_passenger_id, v_fare
  from public.driver_offers o
  join public.ride_requests r on r.id = o.ride_request_id
  where o.id = p_offer_id
    and r.passenger_id = auth.uid()
    and o.status = 'pending'
    and (o.expires_at is null or o.expires_at > now())
    and r.status in ('searching','offers_received')
  for update of o, r;

  if v_ride_id is null then
    raise exception 'Oferta vencida o no disponible';
  end if;

  if v_driver_id = v_passenger_id then
    raise exception 'No puedes asignarte tu propia solicitud';
  end if;

  insert into public.notifications(user_id, title, body, type)
  select distinct
    o.driver_id,
    'Oferta no elegida',
    'El pasajero aceptó otra oferta para este viaje.',
    'ride_offer_declined'
  from public.driver_offers o
  where o.ride_request_id = v_ride_id
    and o.status = 'pending'
    and o.id <> p_offer_id
    and o.driver_id <> v_driver_id;

  update public.driver_offers
  set status = case when id = p_offer_id then 'selected' else 'declined' end
  where ride_request_id = v_ride_id
    and status = 'pending';

  update public.ride_requests
  set status = 'driver_selected', updated_at = now()
  where id = v_ride_id;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');

  insert into public.trips (
    ride_request_id, passenger_id, driver_id, status, final_fare,
    payment_status, boarding_pin
  ) values (
    v_ride_id, v_passenger_id, v_driver_id, 'driver_assigned', v_fare,
    'pending', v_pin
  )
  returning id into v_trip_id;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (v_trip_id, 'driver_assigned', auth.uid());

  update public.driver_profiles
  set online_status = 'busy', updated_at = now()
  where id = v_driver_id;

  insert into public.notifications (user_id, title, body, type)
  values
    (
      v_driver_id,
      'Oferta aceptada',
      'El pasajero eligió tu oferta. Ya tienes un viaje asignado.',
      'ride_assigned'
    ),
    (
      v_passenger_id,
      'Conductor asignado',
      'Tu viaje ya tiene un conductor asignado.',
      'ride_assigned'
    );

  return v_trip_id;
end;
$$;

revoke execute on function public.select_ride_offer(uuid)
  from public, anon;
grant execute on function public.select_ride_offer(uuid)
  to authenticated;
