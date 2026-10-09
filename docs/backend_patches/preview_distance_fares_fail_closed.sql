-- REVIEWED candidate; verified on QA before considering Production.
-- Every byte of original Production function is retained except one early Preview rejection.
-- p_channel='production' semantics, signature, defaults and EXECUTE rights are unchanged.
CREATE OR REPLACE FUNCTION public.admin_distance_fare_steps_replace(p_zone_id uuid, p_service_key text, p_steps jsonb, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_step jsonb; v_km numeric; v_fare numeric;
  v_prev_km numeric:=0; v_prev_fare numeric:=0;
begin
 if auth.uid() is null or not public.is_admin()
  or p_channel not in ('preview','production')
  or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso no autorizado a tarifas';
 end if;
 -- A Preview request must never DELETE/INSERT into the real fare steps.
 if p_channel='preview' then
   raise exception 'Los escalones de Preview se guardan solamente en la configuración QA';
 end if;
 if not exists (select 1 from public.service_zones z where z.id=p_zone_id)
  or not exists(select 1 from public.zone_service_catalog z
    where z.zone_id=p_zone_id and z.service_key=p_service_key) then
    raise exception 'La zona o servicio no existe';
 end if;
 if p_steps is null or jsonb_typeof(p_steps)<>'array'
  or jsonb_array_length(p_steps)>100 then
    raise exception 'Ingresa una lista de hasta 100 escalones';
 end if;
 -- Validate before deleting old tiers, reject duplicate or decreasing levels.
 for v_step in select value from jsonb_array_elements(p_steps) loop
   if jsonb_typeof(v_step)<>'object'
      or (v_step->>'up_to_km') is null or (v_step->>'fare') is null then
     raise exception 'Escalón inválido';
   end if;
   begin
     v_km:=(v_step->>'up_to_km')::numeric;
     v_fare:=(v_step->>'fare')::numeric;
   exception when others then
     raise exception 'Distancia y tarifa deben ser numéricas';
   end;
   if v_km<=v_prev_km or v_fare<=0 or v_fare<v_prev_fare
     or v_km>10000 or v_fare>100000000 then
     raise exception 'Las distancias deben subir y el precio no puede bajar';
   end if;
   v_prev_km:=v_km; v_prev_fare:=v_fare;
 end loop;
 delete from public.zone_distance_fare_steps
   where zone_id=p_zone_id and service_key=p_service_key;
 for v_step in select value from jsonb_array_elements(p_steps) loop
   insert into public.zone_distance_fare_steps(zone_id,service_key,up_to_km,fare)
     values(p_zone_id,p_service_key,(v_step->>'up_to_km')::numeric,
       (v_step->>'fare')::numeric);
 end loop;
 return public.admin_distance_fare_steps_get(p_zone_id,p_service_key,p_channel);
end $function$;
