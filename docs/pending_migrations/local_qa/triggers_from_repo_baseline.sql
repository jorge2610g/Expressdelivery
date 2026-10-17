drop trigger if exists trg_guard_ride_request_runtime_channel
on public.ride_requests;
create trigger trg_guard_ride_request_runtime_channel
before insert or update of channel,passenger_id
on public.ride_requests
for each row execute function public.guard_request_runtime_channel();
drop trigger if exists trg_sync_trip_runtime_channel on public.trips;
create trigger trg_sync_trip_runtime_channel
before insert or update of ride_request_id
on public.trips
for each row execute function public.sync_trip_runtime_channel();
