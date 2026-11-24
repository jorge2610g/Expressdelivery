-- Cuenta de restaurante y cuenta de pasajero con el mismo correo: cada entorno ve solo lo suyo.
-- 1) Historial del pasajero: no incluye los envíos que esa cuenta pidió como restaurante
--    («Solicitar repartidor»). El conductor que hizo el envío lo sigue viendo en el suyo.
-- 2) Calificaciones: no se pide calificar los envíos de restaurante (ni al conductor desde la
--    cuenta del restaurante, ni al restaurante desde el conductor): no contaminan la calificación
--    de pasajero de esa cuenta.
-- 3) Avisos: los de «nuevo pedido» dirigidos al local no llegan a la app de pasajero; el portal
--    del restaurante los avisa por su cuenta.
do $m$
declare
  v_def text; v_new text; v_name text;
begin
  for v_name in select unnest(array['my_current_country_trips', 'my_current_country_trips_v2']) loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = v_name;
    v_new := replace(v_def, '(t.driver_id=v_uid or t.passenger_id=v_uid)',
      '(t.driver_id=v_uid or (t.passenger_id=v_uid and not rr.merchant_courier))');
    if v_new = v_def then raise exception 'No se pudo parchear %', v_name; end if;
    execute v_new;
  end loop;

  select pg_get_functiondef(p.oid) into v_def from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'pending_rating_service';
  v_new := replace(v_def, E'    where t.status=''completed''\n      and v_user in (t.passenger_id,t.driver_id)',
    E'    where t.status=''completed''\n      and not coalesce(rr.merchant_courier,false)\n      and v_user in (t.passenger_id,t.driver_id)');
  if v_new = v_def then raise exception 'No se pudo parchear pending_rating_service'; end if;
  execute v_new;
end $m$;

create or replace function public.skip_merchant_courier_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_merchant boolean := false;
  v_has_ref boolean := (new.metadata ? 'ride_request_id') or (new.metadata ? 'trip_id');
begin
  -- Aviso de «nuevo pedido» para el local: lo atiende el portal del restaurante, no la app de
  -- pasajero de la misma cuenta. (El aviso al cliente sobre su pedido lleva «status» y sigue.)
  if new.type = 'marketplace_order' and (new.metadata ? 'merchant_id')
     and not (new.metadata ? 'status') then
    return null;
  end if;
  if new.type not in ('ride_request','ride_offer','ride_offer_sent','ride_offer_declined',
      'ride_assigned','ride_cancelled','trip_status','trip_completed','trip_cancelled',
      'passenger_on_way','service_message','rating') then
    return new;
  end if;
  begin
    if new.metadata ? 'ride_request_id' then
      select r.merchant_courier and r.passenger_id = new.user_id into v_merchant
        from public.ride_requests r where r.id = (new.metadata ->> 'ride_request_id')::uuid;
    elsif new.metadata ? 'trip_id' then
      select r.merchant_courier and r.passenger_id = new.user_id into v_merchant
        from public.trips t join public.ride_requests r on r.id = t.ride_request_id
       where t.id = (new.metadata ->> 'trip_id')::uuid;
    end if;
  exception when invalid_text_representation then
    v_merchant := false;
  end;
  if coalesce(v_merchant, false) then return null; end if;
  if v_has_ref then return new; end if;
  if exists (
       select 1 from public.ride_requests r
        where r.passenger_id = new.user_id and r.merchant_courier
          and ((r.status in ('searching', 'offers_received') and r.expires_at > now())
               or r.updated_at > now() - interval '3 minutes'
               or exists (select 1 from public.trips t
                           where t.ride_request_id = r.id
                             and (t.status not in ('completed', 'cancelled')
                                  or t.completed_at > now() - interval '3 minutes'))))
     and not exists (
       select 1 from public.ride_requests r
        where r.passenger_id = new.user_id and not r.merchant_courier
          and r.status in ('searching', 'offers_received') and r.expires_at > now())
     and not exists (
       select 1 from public.trips t join public.ride_requests r on r.id = t.ride_request_id
        where t.passenger_id = new.user_id and not r.merchant_courier
          and t.status not in ('completed', 'cancelled')) then
    return null;
  end if;
  return new;
end $$;
