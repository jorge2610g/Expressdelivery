insert into public.fare_rules(
  scope_type,service_key,zone_id,base_fare,per_km,per_minute,
  minimum_fare,surge_multiplier,commission_percent,active,created_at,updated_at
)
select
  'zone_service','motorcycle',fr.zone_id,fr.base_fare,fr.per_km,fr.per_minute,
  fr.minimum_fare,fr.surge_multiplier,fr.commission_percent,true,now(),now()
from public.fare_rules fr
join public.service_zones z on z.id=fr.zone_id
where z.zone_key='trinidad'
  and fr.service_key='economy'
  and fr.active=true
  and not exists(
    select 1 from public.fare_rules existing
    where existing.zone_id=fr.zone_id
      and existing.service_key='motorcycle'
      and existing.active=true
  )
limit 1;
