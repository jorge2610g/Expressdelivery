-- MANUAL ONLY: do not execute without explicit owner authorization.
-- Repairs profiles with a missing registered zone from their latest valid
-- express_manual identity verification. Run against Production only after
-- approval; it is intentionally not a migration.

select 'before' as checkpoint, count(*) as drivers_without_zone
from public.driver_profiles
where zone_id is null;

with latest_identity as (
  select distinct on (i.user_id)
    i.user_id,
    case when coalesce(i.result ->> 'zone_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then (i.result ->> 'zone_id')::uuid end as zone_id
  from public.identity_verifications i
  where i.provider = 'express_manual' and i.subject_role = 'driver'
  order by i.user_id, i.created_at desc
), repaired as (
  update public.driver_profiles p
  set zone_id = z.id,
      city = coalesce(z.city, z.name),
      updated_at = now()
  from latest_identity li
  join public.service_zones z on z.id = li.zone_id
  where p.id = li.user_id and p.zone_id is null
    and upper(z.country_code) = upper(p.country_code)
  returning p.id, z.id as zone_id, coalesce(z.city, z.name) as city
)
select * from repaired order by city, id;

select 'after' as checkpoint, count(*) as drivers_without_zone
from public.driver_profiles
where zone_id is null;
