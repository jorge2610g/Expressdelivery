-- Formalize every current driver as motorcycle during the Trinidad-only stage.
insert into public.driver_vehicles (
  driver_id,
  vehicle_type,
  brand,
  model,
  is_active,
  updated_at
)
select
  dp.id,
  'motorcycle',
  'Express',
  case
    when au.email like 'qa-load-driver-%@expressdelivery.pro'
      or au.email like 'qa-prod-load-driver-%@expressdelivery.pro'
      then 'QA Moto'
    when au.email = 'qa-driver@expressdelivery.pro'
      then 'QA Moto'
    else 'Moto'
  end,
  true,
  now()
from public.driver_profiles dp
join auth.users au on au.id = dp.id
where not exists (
  select 1
  from public.driver_vehicles dv
  where dv.driver_id = dp.id
    and dv.is_active = true
);

update public.driver_vehicles
set vehicle_type = 'motorcycle',
    is_active = true,
    updated_at = now()
where driver_id in (select id from public.driver_profiles);
