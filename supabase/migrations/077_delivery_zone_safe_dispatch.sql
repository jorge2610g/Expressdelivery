-- Zone-safe Delivery dispatch for Marketplace Phase 2.

create or replace function public.delivery_request_matches_driver_zone(
  p_pickup_lat numeric,
  p_pickup_lng numeric,
  p_marketplace_order_id uuid,
  p_customer_id uuid,
  p_driver_id uuid
)
returns boolean
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_driver_zone uuid;
  v_request_zone uuid;
begin
  if p_driver_id is null then return false; end if;

  select zone_id into v_driver_zone
  from public.driver_profiles
  where id=p_driver_id;

  if v_driver_zone is null then return false; end if;

  if p_marketplace_order_id is not null then
    select zone_id into v_request_zone
    from public.marketplace_orders
    where id=p_marketplace_order_id;
  end if;

  if v_request_zone is null
     and p_pickup_lat is not null
     and p_pickup_lng is not null then
    v_request_zone:=public.service_zone_id_for_point(
      p_pickup_lat,p_pickup_lng
    );
  end if;

  if v_request_zone is null and p_customer_id is not null then
    select last_zone_id into v_request_zone
    from public.users
    where id=p_customer_id;
  end if;

  return v_request_zone is not null
    and v_request_zone=v_driver_zone;
end;
$function$;

revoke execute on function public.delivery_request_matches_driver_zone(
  numeric,numeric,uuid,uuid,uuid
) from public,anon;
grant execute on function public.delivery_request_matches_driver_zone(
  numeric,numeric,uuid,uuid,uuid
) to authenticated;

drop policy if exists deliveries_read_participants_or_available
on public.delivery_requests;
create policy deliveries_read_participants_or_available
on public.delivery_requests
for select
to authenticated
using (
  customer_id=(select auth.uid())
  or courier_id=(select auth.uid())
  or (
    status='searching'
    and courier_id is null
    and public.is_approved_online_driver((select auth.uid()))
    and public.same_operational_scope(
      customer_id,(select auth.uid())
    )
    and public.delivery_request_matches_driver_zone(
      pickup_latitude,pickup_longitude,
      marketplace_order_id,customer_id,(select auth.uid())
    )
  )
);

drop policy if exists deliveries_update_participants
on public.delivery_requests;
create policy deliveries_update_participants
on public.delivery_requests
for update
to authenticated
using (
  customer_id=(select auth.uid())
  or courier_id=(select auth.uid())
  or (
    courier_id is null
    and status='searching'
    and public.is_approved_online_driver((select auth.uid()))
    and public.same_operational_scope(
      customer_id,(select auth.uid())
    )
    and public.delivery_request_matches_driver_zone(
      pickup_latitude,pickup_longitude,
      marketplace_order_id,customer_id,(select auth.uid())
    )
  )
)
with check (
  (
    customer_id=(select auth.uid())
    and (
      courier_id is null
      or courier_id=(select auth.uid())
    )
  )
  or (
    courier_id=(select auth.uid())
    and public.same_operational_scope(
      customer_id,(select auth.uid())
    )
    and public.delivery_request_matches_driver_zone(
      pickup_latitude,pickup_longitude,
      marketplace_order_id,customer_id,(select auth.uid())
    )
  )
);

create or replace function public.available_deliveries_for_driver()
returns setof public.delivery_requests
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists(
    select 1
    from public.driver_profiles dp
    where dp.id=v_uid
      and dp.approval_status='approved'
      and dp.online_status='online'
  ) then
    return;
  end if;

  if exists(
    select 1 from public.trips t
    where t.driver_id=v_uid
      and t.status not in ('completed','cancelled')
  ) or exists(
    select 1 from public.delivery_requests d
    where d.courier_id=v_uid
      and d.status not in ('delivered','cancelled')
  ) then
    return;
  end if;

  return query
  select d.*
  from public.delivery_requests d
  where d.status='searching'
    and d.courier_id is null
    and public.same_operational_scope(d.customer_id,v_uid)
    and public.delivery_request_matches_driver_zone(
      d.pickup_latitude,d.pickup_longitude,
      d.marketplace_order_id,d.customer_id,v_uid
    )
  order by
    d.dispatch_priority desc,
    d.created_at asc
  limit 50;
end;
$function$;

revoke execute on function public.available_deliveries_for_driver()
from public,anon;
grant execute on function public.available_deliveries_for_driver()
to authenticated;

create or replace function public.claim_delivery(p_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_customer uuid;
  v_marketplace_order_id uuid;
  v_pickup_lat numeric;
  v_pickup_lng numeric;
  v_priority boolean:=false;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists(
    select 1
    from public.driver_profiles dp
    where dp.id=v_uid
      and dp.approval_status='approved'
      and dp.online_status='online'
  ) then
    raise exception 'Conductor no aprobado o fuera de línea';
  end if;

  if exists(
    select 1
    from public.trips t
    where t.driver_id=v_uid
      and t.status not in ('completed','cancelled')
  ) or exists(
    select 1
    from public.delivery_requests d
    where d.courier_id=v_uid
      and d.status not in ('delivered','cancelled')
  ) then
    raise exception 'Ya tienes un servicio activo';
  end if;

  select
    customer_id,marketplace_order_id,
    pickup_latitude,pickup_longitude,
    marketplace_priority
  into
    v_customer,v_marketplace_order_id,
    v_pickup_lat,v_pickup_lng,v_priority
  from public.delivery_requests
  where id=p_delivery_id
    and courier_id is null
    and status='searching'
  for update;

  if v_customer is null
     or not public.same_operational_scope(v_customer,v_uid)
     or not public.delivery_request_matches_driver_zone(
       v_pickup_lat,v_pickup_lng,
       v_marketplace_order_id,v_customer,v_uid
     ) then
    raise exception 'Delivery no disponible en tu zona';
  end if;

  update public.delivery_requests
  set courier_id=v_uid,status='accepted',updated_at=now()
  where id=p_delivery_id
    and customer_id=v_customer
    and courier_id is null
    and status='searching';

  if not found then
    raise exception 'Delivery no disponible';
  end if;

  insert into public.delivery_status_history(
    delivery_id,status,changed_by
  )
  values(p_delivery_id,'accepted',v_uid);

  update public.driver_profiles
  set online_status='busy',updated_at=now()
  where id=v_uid;

  if v_marketplace_order_id is not null then
    update public.marketplace_orders
    set
      assigned_driver_id=v_uid,
      status='driver_assigned',
      updated_at=now()
    where id=v_marketplace_order_id;
  end if;

  insert into public.notifications(user_id,title,body,type)
  values(
    v_customer,
    'Repartidor asignado',
    case
      when v_priority
        then 'Tu Envío Plus ya tiene repartidor.'
      else 'Tu pedido ya tiene repartidor.'
    end,
    'delivery_assigned'
  );
end;
$function$;

revoke execute on function public.claim_delivery(uuid)
from public,anon;
grant execute on function public.claim_delivery(uuid)
to authenticated;
