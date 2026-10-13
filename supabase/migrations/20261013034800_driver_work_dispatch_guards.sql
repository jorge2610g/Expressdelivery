-- Guard all courier claims, including legacy RPC and direct row updates.
-- A delivery work permission is NEVER interchangeable with Taxi's approval.
create or replace function public.guard_driver_delivery_claim_permissions()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_service text;
  v_channel text;
begin
  if new.courier_id is null or old.courier_id is not null
     or new.courier_id is not distinct from old.courier_id then
    return new;
  end if;
  v_channel:=public.admin_user_runtime_environment(new.courier_id);
  v_service:=case when new.marketplace_order_id is null then 'parcel' else 'market' end;

  if v_channel is distinct from new.channel then
    raise exception 'El conductor no pertenece al entorno del envío';
  end if;
  if auth.uid() is distinct from new.courier_id and not public.is_admin() then
    raise exception 'No puedes asignar el envío a otro conductor';
  end if;
  if not public.driver_work_permission_allowed(new.courier_id,v_service,v_channel)
     or not public.driver_delivery_zone_enabled(new.courier_id,v_channel) then
    raise exception 'Servicio no aprobado para el conductor';
  end if;
  if not exists(
     select 1 from public.driver_profiles dp
     where dp.id=new.courier_id and dp.approval_status='approved'
       and dp.online_status='online'
       and dp.zone_id is not null
       and public.delivery_request_matches_driver_zone(
          new.pickup_latitude,new.pickup_longitude,
          new.marketplace_order_id,new.customer_id,new.courier_id)
  ) then
    raise exception 'Conductor no está disponible en esa zona';
  end if;
  if exists(select 1 from public.trips t
            where t.driver_id=new.courier_id
              and t.status not in ('completed','cancelled'))
     or exists(select 1 from public.delivery_requests d
            where d.courier_id=new.courier_id and d.id<>new.id
              and d.status not in ('delivered','cancelled')) then
    raise exception 'El conductor ya tiene un trabajo activo';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_driver_delivery_claim_permissions
  on public.delivery_requests;
create trigger trg_driver_delivery_claim_permissions
before update of courier_id on public.delivery_requests
for each row execute function public.guard_driver_delivery_claim_permissions();

-- Safely refine the existing list RPCs without losing their existing
-- distance, country, approval, preview and dispatch priority restrictions.
do $$
declare
  v_def text;
  v_marker text;
  v_guard text;
begin
  v_def:=pg_get_functiondef('public.available_deliveries_for_driver_v2(text)'::regprocedure);
  v_marker:='    and d.courier_id is null';
  v_guard:='    and public.driver_work_permission_allowed(v_uid,'
    ||chr(10)||'      case when d.marketplace_order_id is null then ''parcel'' else ''market'' end,v_channel)'
    ||chr(10)||'    and public.driver_delivery_zone_enabled(v_uid,v_channel)';
  if position(v_guard in v_def)=0 then
    if position(v_marker in v_def)=0 then raise exception 'Missing V2 dispatch marker'; end if;
    v_def:=replace(v_def,v_marker,v_marker||chr(10)||v_guard);
    execute v_def;
  end if;

  v_def:=pg_get_functiondef('public.available_deliveries_for_driver()'::regprocedure);
  v_guard:='    and public.driver_work_permission_allowed(v_uid,'
    ||chr(10)||'      case when d.marketplace_order_id is null then ''parcel'' else ''market'' end,'
    ||chr(10)||'      public.admin_user_runtime_environment(v_uid))'
    ||chr(10)||'    and public.driver_delivery_zone_enabled(v_uid,public.admin_user_runtime_environment(v_uid))';
  if position(v_guard in v_def)=0 then
    if position(v_marker in v_def)=0 then raise exception 'Missing legacy dispatch marker'; end if;
    v_def:=replace(v_def,v_marker,v_marker||chr(10)||v_guard);
    execute v_def;
  end if;

  v_def:=pg_get_functiondef('public.available_ride_requests_for_driver()'::regprocedure);
  v_marker:='  if not public.is_approved_online_driver(v_uid) then';
  v_guard:='  if not public.driver_work_permission_allowed('
    ||chr(10)||'    v_uid,''ride'',public.admin_user_runtime_environment(v_uid)) then'
    ||chr(10)||'    return ''[]''::jsonb;'
    ||chr(10)||'  end if;'
    ||chr(10);
  if position('public.driver_work_permission_allowed' in v_def)=0 then
    if position(v_marker in v_def)=0 then raise exception 'Missing ride dispatch marker'; end if;
    v_def:=replace(v_def,v_marker,v_guard||v_marker);
    execute v_def;
  end if;
end;
$$;
