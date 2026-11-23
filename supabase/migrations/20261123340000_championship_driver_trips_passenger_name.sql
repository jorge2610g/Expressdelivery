-- La lista de viajes del conductor en el campeonato muestra el nombre del pasajero.
do $$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_driver_championship_driver_trips';
  if v_def is null then raise exception 'no existe'; end if;
  if position('passenger_name' in v_def) > 0 then return; end if;
  v_new := replace(v_def,
    '''payment_method'', r.payment_method, ''distance_km'', r.route_distance_km) as x',
    '''payment_method'', r.payment_method, ''distance_km'', r.route_distance_km, ''passenger_name'', coalesce((select nullif(trim(pu.full_name), '''') from public.users pu where pu.id = t.passenger_id), ''Pasajero'')) as x');
  if v_new = v_def then raise exception 'no se encontró el armado de cada viaje'; end if;
  execute v_new;
end $$;
