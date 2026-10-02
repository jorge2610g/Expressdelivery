-- Prevent manual admin dispatch from crossing production and audit sandboxes.

create or replace function public.admin_assign_ride(
  p_ride_request_id uuid,
  p_driver_id uuid,
  p_final_fare numeric default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_passenger_id uuid;
  v_fare numeric;
  v_trip_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  if not exists (
    select 1 from public.driver_profiles dp
    join public.users u on u.id=dp.id
    where dp.id=p_driver_id
      and dp.approval_status='approved'
      and u.account_status='active'
      and dp.online_status='online'
  ) then
    raise exception 'Conductor no disponible';
  end if;

  if exists (
    select 1 from public.trips t
    where t.driver_id=p_driver_id
      and t.status not in ('completed','cancelled')
  ) or exists (
    select 1 from public.delivery_requests d
    where d.courier_id=p_driver_id
      and d.status not in ('delivered','cancelled')
  ) then
    raise exception 'El conductor ya tiene un servicio activo';
  end if;

  select r.passenger_id, coalesce(p_final_fare,r.proposed_fare)
    into v_passenger_id,v_fare
  from public.ride_requests r
  where r.id=p_ride_request_id
    and r.status in ('searching','offers_received')
  for update;

  if v_passenger_id is null then raise exception 'Solicitud no disponible'; end if;

  if not public.same_operational_scope(v_passenger_id,p_driver_id) then
    raise exception 'No se puede asignar un viaje entre producción y auditoría';
  end if;

  update public.driver_offers
  set status=case when driver_id=p_driver_id then 'selected' else 'declined' end
  where ride_request_id=p_ride_request_id and status='pending';

  update public.ride_requests
  set status='driver_selected', updated_at=now()
  where id=p_ride_request_id;

  insert into public.trips(
    ride_request_id, passenger_id, driver_id, status, final_fare, payment_status
  )
  values(
    p_ride_request_id, v_passenger_id, p_driver_id,
    'driver_assigned', v_fare, 'pending'
  )
  returning id into v_trip_id;

  insert into public.trip_status_history(trip_id,status,changed_by)
  values(v_trip_id,'driver_assigned',auth.uid());

  update public.driver_profiles
  set online_status='busy', updated_at=now()
  where id=p_driver_id;

  insert into public.notifications(user_id,title,body,type)
  values
    (p_driver_id,'Viaje asignado','El administrador te asignó un viaje.','ride_assigned'),
    (v_passenger_id,'Conductor asignado','Express asignó un conductor a tu viaje.','ride_assigned');

  perform public.admin_log_action(
    'manual_assign',
    'ride_request',
    p_ride_request_id::text,
    jsonb_build_object(
      'driver_id',p_driver_id,
      'trip_id',v_trip_id,
      'final_fare',v_fare
    )
  );

  return v_trip_id;
end;
$$;

create or replace function public.admin_assign_delivery(
  p_delivery_id uuid,
  p_driver_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_customer_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  if not exists (
    select 1 from public.driver_profiles dp
    join public.users u on u.id=dp.id
    where dp.id=p_driver_id
      and dp.approval_status='approved'
      and u.account_status='active'
      and dp.online_status='online'
  ) then
    raise exception 'Conductor no disponible';
  end if;

  if exists (
    select 1 from public.trips t
    where t.driver_id=p_driver_id
      and t.status not in ('completed','cancelled')
  ) or exists (
    select 1 from public.delivery_requests d
    where d.courier_id=p_driver_id
      and d.status not in ('delivered','cancelled')
  ) then
    raise exception 'El conductor ya tiene un servicio activo';
  end if;

  select customer_id into v_customer_id
  from public.delivery_requests
  where id=p_delivery_id
    and status='searching'
    and courier_id is null
  for update;

  if v_customer_id is null then raise exception 'Delivery no disponible'; end if;

  if not public.same_operational_scope(v_customer_id,p_driver_id) then
    raise exception 'No se puede asignar un delivery entre producción y auditoría';
  end if;

  update public.delivery_requests
  set courier_id=p_driver_id, status='accepted', updated_at=now()
  where id=p_delivery_id;

  insert into public.delivery_status_history(delivery_id,status,changed_by)
  values(p_delivery_id,'accepted',auth.uid());

  update public.driver_profiles
  set online_status='busy', updated_at=now()
  where id=p_driver_id;

  insert into public.notifications(user_id,title,body,type)
  values
    (p_driver_id,'Delivery asignado','El administrador te asignó un delivery.','delivery_assigned'),
    (v_customer_id,'Repartidor asignado','Express asignó un repartidor a tu delivery.','delivery_assigned');

  perform public.admin_log_action(
    'manual_assign',
    'delivery',
    p_delivery_id::text,
    jsonb_build_object('driver_id',p_driver_id)
  );
end;
$$;
