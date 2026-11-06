-- Detalle de una alerta SOS para el panel administrativo (solo lectura).
--
-- Autorización igual que admin_dashboard_state_v2 y admin_resolve_emergency_v2:
--   1. entorno permitido a la cuenta (admin_assert_environment);
--   2. registro de la alerta en el mismo entorno (admin_assert_target_environment);
--   3. módulo 'dashboard' para todos los roles y 'safety_sos' para operadores;
--   4. alcance de zona resuelto con admin_effective_zone_id, usando la misma
--      prioridad de zona que el listado: zona del viaje, zona del envío y
--      última zona del pasajero.
-- La función no escribe datos ni registra acciones.

create or replace function public.admin_emergency_detail_v1(
  p_emergency_id uuid,
  p_channel text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_channel text;
  v_role text;
  v_emergency public.emergency_events%rowtype;
  v_trip public.trips%rowtype;
  v_ride public.ride_requests%rowtype;
  v_delivery public.delivery_requests%rowtype;
  v_has_trip boolean := false;
  v_has_delivery boolean := false;
  v_channel_seen text;
  v_delivery_zone uuid;
  v_zone_id uuid;
  v_zone_name text;
  v_driver_id uuid;
  v_passenger jsonb;
  v_driver jsonb := null;
  v_trip_json jsonb := null;
  v_delivery_json jsonb := null;
begin
  if p_emergency_id is null then
    raise exception 'Emergencia requerida';
  end if;

  v_channel := public.admin_assert_environment(p_channel);

  select a.access_role
    into v_role
  from public.admin_users a
  join public.users u on u.id = a.user_id
  where a.user_id = auth.uid()
    and a.active = true
    and u.account_status = 'active'
  limit 1;

  if v_role is null then
    raise exception 'No autorizado';
  end if;

  perform public.admin_operator_assert_module('dashboard');
  if v_role = 'operator' then
    perform public.admin_operator_assert_module('safety_sos');
  end if;

  select * into v_emergency
  from public.emergency_events
  where id = p_emergency_id;

  if not found then
    raise exception 'Emergencia no encontrada';
  end if;

  perform public.admin_assert_target_environment(v_emergency.user_id, v_channel);

  if v_emergency.trip_id is not null then
    select * into v_trip
    from public.trips
    where id = v_emergency.trip_id;
    v_has_trip := found;
  end if;

  if v_has_trip then
    select * into v_ride
    from public.ride_requests
    where id = v_trip.ride_request_id;
  end if;

  if v_emergency.delivery_id is not null then
    select * into v_delivery
    from public.delivery_requests
    where id = v_emergency.delivery_id;
    v_has_delivery := found;
  end if;

  v_channel_seen := coalesce(
    case when v_has_trip then v_trip.channel end,
    case when v_has_delivery then v_delivery.channel end,
    v_channel
  );
  if v_channel_seen <> v_channel then
    raise exception 'Emergencia no encontrada';
  end if;

  if v_has_delivery then
    v_delivery_zone := public.service_zone_id_for_point(
      v_delivery.pickup_latitude::numeric,
      v_delivery.pickup_longitude::numeric
    );
  end if;

  select coalesce(
           case when v_has_trip then v_ride.zone_id end,
           v_delivery_zone,
           u.last_zone_id
         )
    into v_zone_id
  from public.users u
  where u.id = v_emergency.user_id;

  if v_zone_id is null then
    raise exception 'La alerta no tiene zona asignada';
  end if;

  -- Lanza error si el operador o monitor no pertenece a la zona de la alerta.
  perform public.admin_effective_zone_id(v_zone_id);

  select z.name
    into v_zone_name
  from public.service_zones z
  where z.id = v_zone_id;

  select jsonb_build_object(
           'id', u.id,
           'name', u.full_name,
           'phone', u.phone
         )
    into v_passenger
  from public.users u
  where u.id = v_emergency.user_id;

  v_driver_id := coalesce(
    case when v_has_trip then v_trip.driver_id end,
    case when v_has_delivery then v_delivery.courier_id end
  );

  if v_driver_id is not null then
    select jsonb_build_object(
             'id', du.id,
             'name', du.full_name,
             'phone', du.phone,
             'vehicle', coalesce(
               nullif(trim(concat_ws(' ', dv.brand, dv.model)), ''),
               dp.vehicle_summary
             ),
             'plate', dv.plate
           )
      into v_driver
    from public.users du
    left join public.driver_profiles dp on dp.id = du.id
    left join lateral (
      select vh.brand, vh.model, vh.plate
      from public.driver_vehicles vh
      where vh.driver_id = du.id
      order by vh.is_active desc, vh.updated_at desc
      limit 1
    ) dv on true
    where du.id = v_driver_id;
  end if;

  if v_has_trip then
    v_trip_json := jsonb_build_object(
      'id', v_trip.id,
      'status', v_trip.status,
      'category', v_ride.category,
      'origin', v_ride.pickup_address,
      'destination', v_ride.destination_address,
      'final_fare', v_trip.final_fare,
      'currency', v_ride.currency,
      'created_at', v_trip.created_at
    );
  end if;

  if v_has_delivery then
    v_delivery_json := jsonb_build_object(
      'id', v_delivery.id,
      'status', v_delivery.status,
      'origin', v_delivery.pickup_address,
      'destination', v_delivery.dropoff_address,
      'fare', v_delivery.proposed_fare,
      'currency', v_delivery.currency,
      'package_type', v_delivery.package_type,
      'created_at', v_delivery.created_at
    );
  end if;

  return jsonb_build_object(
    'emergency', jsonb_build_object(
      'id', v_emergency.id,
      'status', v_emergency.status,
      'created_at', v_emergency.created_at,
      'latitude', v_emergency.latitude,
      'longitude', v_emergency.longitude,
      'trip_id', v_emergency.trip_id,
      'delivery_id', v_emergency.delivery_id,
      'zone_id', v_zone_id,
      'zone_name', v_zone_name,
      'channel', v_channel
    ),
    'passenger', v_passenger,
    'driver', v_driver,
    'trip', v_trip_json,
    'delivery', v_delivery_json
  );
end;
$$;

revoke execute on function public.admin_emergency_detail_v1(uuid, text) from public, anon;
grant execute on function public.admin_emergency_detail_v1(uuid, text) to authenticated;
