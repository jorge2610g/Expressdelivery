-- Las notificaciones de chat no llevaban referencia al viaje o pedido, así que
-- notification_runtime_channel las dejaba siempre en «production». Para una cuenta de
-- Prueba el aviso salía por el canal equivocado y no llegaba a su teléfono (sus
-- dispositivos están registrados en «preview»). Se añade trip_id / delivery_id para
-- que el canal se tome del propio viaje o pedido.
create or replace function public.notify_service_message()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_recipient uuid;
  v_metadata jsonb := '{}'::jsonb;
begin
  if new.trip_id is not null then
    select case when t.passenger_id = new.sender_id then t.driver_id else t.passenger_id end
      into v_recipient
    from public.trips t
    where t.id = new.trip_id
      and new.sender_id in (t.passenger_id, t.driver_id);
    v_metadata := jsonb_build_object('trip_id', new.trip_id);
  elsif new.delivery_id is not null then
    select case when d.customer_id = new.sender_id then d.courier_id else d.customer_id end
      into v_recipient
    from public.delivery_requests d
    where d.id = new.delivery_id
      and new.sender_id in (d.customer_id, d.courier_id);
    v_metadata := jsonb_build_object('delivery_id', new.delivery_id);
  end if;

  if v_recipient is not null then
    insert into public.notifications (user_id, title, body, type, metadata)
    values (v_recipient, 'Nuevo mensaje', left(new.body, 160), 'service_message', v_metadata);
  end if;
  return new;
end;
$function$;
