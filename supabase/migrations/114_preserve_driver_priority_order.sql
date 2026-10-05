-- Preserve v2 driver priority order while v3 filters accepted payment methods.

create or replace function public.available_ride_requests_for_driver_v3(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_base jsonb;
  v_accepted text[];
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists(
    select 1
    from public.driver_profiles d
    join public.service_zones z on z.id=d.zone_id and z.active=true
    join public.service_countries c
      on c.country_code=upper(coalesce(z.country_code,''))
     and c.active=true
    where d.id=v_uid
      and d.approval_status='approved'
      and d.online_status='online'
      and d.latitude is not null
      and d.longitude is not null
      and public.service_zone_id_for_point(
        d.latitude::numeric,d.longitude::numeric
      )=d.zone_id
  ) then
    return '[]'::jsonb;
  end if;

  v_base:=public.available_ride_requests_for_driver_v2(p_channel);

  select d.accepted_payment_methods
  into v_accepted
  from public.driver_profiles d
  where d.id=v_uid;

  if v_accepted is null or cardinality(v_accepted)=0 then
    return coalesce(v_base,'[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(x.item order by x.ord),'[]'::jsonb)
  into v_result
  from jsonb_array_elements(coalesce(v_base,'[]'::jsonb))
       with ordinality as x(item,ord)
  where x.item->>'payment_method'=any(v_accepted);

  return coalesce(v_result,'[]'::jsonb);
end;
$$;
