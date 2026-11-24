-- Las solicitudes de «Solicitar repartidor» se crean con la cuenta del restaurante como pasajero.
-- Sus avisos de viaje (conductor confirmado, llegó, recogido, entregado, cancelado, mensajes…) no
-- deben llegar como push ni como aviso a la app de pasajero de esa misma cuenta: el restaurante ve
-- el estado en su portal. Los conductores reciben sus avisos como siempre.
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
  if new.type not in ('ride_request','ride_offer','ride_offer_sent','ride_offer_declined',
      'ride_assigned','ride_cancelled','trip_status','trip_completed','trip_cancelled',
      'passenger_on_way','service_message','rating') then
    return new;
  end if;
  -- 1) Con referencia al viaje o a la solicitud: se decide con exactitud.
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
  -- 2) Sin referencia: la cuenta tiene una solicitud de restaurante en curso o recién
  --    terminada y ningún viaje normal activo como pasajero.
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
revoke all on function public.skip_merchant_courier_notification() from public, anon, authenticated;

drop trigger if exists trg_a_skip_merchant_courier_notification on public.notifications;
create trigger trg_a_skip_merchant_courier_notification
  before insert on public.notifications
  for each row execute function public.skip_merchant_courier_notification();
