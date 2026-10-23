-- Solo entorno local de prueba. Envuelve el RPC real y devuelve el resultado como texto.
create or replace function public.test_try_select(p_offer uuid, p_uid uuid)
returns text language plpgsql as $$
declare v_trip uuid;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  v_trip := public.select_ride_offer_v2(p_offer, 'preview');
  return 'OK ' || v_trip::text;
exception when others then
  return 'ERR ' || sqlerrm;
end $$;
