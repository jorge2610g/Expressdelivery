-- Complemento de 20261124050100: las funciones SECURITY DEFINER con las que la app de pasajero
-- carga su estado (viaje abierto, ofertas, viaje activo) se saltan la RLS y seguían devolviendo
-- las solicitudes de repartidor creadas por restaurantes. Se excluyen aquí también.
do $m$
declare
  v_def text; v_new text; v_name text;
  v_required text[] := array['passenger_home_state_v2', 'passenger_live_offer_state_v2',
                             'passenger_active_trip_live_state_v2'];
begin
  for v_name in
    select unnest(array['passenger_home_state_v2', 'passenger_live_offer_state_v2',
                         'passenger_active_trip_live_state_v2', 'passenger_home_state',
                         'passenger_live_offer_state', 'passenger_active_trip_live_state'])
  loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = v_name limit 1;
    if v_def is null then continue; end if;
    v_new := v_def;
    -- viaje activo (home_state): trips sin alias
    v_new := replace(v_new,
      E'from public.trips\n  where passenger_id=v_uid\n',
      E'from public.trips\n  where passenger_id=v_uid\n    and not public.is_merchant_courier_ride(ride_request_id)\n');
    -- viaje abierto (home_state): ride_requests sin alias
    v_new := replace(v_new,
      E'from public.ride_requests\n    where passenger_id=v_uid\n',
      E'from public.ride_requests\n    where passenger_id=v_uid\n      and not merchant_courier\n');
    -- viaje abierto (live_offer_state): alias r
    v_new := replace(v_new,
      E'from public.ride_requests r\n  where r.passenger_id=v_uid\n',
      E'from public.ride_requests r\n  where r.passenger_id=v_uid\n    and not r.merchant_courier\n');
    -- viaje activo (active_trip_live_state): alias t y r
    v_new := replace(v_new,
      E'where t.passenger_id=v_uid\n',
      E'where t.passenger_id=v_uid\n    and not r.merchant_courier\n');
    if v_new = v_def then
      if v_name = any (v_required) then
        raise exception 'No se pudo parchear %', v_name;
      end if;
      continue;
    end if;
    execute v_new;
  end loop;
end $m$;
