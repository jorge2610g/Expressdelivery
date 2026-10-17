create or replace function public.same_operational_scope(
  p_user_a uuid,
  p_user_b uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_group_a uuid;
  v_group_b uuid;
  v_member_enabled_a boolean;
  v_member_enabled_b boolean;
  v_group_active_a boolean;
  v_group_active_b boolean;
begin
  if p_user_a is null or p_user_b is null then
    return false;
  end if;

  select m.group_id, m.enabled, g.active
    into v_group_a, v_member_enabled_a, v_group_active_a
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_a
  limit 1;

  select m.group_id, m.enabled, g.active
    into v_group_b, v_member_enabled_b, v_group_active_b
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_b
  limit 1;

  if v_group_a is null and v_group_b is null then
    return true;
  end if;

  if v_group_a is null or v_group_b is null then
    return false;
  end if;

  return v_group_a = v_group_b
    and coalesce(v_member_enabled_a, false)
    and coalesce(v_member_enabled_b, false)
    and coalesce(v_group_active_a, false)
    and coalesce(v_group_active_b, false);
end;
$$;

create or replace function public.normalize_runtime_channel(p_channel text)
returns text
language sql
immutable
as $func$
  select case
    when lower(trim(coalesce(p_channel,'')))='preview' then 'preview'
    else 'production'
  end
$func$;

create or replace function public.is_active_audit_user(p_user_id uuid)
returns boolean
language sql
stable security definer
set search_path=public
as $func$
  select exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=p_user_id
      and m.enabled=true
      and g.active=true
  )
$func$;

create or replace function public.guard_request_runtime_channel()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user uuid;
  v_is_preview_user boolean := false;
begin
  new.channel := public.normalize_runtime_channel(new.channel);

  case tg_table_name
    when 'ride_requests' then
      v_user := nullif(to_jsonb(new)->>'passenger_id','')::uuid;
    when 'delivery_requests' then
      v_user := nullif(to_jsonb(new)->>'customer_id','')::uuid;
    else
      raise exception 'Tabla no soportada por guard_request_runtime_channel: %', tg_table_name;
  end case;

  v_is_preview_user := coalesce(public.is_active_audit_user(v_user), false);

  if new.channel = 'preview' and not v_is_preview_user then
    raise exception 'Preview requiere una cuenta QA/sandbox activa';
  end if;

  if new.channel = 'production' and v_is_preview_user then
    raise exception 'Una cuenta QA/Preview no puede crear datos de Producción';
  end if;

  return new;
end;
$function$;

create or replace function public.sync_trip_runtime_channel()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if new.ride_request_id is not null then
    select r.channel into new.channel
    from public.ride_requests r
    where r.id=new.ride_request_id;
  end if;
  new.channel:=public.normalize_runtime_channel(new.channel);
  return new;
end;
$$;

create or replace function public.select_ride_offer(p_offer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ride_id uuid;
  v_driver_id uuid;
  v_passenger_id uuid;
  v_fare numeric;
  v_trip_id uuid;
  v_pin text;
  v_driver_name text;
  v_amount text;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;

  update public.driver_offers
  set status = 'expired'
  where id = p_offer_id
    and status = 'pending'
    and expires_at is not null
    and expires_at <= now();

  select o.ride_request_id, o.driver_id, r.passenger_id, o.proposed_fare
    into v_ride_id, v_driver_id, v_passenger_id, v_fare
  from public.driver_offers o
  join public.ride_requests r on r.id = o.ride_request_id
  where o.id = p_offer_id
    and r.passenger_id = auth.uid()
    and o.status = 'pending'
    and (o.expires_at is null or o.expires_at > now())
    and r.status in ('searching','offers_received')
  for update of o, r;

  if v_ride_id is null then
    raise exception 'Oferta vencida o no disponible';
  end if;
  if v_driver_id = v_passenger_id then
    raise exception 'No puedes asignarte tu propia solicitud';
  end if;
  if not public.same_operational_scope(v_passenger_id, v_driver_id) then
    raise exception 'Oferta fuera de tu entorno operativo';
  end if;

  select nullif(trim(u.full_name), '') into v_driver_name
  from public.users u where u.id = v_driver_id;
  v_amount := trim(to_char(v_fare, 'FM999999990.00'));

  insert into public.notifications(user_id, title, body, type)
  select distinct
    o.driver_id,
    'Oferta no seleccionada',
    'Este viaje fue asignado a otro conductor.',
    'ride_offer_declined'
  from public.driver_offers o
  where o.ride_request_id = v_ride_id
    and o.status = 'pending'
    and o.id <> p_offer_id
    and o.driver_id <> v_driver_id
    and public.same_operational_scope(v_passenger_id, o.driver_id);

  update public.driver_offers
  set status = case when id = p_offer_id then 'selected' else 'declined' end
  where ride_request_id = v_ride_id and status = 'pending';

  update public.ride_requests
  set status = 'driver_selected', updated_at = now()
  where id = v_ride_id;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');

  insert into public.trips(
    ride_request_id, passenger_id, driver_id, status, final_fare,
    payment_status, boarding_pin
  )
  values(
    v_ride_id, v_passenger_id, v_driver_id, 'driver_arriving', v_fare,
    'pending', v_pin
  )
  returning id into v_trip_id;

  insert into public.trip_status_history(trip_id, status, changed_by)
  values(v_trip_id, 'driver_arriving', auth.uid());

  update public.driver_profiles
  set online_status = 'busy', updated_at = now()
  where id = v_driver_id;

  insert into public.notifications(user_id, title, body, type)
  values
    (
      v_driver_id,
      '¡Viaje confirmado!',
      'Tu oferta de Bs ' || v_amount ||
        ' fue aceptada. Ya estás en camino al punto de recogida.',
      'ride_assigned'
    ),
    (
      v_passenger_id,
      'Conductor confirmado',
      coalesce(v_driver_name, 'Tu conductor') ||
        ' fue asignado y ya va en camino. Sigue su llegada en el mapa.',
      'ride_assigned'
    );

  return v_trip_id;
end;
$$;

create or replace function public.select_ride_offer_v2(
  p_offer_id uuid,
  p_channel text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_offer_channel text;
  v_trip uuid;
begin
  select o.channel into v_offer_channel
  from public.driver_offers o
  where o.id=p_offer_id;

  if v_offer_channel is distinct from v_channel then
    raise exception 'Oferta fuera del entorno seleccionado';
  end if;

  perform set_config('app.runtime_channel',v_channel,true);
  v_trip:=public.select_ride_offer(p_offer_id);
  return v_trip;
end;
$$;

alter function public.normalize_runtime_channel(text)
  set search_path = public;
revoke all on function public.is_active_audit_user(uuid)
  from public, anon;
grant execute on function public.is_active_audit_user(uuid)
  to authenticated;
revoke all on function public.guard_request_runtime_channel()
  from public, anon;
revoke all on function public.sync_trip_runtime_channel()
  from public, anon;

revoke all on function public.guard_request_runtime_channel()
  from public, anon;



revoke all on function public.select_ride_offer_v2(uuid,text) from public,anon;
grant execute on function public.select_ride_offer_v2(uuid,text) to authenticated;
