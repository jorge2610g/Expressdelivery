-- Allow an assigned driver to keep reading the route data for their own trip.
-- This prevents pickup/destination addresses and coordinates from disappearing
-- after a passenger selects an offer.

drop policy if exists rides_read_available_for_drivers on public.ride_requests;

create policy rides_read_available_for_drivers
on public.ride_requests
for select
to authenticated
using (
  passenger_id = (select auth.uid())
  or (
    status in ('searching', 'offers_received')
    and public.is_approved_online_driver((select auth.uid()))
  )
  or exists (
    select 1
    from public.trips t
    where t.ride_request_id = ride_requests.id
      and t.driver_id = (select auth.uid())
  )
);

create index if not exists trips_ride_request_driver_idx
  on public.trips (ride_request_id, driver_id);
