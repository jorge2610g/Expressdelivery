-- Rider search visuals: driver viewer avatars and offer identity.
-- Applied to production Supabase on 2026-09-30.

create or replace function public.ride_request_viewers(p_ride_request_id uuid)
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

  if not exists (
    select 1
    from public.ride_requests r
    where r.id = p_ride_request_id
      and r.passenger_id = auth.uid()
  ) then
    raise exception 'No autorizado';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'driver_id', v.driver_id,
        'viewed_at', v.viewed_at,
        'full_name', u.full_name,
        'avatar_url', u.avatar_url,
        'rating', dp.rating,
        'completed_trips', dp.completed_trips,
        'vehicle_summary', dp.vehicle_summary
      )
      order by v.viewed_at desc
    ),
    '[]'::jsonb
  )
  into v_result
  from (
    select rv.driver_id, rv.viewed_at
    from public.ride_request_views rv
    where rv.ride_request_id = p_ride_request_id
    order by rv.viewed_at desc
    limit 12
  ) v
  join public.users u on u.id = v.driver_id
  left join public.driver_profiles dp on dp.id = v.driver_id;

  return v_result;
end;
$$;

revoke execute on function public.ride_request_viewers(uuid) from public, anon;
grant execute on function public.ride_request_viewers(uuid) to authenticated;

create or replace function public.passenger_home_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_open_ride public.ride_requests%rowtype;
  v_active_trip public.trips%rowtype;
  v_active_delivery public.delivery_requests%rowtype;
  v_driver_id uuid;
  v_counterpart jsonb;
  v_driver_profile jsonb;
  v_offers jsonb := '[]'::jsonb;
  v_saved jsonb := '[]'::jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  update public.driver_offers o
  set status = 'declined'
  where o.status = 'pending'
    and exists (
      select 1
      from public.ride_requests r
      where r.id = o.ride_request_id
        and r.passenger_id = v_uid
        and r.status in ('searching','offers_received')
        and r.expires_at <= now()
    );

  update public.ride_requests
  set status = 'cancelled',
      updated_at = now()
  where passenger_id = v_uid
    and status in ('searching','offers_received')
    and expires_at <= now();

  select *
  into v_active_trip
  from public.trips
  where passenger_id = v_uid
    and status not in ('completed','cancelled')
  order by created_at desc
  limit 1;

  if v_active_trip.id is null then
    select *
    into v_open_ride
    from public.ride_requests
    where passenger_id = v_uid
      and status in ('searching','offers_received')
      and expires_at > now()
    order by created_at desc
    limit 1;
  end if;

  select *
  into v_active_delivery
  from public.delivery_requests
  where customer_id = v_uid
    and status not in ('delivered','cancelled')
  order by created_at desc
  limit 1;

  if v_open_ride.id is not null then
    select coalesce(
      jsonb_agg(
        to_jsonb(o) ||
        jsonb_build_object(
          'driver_profiles',
          jsonb_build_object(
            'id', dp.id,
            'rating', dp.rating,
            'completed_trips', dp.completed_trips,
            'vehicle_summary', dp.vehicle_summary,
            'city', dp.city,
            'approval_status', dp.approval_status,
            'online_status', dp.online_status
          ),
          'driver_user',
          jsonb_build_object(
            'id', u.id,
            'full_name', u.full_name,
            'avatar_url', u.avatar_url
          )
        )
        order by o.created_at asc
      ),
      '[]'::jsonb
    )
    into v_offers
    from public.driver_offers o
    left join public.driver_profiles dp on dp.id = o.driver_id
    left join public.users u on u.id = o.driver_id
    where o.ride_request_id = v_open_ride.id;
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(sa) order by sa.created_at desc),
    '[]'::jsonb
  )
  into v_saved
  from public.saved_addresses sa
  where sa.user_id = v_uid;

  v_driver_id := coalesce(v_active_trip.driver_id, v_active_delivery.courier_id);

  if v_driver_id is not null then
    select jsonb_build_object(
      'id', u.id,
      'full_name', u.full_name,
      'phone', u.phone,
      'avatar_url', u.avatar_url,
      'active_mode', u.active_mode
    )
    into v_counterpart
    from public.users u
    where u.id = v_driver_id;

    select jsonb_build_object(
      'id', dp.id,
      'rating', dp.rating,
      'completed_trips', dp.completed_trips,
      'vehicle_summary', dp.vehicle_summary,
      'city', dp.city,
      'approval_status', dp.approval_status,
      'online_status', dp.online_status
    )
    into v_driver_profile
    from public.driver_profiles dp
    where dp.id = v_driver_id;
  end if;

  return jsonb_build_object(
    'open_ride',
      case when v_open_ride.id is null then null else to_jsonb(v_open_ride) end,
    'active_trip',
      case
        when v_active_trip.id is null then null
        else to_jsonb(v_active_trip) ||
          jsonb_build_object(
            'ride_requests',
            (
              select to_jsonb(r)
              from public.ride_requests r
              where r.id = v_active_trip.ride_request_id
            )
          )
      end,
    'active_delivery',
      case when v_active_delivery.id is null then null else to_jsonb(v_active_delivery) end,
    'offers', v_offers,
    'saved', v_saved,
    'counterpart', v_counterpart,
    'driver_profile', v_driver_profile
  );
end;
$$;
