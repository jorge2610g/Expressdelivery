-- Lightweight source of truth for the passenger offer screen.
-- It bypasses nested PostgREST/RLS joins while still validating that the
-- authenticated user owns the ride.
create or replace function public.passenger_pending_ride_offers(
  p_ride_request_id uuid
)
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

  if not exists (
    select 1
    from public.ride_requests r
    where r.id = p_ride_request_id
      and r.passenger_id = v_uid
  ) then
    raise exception 'Solicitud no disponible';
  end if;

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
          'city', dp.city
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
  into v_result
  from public.driver_offers o
  left join public.driver_profiles dp on dp.id = o.driver_id
  left join public.users u on u.id = o.driver_id
  where o.ride_request_id = p_ride_request_id
    and o.status = 'pending'
    and coalesce(o.expires_at, now() + interval '1 second') > now();

  return v_result;
end;
$$;

grant execute on function public.passenger_pending_ride_offers(uuid)
to authenticated;

alter table public.driver_offers replica identity full;
