-- «Solicitar repartidor»: los cobros en efectivo quedan guardados de forma estructurada para que la
-- app del conductor muestre lo correcto.
--  · Entregar y cobrar: el restaurante escribe el monto del PEDIDO; el repartidor cobra al cliente
--    pedido + delivery (ej. 15.000 + 2.500 = 17.500), paga el pedido al local al recoger y se queda
--    con el delivery. Si el cliente paga con un billete mayor, se indica el vuelto.
--  · Solo entregar: el cliente ya pagó al local. El repartidor cobra el delivery al local antes de
--    recoger y NO cobra nada al cliente.
alter table public.ride_requests
  add column if not exists merchant_service_type text
    check (merchant_service_type is null or merchant_service_type in ('collect', 'deliver_only')),
  add column if not exists merchant_order_amount numeric,
  add column if not exists merchant_change_for numeric;

create or replace function public.marketplace_merchant_request_courier(
  p_merchant_id uuid, p_channel text, p_customer_name text, p_customer_phone text,
  p_dest_address text, p_dest_lat numeric, p_dest_lng numeric, p_distance_km numeric,
  p_duration_min numeric, p_service_type text, p_collect_amount numeric, p_customer_payment text,
  p_change_for numeric, p_prep_minutes integer, p_notes text, p_sender_phone text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  m public.marketplace_merchants%rowtype;
  v_fee jsonb; v_amount numeric; v_currency text; v_cur text;
  v_details text; v_ride public.ride_requests%rowtype; v_pay_label text; v_total numeric;
  v_straight numeric; v_active integer; v_name text; v_phone text; v_sphone text;
  v_order numeric; v_change numeric;
begin
  perform public.marketplace_portal_role(p_merchant_id, p_channel);
  select * into m from public.marketplace_merchants where id = p_merchant_id and active;
  if m.id is null then raise exception 'Restaurante no disponible'; end if;
  if m.courier_mode not in ('courier', 'both') then
    raise exception 'Solicitar repartidor no está habilitado para tu restaurante';
  end if;
  v_name := left(trim(coalesce(p_customer_name, '')), 80);
  v_phone := trim(coalesce(p_customer_phone, ''));
  v_sphone := trim(coalesce(p_sender_phone, ''));
  if length(v_name) < 2 then raise exception 'Escribe el nombre del cliente'; end if;
  if v_phone !~ '^\+?[0-9 ()-]{6,20}$' then raise exception 'Teléfono del cliente no válido'; end if;
  if v_sphone !~ '^\+?[0-9 ()-]{6,20}$' then raise exception 'Teléfono del restaurante no válido'; end if;
  if length(trim(coalesce(p_dest_address, ''))) < 3 or p_dest_lat is null or p_dest_lng is null then
    raise exception 'Elige la dirección de entrega en el mapa';
  end if;
  if p_dest_lat not between -90 and 90 or p_dest_lng not between -180 and 180 then
    raise exception 'Ubicación de entrega no válida';
  end if;
  if p_service_type not in ('deliver_only', 'collect') then raise exception 'Tipo de servicio no válido'; end if;
  if p_customer_payment not in ('cash', 'card', 'other') then raise exception 'Forma de pago no válida'; end if;
  if p_prep_minutes is null or p_prep_minutes not between 0 and 120 then
    raise exception 'Tiempo de preparación no válido (0 a 120 minutos)';
  end if;
  if coalesce(p_distance_km, 0) <= 0 or p_distance_km > 80 then raise exception 'Ruta no válida'; end if;
  v_straight := public.geo_distance_km(m.latitude, m.longitude, p_dest_lat, p_dest_lng);
  if p_distance_km < v_straight * 0.9 then raise exception 'Ruta no válida'; end if;
  select count(*) into v_active from public.marketplace_courier_requests cr
    join public.ride_requests r on r.id = cr.ride_request_id
   where cr.merchant_id = p_merchant_id
     and r.status in ('searching', 'offers_received', 'driver_selected');
  if v_active >= 10 then
    raise exception 'Ya tienes 10 solicitudes en curso. Espera a que se completen.';
  end if;

  v_fee := public.marketplace_courier_fee_internal(
    p_merchant_id, p_channel, p_dest_lat, p_dest_lng, p_distance_km, p_duration_min);
  v_amount := (v_fee ->> 'fee')::numeric;
  v_currency := v_fee ->> 'currency';
  v_cur := public.express_push_currency_label(v_currency);
  v_pay_label := case p_customer_payment when 'cash' then 'Efectivo' when 'card' then 'Tarjeta' else 'Otro' end;

  if p_service_type = 'collect' then
    v_order := p_collect_amount;
    if coalesce(v_order, 0) <= 0 then raise exception 'Escribe el monto del pedido a cobrar'; end if;
    v_total := v_order + v_amount;
    v_change := null;
    if p_change_for is not null and p_change_for > 0 then
      if p_change_for < v_total then
        raise exception 'El cliente debe pagar con al menos % (pedido + delivery)',
          v_cur || trim(to_char(v_total, 'FM999999990.00'));
      end if;
      v_change := p_change_for;
    end if;
    v_details := 'ENTREGAR Y COBRAR (contra entrega)'
      || E'\nPaga al local al recoger: ' || v_cur || trim(to_char(v_order, 'FM999999990.00')) || ' (el pedido)'
      || E'\nCobra al cliente: ' || v_cur || trim(to_char(v_total, 'FM999999990.00'))
      || ' (pedido ' || v_cur || trim(to_char(v_order, 'FM999999990.00'))
      || ' + delivery ' || v_cur || trim(to_char(v_amount, 'FM999999990.00')) || ')'
      || E'\nTu delivery: ' || v_cur || trim(to_char(v_amount, 'FM999999990.00'))
      || E'\nForma de pago del cliente: ' || v_pay_label;
    if v_change is not null then
      v_details := v_details || E'\nEl cliente paga con ' || v_cur || trim(to_char(v_change, 'FM999999990.00'))
        || ' (devuélvele ' || v_cur || trim(to_char(v_change - v_total, 'FM999999990.00')) || ')';
    end if;
  else
    v_order := null;
    v_details := 'SOLO ENTREGAR (el cliente ya pagó el pedido al local)'
      || E'\nCobra el delivery al local ANTES de recoger el pedido: ' || v_cur || trim(to_char(v_amount, 'FM999999990.00'))
      || E'\nNO cobres nada al cliente: ya está pagado.';
  end if;
  v_details := v_details
    || E'\nCliente: ' || v_name || ' · ' || v_phone
    || E'\nPedido de: ' || m.name || ' · ' || v_sphone
    || E'\nEl pedido estará listo en ' || p_prep_minutes || ' min';
  if nullif(trim(coalesce(p_notes, '')), '') is not null then
    v_details := v_details || E'\nNota: ' || left(trim(p_notes), 400);
  end if;

  perform set_config('app.runtime_channel', p_channel, true);
  insert into public.ride_requests(
    passenger_id, channel, category, service_mode, parcel_kind,
    parcel_sender_name, parcel_sender_phone, parcel_recipient_name, parcel_recipient_phone, parcel_details,
    pickup_address, pickup_latitude, pickup_longitude,
    destination_address, destination_latitude, destination_longitude,
    route_distance_km, route_duration_minutes,
    proposed_fare, base_fare, currency, payment_method, status,
    pricing_mode, dispatch_style, expires_at, merchant_courier,
    merchant_service_type, merchant_order_amount, merchant_change_for)
  values (
    auth.uid(), p_channel, 'economy', 'parcel', 'moto',
    left(m.name, 80), v_sphone, v_name, v_phone, v_details,
    coalesce(nullif(trim(m.address), ''), m.name), m.latitude, m.longitude,
    left(trim(p_dest_address), 300), p_dest_lat, p_dest_lng,
    p_distance_km, greatest(round(coalesce(p_duration_min, 0))::int, 1),
    v_amount, v_amount, v_currency, 'cash', 'searching',
    'fixed', 'sequential', now() + interval '4 minutes', true,
    p_service_type, v_order, case when p_service_type = 'collect' then v_change end)
  returning * into v_ride;

  insert into public.marketplace_courier_requests(
    merchant_id, ride_request_id, created_by, channel, service_type, customer_name, customer_phone,
    destination_address, collect_amount, change_for, customer_payment, prep_minutes, notes,
    delivery_fee, currency)
  values (p_merchant_id, v_ride.id, auth.uid(), p_channel, p_service_type, v_name, v_phone,
    left(trim(p_dest_address), 300),
    case when p_service_type = 'collect' then v_order end,
    case when p_service_type = 'collect' then v_change end,
    p_customer_payment, p_prep_minutes, nullif(trim(coalesce(p_notes, '')), ''), v_amount, v_currency);

  return jsonb_build_object('ok', true, 'ride_request_id', v_ride.id, 'fee', v_amount,
    'currency', v_currency, 'collect_total', case when p_service_type = 'collect' then v_total end);
end $$;
revoke all on function public.marketplace_merchant_request_courier(uuid, text, text, text, text, numeric, numeric, numeric, numeric, text, numeric, text, numeric, integer, text, text) from public, anon;
grant execute on function public.marketplace_merchant_request_courier(uuid, text, text, text, text, numeric, numeric, numeric, numeric, text, numeric, text, numeric, integer, text, text) to authenticated;
