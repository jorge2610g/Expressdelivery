-- SOS solo durante un servicio en curso.
-- Antes, raise_emergency aceptaba una alerta sin viaje ni delivery, y la pantalla
-- «Seguridad y SOS» del menú permitía dispararla desde cualquier cuenta. El panel
-- recibía alertas falsas de conductores y pasajeros que no estaban en servicio.
-- Ahora la alerta exige:
--   - un viaje no finalizado del que la cuenta sea pasajero o conductor, o
--   - un delivery no finalizado con repartidor asignado.
-- El resto de la lógica (estado del viaje, notificaciones y alertas al admin) no cambia.

begin;

create or replace function public.raise_emergency(
  p_trip_id uuid default null::uuid,
  p_delivery_id uuid default null::uuid,
  p_latitude numeric default null::numeric,
  p_longitude numeric default null::numeric
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_event_id uuid;
  v_counterpart uuid;
  v_status text;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if p_trip_id is not null and p_delivery_id is not null then
    raise exception 'La alerta solo puede pertenecer a un servicio';
  end if;

  if p_trip_id is null and p_delivery_id is null then
    raise exception 'El SOS solo está disponible durante un viaje o delivery en curso';
  end if;

  if p_trip_id is not null then
    select
      case
        when passenger_id = auth.uid() then driver_id
        when driver_id = auth.uid() then passenger_id
        else null
      end,
      status
    into v_counterpart, v_status
    from public.trips
    where id = p_trip_id
    for update;

    if v_counterpart is null then
      raise exception 'No perteneces a este viaje';
    end if;

    if v_status in ('completed','cancelled') then
      raise exception 'Este viaje ya finalizó';
    end if;

    update public.trips
    set status = 'emergency'
    where id = p_trip_id;

    insert into public.trip_status_history(trip_id, status, changed_by)
    values (p_trip_id, 'emergency', auth.uid());
  elsif p_delivery_id is not null then
    select
      case
        when customer_id = auth.uid() then courier_id
        when courier_id = auth.uid() then customer_id
        else null
      end,
      status
    into v_counterpart, v_status
    from public.delivery_requests
    where id = p_delivery_id;

    if v_status is null then
      raise exception 'Delivery no encontrado';
    end if;

    if auth.uid() <> (
      select customer_id
      from public.delivery_requests
      where id = p_delivery_id
    ) and (
      select courier_id
      from public.delivery_requests
      where id = p_delivery_id
    ) is distinct from auth.uid() then
      raise exception 'No perteneces a este delivery';
    end if;

    if v_status in ('delivered','cancelled') then
      raise exception 'Este delivery ya finalizó';
    end if;

    if (
      select courier_id
      from public.delivery_requests
      where id = p_delivery_id
    ) is null then
      raise exception 'El SOS del delivery solo está disponible cuando hay repartidor asignado';
    end if;
  end if;

  insert into public.emergency_events(
    user_id,
    trip_id,
    delivery_id,
    latitude,
    longitude,
    status
  )
  values (
    auth.uid(),
    p_trip_id,
    p_delivery_id,
    p_latitude,
    p_longitude,
    'active'
  )
  returning id into v_event_id;

  if v_counterpart is not null then
    insert into public.notifications(user_id, title, body, type)
    values (
      v_counterpart,
      'Alerta SOS',
      'La otra persona del servicio activó una alerta de emergencia.',
      'emergency'
    );
  end if;

  insert into public.notifications(user_id, title, body, type)
  select
    a.user_id,
    'Alerta SOS activa',
    'Un usuario activó una alerta de emergencia en Express.',
    'emergency_admin'
  from public.admin_users a
  where a.user_id <> auth.uid();

  return v_event_id;
end;
$function$;

commit;
