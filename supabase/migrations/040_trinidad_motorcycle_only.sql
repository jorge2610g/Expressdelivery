-- Trinidad launch mode: motorcycles only until multizone vehicle catalog is enabled.
-- Keeps historical trips untouched while preventing new disabled ride categories.

update public.service_catalog
set enabled = false,
    passenger_visible = false,
    driver_visible = false
where service_key in ('economy', 'comfort', 'xl');

update public.service_catalog
set enabled = true,
    passenger_visible = true,
    driver_visible = true,
    vehicle_type = 'motorcycle'
where service_key = 'motorcycle';

-- Current registered active vehicles are treated as motorcycles during
-- the Trinidad-only launch stage.
update public.driver_vehicles
set vehicle_type = 'motorcycle',
    updated_at = now()
where vehicle_type is distinct from 'motorcycle';

-- Make current driver profiles unambiguous for map/RPC fallback logic.
update public.driver_profiles dp
set vehicle_summary = case
  when au.email like 'qa-load-driver-%@expressdelivery.pro'
    or au.email like 'qa-prod-load-driver-%@expressdelivery.pro'
    then 'QA Load Moto'
  when au.email = 'qa-driver@expressdelivery.pro'
    then 'QA Moto'
  when not exists (
    select 1
    from public.driver_vehicles dv
    where dv.driver_id = dp.id
      and dv.is_active = true
  )
    then 'Moto'
  else dp.vehicle_summary
end,
updated_at = now()
from auth.users au
where au.id = dp.id;

-- Existing active load-lab requests should immediately behave like Moto.
update public.ride_requests
set category = 'motorcycle',
    updated_at = now()
where pickup_address like '[LOADTEST:%'
  and status in ('searching', 'offers_received');

create or replace function public.enforce_enabled_ride_service()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.service_catalog c
    where c.service_key = new.category
      and c.enabled = true
      and c.passenger_visible = true
  ) then
    raise exception 'Servicio temporalmente no disponible';
  end if;

  return new;
end;
$$;

drop trigger if exists ride_requests_enforce_enabled_service
  on public.ride_requests;

create trigger ride_requests_enforce_enabled_service
before insert or update of category
on public.ride_requests
for each row
execute function public.enforce_enabled_ride_service();
