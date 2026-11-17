-- Send only the driver's live coordinates to the private counterpart channel.
-- This avoids exposing a full driver_profiles row through Postgres Changes.
create or replace function public.broadcast_driver_live_location()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, realtime
as $$
declare
  v_trip_id uuid;
begin
  if new.latitude is not distinct from old.latitude
     and new.longitude is not distinct from old.longitude
     and new.heading_degrees is not distinct from old.heading_degrees then
    return new;
  end if;

  for v_trip_id in
    select t.id
    from public.trips t
    where t.driver_id = new.id
      and t.status not in ('completed', 'cancelled')
  loop
    perform realtime.send(
      jsonb_build_object(
        'trip_id', v_trip_id,
        'driver_id', new.id,
        'latitude', new.latitude,
        'longitude', new.longitude,
        'heading_degrees', new.heading_degrees,
        'location_updated_at', new.location_updated_at
      ),
      'driver_location',
      'trip-location:' || v_trip_id::text,
      true
    );
  end loop;
  return new;
end;
$$;

revoke all on function public.broadcast_driver_live_location()
from public, anon, authenticated;

drop trigger if exists broadcast_driver_live_location
on public.driver_profiles;
create trigger broadcast_driver_live_location
after update of latitude, longitude, heading_degrees
on public.driver_profiles
for each row
execute function public.broadcast_driver_live_location();

create or replace function public.can_read_trip_live_location(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select auth.uid() is not null
    and public.is_account_active()
    and exists (
      select 1
      from public.trips t
      join public.account_runtime_bindings viewer_runtime
        on viewer_runtime.user_id = auth.uid()
       and viewer_runtime.environment = t.channel
      join public.account_runtime_bindings driver_runtime
        on driver_runtime.user_id = t.driver_id
       and driver_runtime.environment = t.channel
      where t.id = p_trip_id
        and t.status not in ('completed', 'cancelled')
        and (t.passenger_id = auth.uid() or t.driver_id = auth.uid())
    );
$$;

revoke all on function public.can_read_trip_live_location(uuid)
from public, anon;
grant execute on function public.can_read_trip_live_location(uuid)
to authenticated;

drop policy if exists trip_participants_receive_driver_location
on realtime.messages;
create policy trip_participants_receive_driver_location
on realtime.messages
for select
to authenticated
using (
  case
    when realtime.topic() ~
      '^trip-location:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then public.can_read_trip_live_location(
      split_part(realtime.topic(), ':', 2)::uuid
    )
    else false
  end
);
