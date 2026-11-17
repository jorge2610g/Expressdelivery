-- Número del otro participante de un viaje activo (pasajero <-> conductor).
-- Solo lo recibe un participante del viaje, y solo mientras el viaje está activo.
create or replace function public.trip_counterpart_phone(p_trip_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_trip public.trips%rowtype;
  v_other uuid;
  v_name text;
  v_phone text;
begin
  if v_uid is null then raise exception 'No autorizado'; end if;
  select * into v_trip from public.trips where id = p_trip_id;
  if not found then raise exception 'Viaje no encontrado'; end if;
  if v_uid = v_trip.passenger_id then
    v_other := v_trip.driver_id;
  elsif v_uid = v_trip.driver_id then
    v_other := v_trip.passenger_id;
  else
    raise exception 'No eres participante de este viaje';
  end if;
  if v_trip.status not in ('driver_assigned','driver_arriving','driver_waiting','in_progress') then
    raise exception 'El viaje no está activo';
  end if;
  select u.full_name, u.phone into v_name, v_phone from public.users u where u.id = v_other;
  return jsonb_build_object(
    'name', coalesce(v_name, ''),
    'phone', nullif(trim(coalesce(v_phone, '')), '')
  );
end;
$$;

revoke all on function public.trip_counterpart_phone(uuid) from public, anon;
grant execute on function public.trip_counterpart_phone(uuid) to authenticated;
