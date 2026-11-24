-- «Solicitar repartidor» desde el portal de restaurantes.
-- El restaurante pide un repartidor para un cliente que le compró por teléfono o WhatsApp.
-- Se reutiliza el servicio de Envíos (moto) con precio fijo: el sistema pone la tarifa y el
-- primer repartidor que acepta se lleva el pedido. No hay liquidaciones ni comisión: el
-- restaurante y el repartidor se pagan entre ellos; las instrucciones viajan en el texto del
-- envío para que el repartidor las vea en la app que ya tiene.

alter table public.marketplace_merchants
  add column if not exists courier_mode text not null default 'menu'
    check (courier_mode in ('menu', 'courier', 'both')),
  add column if not exists courier_pricing text not null default 'zone'
    check (courier_pricing in ('zone', 'flat')),
  add column if not exists courier_flat_fare numeric
    check (courier_flat_fare is null or courier_flat_fare > 0);

alter table public.ride_requests
  add column if not exists merchant_courier boolean not null default false;

create table if not exists public.marketplace_courier_requests (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.marketplace_merchants(id) on delete cascade,
  ride_request_id uuid references public.ride_requests(id) on delete set null,
  created_by uuid not null,
  channel text not null check (channel in ('preview', 'production')),
  service_type text not null check (service_type in ('deliver_only', 'collect')),
  customer_name text not null,
  customer_phone text not null,
  destination_address text not null,
  collect_amount numeric,
  change_for numeric,
  customer_payment text not null default 'cash',
  prep_minutes integer not null default 15,
  notes text,
  delivery_fee numeric not null,
  currency text not null,
  created_at timestamptz not null default now()
);
create index if not exists marketplace_courier_requests_merchant_idx
  on public.marketplace_courier_requests(merchant_id, created_at desc);
alter table public.marketplace_courier_requests enable row level security;

-- El precio fijo de los Envíos se desactivaba siempre. Las solicitudes de restaurantes
-- (merchant_courier) conservan la tarifa y el despacho de precio fijo con que se crearon.
create or replace function public.apply_service_fixed_price()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_mode text; v_quote jsonb; v_increment numeric; v_fare numeric;
begin
  if new.merchant_courier then
    return new;
  end if;
  if new.service_mode = 'parcel' or new.zone_id is null or new.scheduled_for is not null then
    if new.pricing_mode = 'fixed' then new.pricing_mode := 'offer'; end if;
    return new;
  end if;
  select zs.price_mode into v_mode from public.zone_service_catalog zs where zs.zone_id = new.zone_id and zs.service_key = new.category;
  v_mode := coalesce(v_mode, 'offer');
  -- 'offer': siempre ofertas. 'both': precio fijo solo si el pasajero lo eligió. 'fixed': siempre fijo.
  if v_mode = 'offer' or (v_mode = 'both' and coalesce(new.pricing_mode,'offer') <> 'fixed') then
    new.pricing_mode := 'offer';
    return new;
  end if;
  if new.pickup_latitude is null or new.pickup_longitude is null or coalesce(new.route_distance_km, 0) <= 0 then
    raise exception 'Faltan los datos de la ruta para calcular el precio fijo';
  end if;
  v_quote := public.dynamic_pricing_quote_internal(new.category, new.route_distance_km, coalesce(new.route_duration_minutes, 0),
    new.pickup_latitude, new.pickup_longitude, new.channel, new.destination_latitude, new.destination_longitude, 'fixed');
  v_increment := public.fare_rounding_increment(coalesce(v_quote->>'currency', new.currency), new.channel);
  v_fare := public.fare_round_value(coalesce((v_quote->>'minimum_allowed_fare')::numeric, (v_quote->>'amount')::numeric), v_increment);
  if v_fare is null or v_fare <= 0 then raise exception 'No se pudo calcular el precio fijo'; end if;
  new.proposed_fare := v_fare; new.base_fare := v_fare; new.pricing_mode := 'fixed'; new.dispatch_style := 'sequential';
  new.currency := coalesce(v_quote->>'currency', new.currency); new.fare_rounding_increment := v_increment;
  new.demand_multiplier := coalesce((v_quote->>'demand_multiplier')::numeric, 1);
  new.demand_level := coalesce(v_quote->>'demand_level', 'normal');
  return new;
end; $function$;

-- Tarifa de la solicitud: la fija del restaurante, o la del sistema por distancia.
create or replace function public.marketplace_courier_fee_internal(
  p_merchant_id uuid, p_channel text, p_dest_lat numeric, p_dest_lng numeric,
  p_distance_km numeric, p_duration_min numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare m public.marketplace_merchants%rowtype; v_zone uuid; v_currency text;
  v_quote jsonb; v_increment numeric; v_fare numeric;
begin
  select * into m from public.marketplace_merchants where id = p_merchant_id;
  if m.id is null or m.latitude is null or m.longitude is null then
    raise exception 'Tu restaurante no tiene una ubicación guardada. Escríbenos desde Soporte para marcarla.';
  end if;
  v_zone := public.service_zone_id_for_point(m.latitude, m.longitude);
  if v_zone is null then
    raise exception 'Tu restaurante está fuera de una zona de servicio de Express.';
  end if;
  select z.currency_code into v_currency from public.service_zones z where z.id = v_zone;
  if m.courier_pricing = 'flat' and coalesce(m.courier_flat_fare, 0) > 0 then
    v_increment := public.fare_rounding_increment(v_currency, p_channel);
    return jsonb_build_object('fee', public.fare_round_value(m.courier_flat_fare, v_increment),
                              'currency', v_currency, 'pricing', 'flat');
  end if;
  if coalesce(p_distance_km, 0) <= 0 then
    raise exception 'Faltan los datos de la ruta para calcular el precio';
  end if;
  v_quote := public.dynamic_pricing_quote_internal('economy', p_distance_km, coalesce(p_duration_min, 0),
    m.latitude, m.longitude, p_channel, p_dest_lat, p_dest_lng, 'fixed');
  v_increment := public.fare_rounding_increment(coalesce(v_quote->>'currency', v_currency), p_channel);
  v_fare := public.fare_round_value(
    coalesce((v_quote->>'minimum_allowed_fare')::numeric, (v_quote->>'amount')::numeric), v_increment);
  if v_fare is null or v_fare <= 0 then raise exception 'No se pudo calcular el precio'; end if;
  return jsonb_build_object('fee', v_fare, 'currency', coalesce(v_quote->>'currency', v_currency),
                            'pricing', 'zone');
end $$;
revoke all on function public.marketplace_courier_fee_internal(uuid, text, numeric, numeric, numeric, numeric) from public, anon, authenticated;

create or replace function public.marketplace_merchant_courier_quote(
  p_merchant_id uuid, p_channel text, p_dest_lat numeric, p_dest_lng numeric,
  p_distance_km numeric, p_duration_min numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare m public.marketplace_merchants%rowtype;
begin
  perform public.marketplace_portal_role(p_merchant_id, p_channel);
  select * into m from public.marketplace_merchants where id = p_merchant_id;
  if m.courier_mode not in ('courier', 'both') then
    raise exception 'Solicitar repartidor no está habilitado para tu restaurante';
  end if;
  return public.marketplace_courier_fee_internal(
    p_merchant_id, p_channel, p_dest_lat, p_dest_lng, p_distance_km, p_duration_min);
end $$;
revoke all on function public.marketplace_merchant_courier_quote(uuid, text, numeric, numeric, numeric, numeric) from public, anon;
grant execute on function public.marketplace_merchant_courier_quote(uuid, text, numeric, numeric, numeric, numeric) to authenticated;

create or replace function public.marketplace_merchant_request_courier(
  p_merchant_id uuid, p_channel text,
  p_customer_name text, p_customer_phone text,
  p_dest_address text, p_dest_lat numeric, p_dest_lng numeric,
  p_distance_km numeric, p_duration_min numeric,
  p_service_type text, p_collect_amount numeric, p_customer_payment text,
  p_change_for numeric, p_prep_minutes integer, p_notes text, p_sender_phone text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  m public.marketplace_merchants%rowtype;
  v_fee jsonb; v_amount numeric; v_currency text; v_cur text;
  v_details text; v_ride public.ride_requests%rowtype; v_pay_label text; v_pay_local numeric;
  v_straight numeric; v_active integer; v_name text; v_phone text; v_sphone text;
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
  -- La ruta nunca puede ser mucho más corta que la línea recta entre los dos puntos.
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
    if coalesce(p_collect_amount, 0) <= 0 then raise exception 'Escribe el monto a cobrar'; end if;
    if p_collect_amount < v_amount then
      raise exception 'El monto a cobrar debe ser mayor que el delivery (%)', v_cur || trim(to_char(v_amount, 'FM999999990.00'));
    end if;
    v_pay_local := p_collect_amount - v_amount;
    v_details := 'ENTREGAR Y COBRAR (contra entrega)'
      || E'\nPaga al local: ' || v_cur || trim(to_char(v_pay_local, 'FM999999990.00'))
      || ' (pedido ' || v_cur || trim(to_char(p_collect_amount, 'FM999999990.00'))
      || ' menos tu delivery ' || v_cur || trim(to_char(v_amount, 'FM999999990.00')) || ')'
      || E'\nCobra al cliente: ' || v_cur || trim(to_char(p_collect_amount, 'FM999999990.00'))
      || E'\nForma de pago del cliente: ' || v_pay_label;
    if p_change_for is not null and p_change_for > 0 then
      v_details := v_details || E'\nEl cliente paga con ' || v_cur || trim(to_char(p_change_for, 'FM999999990.00'))
        || ' (cambio ' || v_cur || trim(to_char(greatest(p_change_for - p_collect_amount, 0), 'FM999999990.00')) || ')';
    end if;
  else
    v_details := 'SOLO ENTREGAR (el cliente ya pagó al local)'
      || E'\nEl local te paga el delivery: ' || v_cur || trim(to_char(v_amount, 'FM999999990.00'));
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
    pricing_mode, dispatch_style, expires_at, merchant_courier)
  values (
    auth.uid(), p_channel, 'economy', 'parcel', 'moto',
    left(m.name, 80), v_sphone, v_name, v_phone, v_details,
    coalesce(nullif(trim(m.address), ''), m.name), m.latitude, m.longitude,
    left(trim(p_dest_address), 300), p_dest_lat, p_dest_lng,
    p_distance_km, greatest(round(coalesce(p_duration_min, 0))::int, 1),
    v_amount, v_amount, v_currency, 'cash', 'searching',
    'fixed', 'sequential', now() + interval '4 minutes', true)
  returning * into v_ride;

  insert into public.marketplace_courier_requests(
    merchant_id, ride_request_id, created_by, channel, service_type, customer_name, customer_phone,
    destination_address, collect_amount, change_for, customer_payment, prep_minutes, notes,
    delivery_fee, currency)
  values (p_merchant_id, v_ride.id, auth.uid(), p_channel, p_service_type, v_name, v_phone,
    left(trim(p_dest_address), 300),
    case when p_service_type = 'collect' then p_collect_amount end,
    case when p_service_type = 'collect' then p_change_for end,
    p_customer_payment, p_prep_minutes, nullif(trim(coalesce(p_notes, '')), ''), v_amount, v_currency);

  return jsonb_build_object('ok', true, 'ride_request_id', v_ride.id, 'fee', v_amount, 'currency', v_currency);
end $$;
revoke all on function public.marketplace_merchant_request_courier(uuid, text, text, text, text, numeric, numeric, numeric, numeric, text, numeric, text, numeric, integer, text, text) from public, anon;
grant execute on function public.marketplace_merchant_request_courier(uuid, text, text, text, text, numeric, numeric, numeric, numeric, text, numeric, text, numeric, integer, text, text) to authenticated;

create or replace function public.marketplace_merchant_courier_requests(p_merchant_id uuid, p_channel text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  perform public.marketplace_portal_role(p_merchant_id, p_channel);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', cr.id, 'ride_request_id', cr.ride_request_id, 'created_at', cr.created_at,
      'service_type', cr.service_type, 'customer_name', cr.customer_name,
      'customer_phone', cr.customer_phone, 'destination_address', cr.destination_address,
      'collect_amount', cr.collect_amount, 'delivery_fee', cr.delivery_fee, 'currency', cr.currency,
      'prep_minutes', cr.prep_minutes,
      'status', r.status,
      'driver_name', (select nullif(trim(u.full_name), '') from public.trips t
                        join public.users u on u.id = t.driver_id
                       where t.ride_request_id = r.id order by t.created_at desc limit 1))
      order by cr.created_at desc), '[]'::jsonb)
    from (select * from public.marketplace_courier_requests
           where merchant_id = p_merchant_id order by created_at desc limit 50) cr
    left join public.ride_requests r on r.id = cr.ride_request_id);
end $$;
revoke all on function public.marketplace_merchant_courier_requests(uuid, text) from public, anon;
grant execute on function public.marketplace_merchant_courier_requests(uuid, text) to authenticated;

create or replace function public.marketplace_merchant_cancel_courier(
  p_merchant_id uuid, p_channel text, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_ride uuid; v_status text;
begin
  perform public.marketplace_portal_role(p_merchant_id, p_channel);
  select cr.ride_request_id into v_ride from public.marketplace_courier_requests cr
   where cr.id = p_request_id and cr.merchant_id = p_merchant_id;
  if v_ride is null then raise exception 'Solicitud no encontrada'; end if;
  select status into v_status from public.ride_requests where id = v_ride for update;
  if v_status not in ('searching', 'offers_received') then
    raise exception 'Esta solicitud ya tiene un repartidor o terminó. Contacta a soporte si necesitas cancelarla.';
  end if;
  update public.ride_requests
     set status = 'cancelled', cancellation_reason = 'Cancelado por el restaurante', updated_at = now()
   where id = v_ride;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.marketplace_merchant_cancel_courier(uuid, text, uuid) from public, anon;
grant execute on function public.marketplace_merchant_cancel_courier(uuid, text, uuid) to authenticated;

-- Configuración del administrador: qué ve el restaurante y cómo se calcula la tarifa.
create or replace function public.admin_marketplace_set_courier_settings(
  p_merchant_id uuid, p_mode text, p_pricing text, p_flat_fare numeric)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_row public.marketplace_merchants%rowtype;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_mode not in ('menu', 'courier', 'both') then raise exception 'Modo no válido'; end if;
  if p_pricing not in ('zone', 'flat') then raise exception 'Tipo de tarifa no válido'; end if;
  if p_pricing = 'flat' and coalesce(p_flat_fare, 0) <= 0 then
    raise exception 'Escribe la tarifa fija del restaurante';
  end if;
  update public.marketplace_merchants set
      courier_mode = p_mode,
      courier_pricing = p_pricing,
      courier_flat_fare = case when p_pricing = 'flat' then p_flat_fare end,
      -- «Solo repartidor» no aparece en la app de los clientes.
      production_visible = case when p_mode = 'courier' then false else production_visible end,
      preview_visible = case when p_mode = 'courier' then false else preview_visible end,
      updated_at = now()
   where id = p_merchant_id
   returning * into v_row;
  if v_row.id is null then raise exception 'Comercio no encontrado'; end if;
  return jsonb_build_object('ok', true, 'courier_mode', v_row.courier_mode,
    'courier_pricing', v_row.courier_pricing, 'courier_flat_fare', v_row.courier_flat_fare);
end $$;
revoke all on function public.admin_marketplace_set_courier_settings(uuid, text, text, numeric) from public, anon;
grant execute on function public.admin_marketplace_set_courier_settings(uuid, text, text, numeric) to authenticated;

-- El perfil del portal incluye la configuración de «Solicitar repartidor» y la ubicación.
create or replace function public.marketplace_merchant_profile(p_merchant_id uuid, p_channel text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare v_role text;
begin
  v_role := public.marketplace_portal_role(p_merchant_id, p_channel);
  return (select jsonb_build_object(
      'role', v_role,
      'id', m.id, 'name', m.name, 'description', m.description,
      'image_url', m.image_url, 'cover_image_url', m.cover_image_url,
      'address', m.address, 'category_key', m.category_key,
      'latitude', m.latitude, 'longitude', m.longitude,
      'minimum_order', m.minimum_order, 'delivery_fee', m.delivery_fee,
      'eta_min_minutes', m.eta_min_minutes, 'eta_max_minutes', m.eta_max_minutes,
      'transfer_instructions', m.transfer_instructions,
      'business_hours', m.business_hours, 'open_override', m.open_override,
      'courier_mode', m.courier_mode, 'courier_pricing', m.courier_pricing,
      'courier_flat_fare', m.courier_flat_fare,
      'currency', z.currency_code, 'timezone', z.timezone,
      'country_code', z.country_code,
      'rating', coalesce((select round(avg(r.rating)::numeric, 1)
                            from public.marketplace_order_reviews r
                           where r.merchant_id = m.id and r.channel = p_channel), m.rating),
      'review_count', (select count(*) from public.marketplace_order_reviews r
                        where r.merchant_id = m.id and r.channel = p_channel))
    from public.marketplace_merchants m
    left join public.service_zones z on z.id = m.zone_id
    where m.id = p_merchant_id);
end $$;
