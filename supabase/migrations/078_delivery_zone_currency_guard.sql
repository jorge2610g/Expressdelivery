-- Keep all delivery currencies authoritative to their operational zone.
create or replace function public.set_delivery_currency_from_zone()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_zone_id uuid;
  v_currency text;
begin
  if new.marketplace_order_id is not null then
    select o.zone_id into v_zone_id
    from public.marketplace_orders o
    where o.id=new.marketplace_order_id;
  end if;

  if v_zone_id is null
     and new.pickup_latitude is not null
     and new.pickup_longitude is not null then
    v_zone_id:=public.service_zone_id_for_point(
      new.pickup_latitude,new.pickup_longitude
    );
  end if;

  if v_zone_id is null and new.customer_id is not null then
    select last_zone_id into v_zone_id
    from public.users
    where id=new.customer_id;
  end if;

  if v_zone_id is not null then
    select currency_code into v_currency
    from public.service_zones
    where id=v_zone_id and active=true;

    if nullif(trim(coalesce(v_currency,'')),'') is not null then
      new.currency:=upper(trim(v_currency));
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_set_delivery_currency_from_zone
on public.delivery_requests;
create trigger trg_set_delivery_currency_from_zone
before insert or update of
  pickup_latitude,pickup_longitude,marketplace_order_id,customer_id
on public.delivery_requests
for each row execute function public.set_delivery_currency_from_zone();

revoke execute on function public.set_delivery_currency_from_zone()
from public,anon,authenticated;
