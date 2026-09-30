-- Rider live search, expiring offers and payment labels.
-- Applied to production Supabase project zgpijrznvaskgcmauwxx on 2026-09-30.

alter table public.ride_requests drop constraint if exists ride_requests_payment_method_check;
alter table public.ride_requests add constraint ride_requests_payment_method_check
  check (payment_method = any (array[
    'cash'::text,'pagorut'::text,'mercado_pago'::text,'santander'::text,
    'mach'::text,'tenpo'::text,'card'::text,'wallet'::text
  ]));

alter table public.delivery_requests drop constraint if exists delivery_requests_payment_method_check;
alter table public.delivery_requests add constraint delivery_requests_payment_method_check
  check (payment_method = any (array[
    'cash'::text,'pagorut'::text,'mercado_pago'::text,'santander'::text,
    'mach'::text,'tenpo'::text,'card'::text,'wallet'::text
  ]));

alter table public.payment_transactions drop constraint if exists payment_transactions_method_check;
alter table public.payment_transactions add constraint payment_transactions_method_check
  check (method = any (array[
    'cash'::text,'pagorut'::text,'mercado_pago'::text,'santander'::text,
    'mach'::text,'tenpo'::text,'card'::text,'wallet'::text
  ]));

update public.app_settings
set offer_timeout_seconds = 20, updated_at = now()
where id = true;

alter table public.driver_offers add column if not exists expires_at timestamptz;
update public.driver_offers
set expires_at = created_at + interval '20 seconds'
where expires_at is null;
alter table public.driver_offers
  alter column expires_at set default (now() + interval '20 seconds');

create table if not exists public.ride_request_views (
  ride_request_id uuid not null references public.ride_requests(id) on delete cascade,
  driver_id uuid not null references public.driver_profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (ride_request_id, driver_id)
);
alter table public.ride_request_views enable row level security;

create or replace function public.mark_ride_requests_viewed(p_ride_request_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if not public.is_approved_online_driver(auth.uid()) then
    raise exception 'Conductor no disponible';
  end if;

  insert into public.ride_request_views (ride_request_id, driver_id, viewed_at)
  select r.id, auth.uid(), now()
  from public.ride_requests r
  where r.id = any(p_ride_request_ids)
    and r.status in ('searching','offers_received')
    and coalesce(r.expires_at, now() + interval '1 second') > now()
  on conflict (ride_request_id, driver_id)
  do update set viewed_at = excluded.viewed_at;
end;
$$;

create or replace function public.ride_request_view_count(p_ride_request_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists (
    select 1 from public.ride_requests r
    where r.id = p_ride_request_id and r.passenger_id = auth.uid()
  ) then
    raise exception 'No autorizado';
  end if;

  select count(*)::integer into v_count
  from public.ride_request_views v
  where v.ride_request_id = p_ride_request_id;

  return coalesce(v_count, 0);
end;
$$;

create or replace function public.nearby_online_driver_markers(
  p_lat numeric,
  p_lng numeric,
  p_radius_km numeric default 5
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  with candidates as (
    select
      round(dp.latitude::numeric, 3) as latitude,
      round(dp.longitude::numeric, 3) as longitude,
      coalesce(
        (
          select dv.vehicle_type
          from public.driver_vehicles dv
          where dv.driver_id = dp.id and dv.is_active = true
          order by dv.updated_at desc
          limit 1
        ),
        case
          when lower(coalesce(dp.vehicle_summary,'')) like '%moto%' then 'motorcycle'
          when lower(coalesce(dp.vehicle_summary,'')) like '%xl%' then 'xl'
          else 'car'
        end
      ) as vehicle_type,
      (
        6371 * acos(
          least(1, greatest(-1,
            cos(radians(p_lat::double precision))
            * cos(radians(dp.latitude::double precision))
            * cos(radians(dp.longitude::double precision) - radians(p_lng::double precision))
            + sin(radians(p_lat::double precision))
            * sin(radians(dp.latitude::double precision))
          ))
        )
      ) as distance_km
    from public.driver_profiles dp
    where dp.approval_status = 'approved'
      and dp.online_status = 'online'
      and dp.latitude is not null
      and dp.longitude is not null
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'latitude', latitude,
        'longitude', longitude,
        'vehicle_type', vehicle_type,
        'distance_km', round(distance_km::numeric, 1)
      )
      order by distance_km
    ),
    '[]'::jsonb
  )
  into v_result
  from (
    select * from candidates
    where distance_km <= greatest(0.5, least(coalesce(p_radius_km, 5), 20))
    order by distance_km
    limit 12
  ) q;

  return v_result;
end;
$$;

create or replace function public.decline_ride_offer(p_offer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid;
  v_ride_id uuid;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select o.driver_id, o.ride_request_id
  into v_driver_id, v_ride_id
  from public.driver_offers o
  join public.ride_requests r on r.id = o.ride_request_id
  where o.id = p_offer_id
    and r.passenger_id = auth.uid()
    and o.status = 'pending'
  for update of o;

  if v_ride_id is null then
    raise exception 'Oferta no disponible';
  end if;

  update public.driver_offers set status = 'declined'
  where id = p_offer_id;

  insert into public.notifications(user_id, title, body, type)
  values (
    v_driver_id,
    'Oferta no elegida',
    'El pasajero continuó revisando otras ofertas.',
    'ride_offer_declined'
  );
end;
$$;

create or replace function public.cleanup_expired_ride_offers()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  update public.driver_offers
  set status = 'expired'
  where status = 'pending'
    and expires_at is not null
    and expires_at <= now();
end;
$$;

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

  update public.driver_offers
  set status = case when id = p_offer_id then 'selected' else 'declined' end
  where ride_request_id = v_ride_id and status = 'pending';

  update public.ride_requests
  set status = 'driver_selected', updated_at = now()
  where id = v_ride_id;

  insert into public.trips (
    ride_request_id, passenger_id, driver_id, status, final_fare, payment_status
  ) values (
    v_ride_id, v_passenger_id, v_driver_id, 'driver_assigned', v_fare, 'pending'
  )
  returning id into v_trip_id;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (v_trip_id, 'driver_assigned', auth.uid());

  update public.driver_profiles
  set online_status = 'busy', updated_at = now()
  where id = v_driver_id;

  insert into public.notifications (user_id, title, body, type)
  values
    (v_driver_id, 'Oferta aceptada', 'El pasajero eligió tu oferta. Ya tienes un viaje asignado.', 'ride_assigned'),
    (v_passenger_id, 'Conductor asignado', 'Tu viaje ya tiene un conductor asignado.', 'ride_assigned');

  return v_trip_id;
end;
$$;

grant execute on function public.mark_ride_requests_viewed(uuid[]) to authenticated;
grant execute on function public.ride_request_view_count(uuid) to authenticated;
grant execute on function public.nearby_online_driver_markers(numeric,numeric,numeric) to authenticated;
grant execute on function public.decline_ride_offer(uuid) to authenticated;
grant execute on function public.cleanup_expired_ride_offers() to authenticated;


-- Restrict newly exposed SECURITY DEFINER RPCs to signed-in users only.
revoke all on table public.ride_request_views from anon;
revoke all on table public.ride_request_views from authenticated;

revoke execute on function public.mark_ride_requests_viewed(uuid[]) from public, anon;
revoke execute on function public.ride_request_view_count(uuid) from public, anon;
revoke execute on function public.nearby_online_driver_markers(numeric,numeric,numeric) from public, anon;
revoke execute on function public.decline_ride_offer(uuid) from public, anon;
revoke execute on function public.cleanup_expired_ride_offers() from public, anon;

grant execute on function public.mark_ride_requests_viewed(uuid[]) to authenticated;
grant execute on function public.ride_request_view_count(uuid) to authenticated;
grant execute on function public.nearby_online_driver_markers(numeric,numeric,numeric) to authenticated;
grant execute on function public.decline_ride_offer(uuid) to authenticated;
grant execute on function public.cleanup_expired_ride_offers() to authenticated;

create index if not exists ride_request_views_driver_id_idx
  on public.ride_request_views(driver_id);
