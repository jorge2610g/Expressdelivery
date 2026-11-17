-- Cupón con precio fijo: aceptación directa, descuento que cuadra y billetera por canal.
--
-- 1. Billetera: ensure_country_wallet_v2 y my_country_wallet_transactions_v2 usan el canal
--    del usuario (preview o production). Antes siempre leían producción, así que el
--    ajuste de cupón de una cuenta de prueba no aparecía y el saldo se veía en cero.
-- 2. Descuento: se calcula como tarifa original menos el precio final ya redondeado al
--    incremento de la zona. Así el pasajero paga el precio final y el conductor recibe
--    exactamente la diferencia (antes podía descuadrar por centavos).
-- 3. Precio fijo: driver_accept_fixed_price_ride_v1 crea el viaje al aceptar el conductor.
--    No pasa por oferta ni por elección del pasajero.

begin;

-- 1a. Saldo de billetera por canal -------------------------------------------------

create or replace function public.ensure_country_wallet_v2(p_channel text default 'production')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid:=auth.uid();
  v_context jsonb;
  v_country text;
  v_currency text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_wallet public.wallet_country_accounts%rowtype;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_context:=public.current_operating_context();
  v_country:=v_context->>'country_code';
  v_currency:=upper(coalesce(v_context->>'currency_code',''));

  if nullif(v_country,'') is null or nullif(v_currency,'') is null then
    raise exception 'No se pudo determinar país y moneda de la zona actual';
  end if;

  insert into public.wallet_country_accounts(
    user_id,country_code,channel,currency,balance
  )
  values(v_uid,v_country,v_channel,v_currency,0)
  on conflict(user_id,country_code,channel) do update set
    currency=excluded.currency,
    updated_at=case
      when public.wallet_country_accounts.currency is distinct from excluded.currency
      then now()
      else public.wallet_country_accounts.updated_at
    end;

  select * into v_wallet
  from public.wallet_country_accounts
  where user_id=v_uid
    and country_code=v_country
    and channel=v_channel;

  return to_jsonb(v_wallet)||jsonb_build_object(
    'country',v_context->>'country',
    'zone_id',v_context->>'zone_id',
    'zone_key',v_context->>'zone_key',
    'zone_name',v_context->>'zone_name'
  );
end;
$$;

create or replace function public.my_country_wallet_transactions_v2(p_channel text default 'production')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';

  return (
    select coalesce(
      jsonb_agg(to_jsonb(wt) order by wt.created_at desc),
      '[]'::jsonb
    )
    from public.wallet_transactions wt
    where wt.user_id=v_uid
      and wt.country_code=v_country
      and wt.channel=v_channel
  );
end;
$$;

-- 2a. Precio fijo al crear la solicitud: descuento = original − precio final redondeado.

create or replace function public.apply_benefit_coupon_fixed_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_zone_id uuid;
  v_currency text;
  v_program public.benefit_programs%rowtype;
  v_coupon public.benefit_user_coupons%rowtype;
  v_config jsonb;
  v_orig numeric(12,2);
  v_discount numeric(12,2) := 0;
  v_final numeric(12,2);
  v_inc numeric;
begin
  if new.benefit_coupon_code is null then return new; end if;
  if new.service_mode = 'parcel' or coalesce(new.payment_method, '') not in ('cash', 'driver_qr') then
    return new;
  end if;

  v_zone_id := coalesce(
    new.zone_id,
    public.service_zone_id_for_point(new.pickup_latitude, new.pickup_longitude)
  );
  if v_zone_id is null then return new; end if;

  select z.currency_code into v_currency
  from public.service_zones z
  where z.id = v_zone_id;

  v_orig := round(greatest(coalesce(new.proposed_fare, 0), 0), 2);

  select * into v_program
  from public.benefit_programs p
  where p.channel = new.channel and p.zone_id = v_zone_id
    and p.program_type = 'coupon' and p.state = 'active'
    and upper(coalesce(p.config->>'code', '')) = new.benefit_coupon_code
    and (p.starts_at is null or p.starts_at <= now())
    and (p.ends_at is null or p.ends_at > now())
  limit 1;

  if found then
    v_config := v_program.config;
    if v_config->>'discount_type' = 'percent' then
      v_discount := round(v_orig * coalesce((v_config->>'value')::numeric, 0) / 100, 2);
    else
      v_discount := round(coalesce((v_config->>'value')::numeric, 0), 2);
    end if;
    if nullif(v_config->>'max_discount', '') is not null then
      v_discount := least(v_discount, (v_config->>'max_discount')::numeric);
    end if;
  else
    select * into v_coupon
    from public.benefit_user_coupons c
    where c.code = new.benefit_coupon_code and c.user_id = new.passenger_id
      and c.zone_id = v_zone_id and c.channel = new.channel
      and c.state = 'available' and c.expires_at > now()
    limit 1;
    -- Si no existe o no es válido, la reserva posterior lo rechaza con su mensaje.
    if not found then return new; end if;
    if v_coupon.discount_type = 'percent' then
      v_discount := round(v_orig * v_coupon.value / 100, 2);
    else
      v_discount := round(v_coupon.value, 2);
    end if;
    if v_coupon.max_discount is not null then
      v_discount := least(v_discount, v_coupon.max_discount);
    end if;
  end if;

  v_discount := least(greatest(v_discount, 0), v_orig);
  v_inc := public.fare_rounding_increment(coalesce(v_currency, new.currency, 'BOB'), new.channel);
  v_final := public.fare_round_value(greatest(v_orig - v_discount, 0), v_inc);
  -- El descuento es lo que realmente se resta del precio final que verá el conductor.
  v_discount := v_orig - v_final;
  if v_discount <= 0 then return new; end if;

  new.zone_id := v_zone_id;
  new.benefit_original_fare := v_orig;
  new.benefit_discount_amount := v_discount;
  new.proposed_fare := v_final;
  new.base_fare := v_final;
  new.pricing_mode := 'fixed';
  return new;
end $$;

-- 2b. Validación previa del cupón: mismo cálculo que la solicitud.

create or replace function public.validate_benefit_coupon(
  p_code text,
  p_channel text,
  p_lat numeric,
  p_lng numeric,
  p_category text,
  p_fare numeric,
  p_payment_method text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_runtime jsonb;
  v_zone uuid;
  v_currency text;
  v_code text:=upper(trim(coalesce(p_code,'')));
  v_fare numeric:=round(greatest(coalesce(p_fare,0),0),2);
  v_program public.benefit_programs%rowtype;
  v_coupon public.benefit_user_coupons%rowtype;
  v_config jsonb;
  v_discount numeric:=0;
  v_final numeric;
  v_has_trips boolean;
  v_max_total integer;
  v_per_user integer;
  v_used_total integer;
  v_used_user integer;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if p_channel not in ('preview','production') then
    raise exception 'Entorno de datos no autorizado';
  end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false
     or (v_runtime->>'environment') is distinct from p_channel then
    raise exception 'Entorno de datos no autorizado';
  end if;

  if v_code='' then
    return jsonb_build_object('valid',false,'message','Escribe un código de cupón');
  end if;
  if coalesce(p_payment_method,'') not in ('cash','driver_qr') then
    return jsonb_build_object('valid',false,'message','Los cupones solo se aplican a pago en efectivo o QR del conductor');
  end if;
  v_zone:=public.service_zone_id_for_point(p_lat,p_lng);
  if v_zone is null then
    return jsonb_build_object('valid',false,'message','Los cupones no están disponibles en tu ubicación');
  end if;
  select z.currency_code into v_currency from public.service_zones z where z.id=v_zone;

  select * into v_program from public.benefit_programs p
  where p.channel=p_channel and p.zone_id=v_zone
    and p.program_type='coupon' and p.state='active'
    and upper(coalesce(p.config->>'code',''))=v_code
    and (p.starts_at is null or p.starts_at<=now())
    and (p.ends_at is null or p.ends_at>now())
  limit 1;

  if found then
    v_config:=v_program.config;
    if coalesce(v_config->>'audience','passengers') not in ('passengers','clients') then
      return jsonb_build_object('valid',false,'message','Este cupón no aplica a pasajeros');
    end if;
    if coalesce(v_config->>'service_mode','transport') not in ('transport','taxi') then
      return jsonb_build_object('valid',false,'message','Este cupón solo aplica a viajes de transporte');
    end if;
    if coalesce(v_config->>'service_type','all') not in ('all',coalesce(p_category,''))
       and not (v_config->>'service_type'='moto' and coalesce(p_category,'') in ('motorcycle','moto')) then
      return jsonb_build_object('valid',false,'message','Este cupón no aplica a esta categoría de vehículo');
    end if;
    if v_fare < coalesce(nullif(v_config->>'min_fare','')::numeric,0) then
      return jsonb_build_object('valid',false,'message','La tarifa es menor al mínimo de este cupón');
    end if;
    if v_config->>'discount_type' not in ('fixed','percent')
       or coalesce(nullif(v_config->>'value','')::numeric,0)<=0 then
      return jsonb_build_object('valid',false,'message','Este cupón no tiene un descuento válido');
    end if;

    v_has_trips:=exists(
      select 1 from public.trips t where t.passenger_id=v_uid
        and t.channel=p_channel and t.status='completed' and t.payment_status='paid');
    if coalesce((v_config->>'first_ride_only')::boolean,false) then
      if v_has_trips then
        return jsonb_build_object('valid',false,'message','Este cupón es válido solo para tu primer viaje');
      end if;
      if exists(select 1 from public.benefit_coupon_reservations r
        where r.program_id=v_program.id and r.user_id=v_uid
          and r.state in ('reserved','redeemed')) then
        return jsonb_build_object('valid',false,'message','Ya tienes un viaje con este cupón pendiente o usado');
      end if;
    end if;
    if coalesce(v_config->>'target_audience','all')='new' and v_has_trips then
      return jsonb_build_object('valid',false,'message','Este cupón es solo para usuarios nuevos');
    end if;
    if coalesce(v_config->>'target_audience','all')='returning' and not v_has_trips then
      return jsonb_build_object('valid',false,'message','Este cupón es para usuarios frecuentes');
    end if;

    v_max_total:=nullif(v_config->>'max_total_uses','')::integer;
    v_per_user:=nullif(v_config->>'uses_per_user','')::integer;
    select count(*) into v_used_total from public.benefit_coupon_reservations r
      where r.program_id=v_program.id and r.channel=p_channel and r.state in ('reserved','redeemed');
    select count(*) into v_used_user from public.benefit_coupon_reservations r
      where r.program_id=v_program.id and r.user_id=v_uid
        and r.channel=p_channel and r.state in ('reserved','redeemed');
    if v_max_total is not null and v_used_total>=v_max_total then
      return jsonb_build_object('valid',false,'message','Este cupón ya alcanzó su límite de usos');
    end if;
    if v_per_user is not null and v_used_user>=v_per_user then
      return jsonb_build_object('valid',false,'message','Ya utilizaste el máximo permitido de este cupón');
    end if;

    if v_config->>'discount_type'='percent' then
      v_discount:=round(v_fare*coalesce((v_config->>'value')::numeric,0)/100,2);
    else
      v_discount:=round(coalesce((v_config->>'value')::numeric,0),2);
    end if;
    if nullif(v_config->>'max_discount','') is not null then
      v_discount:=least(v_discount,(v_config->>'max_discount')::numeric);
    end if;
    v_discount:=least(greatest(v_discount,0),v_fare);
    v_final:=public.fare_round_value(greatest(v_fare-v_discount,0),public.fare_rounding_increment(coalesce(v_currency,'BOB'),p_channel));
    v_discount:=v_fare-v_final;

    return jsonb_build_object('valid',true,'kind','program','code',v_code,
      'name',v_program.name,'discount',v_discount,'final_fare',v_final,'currency',v_currency,
      'message','Cupón válido: descuento de '||v_discount::text||' '||coalesce(v_currency,''));
  end if;

  -- Personal coupons granted by welcome or loyalty rewards.
  select * into v_coupon from public.benefit_user_coupons c
  where c.code=v_code and c.user_id=v_uid and c.zone_id=v_zone
    and c.channel=p_channel and c.state='available' and c.expires_at>now()
  limit 1;
  if not found then
    return jsonb_build_object('valid',false,'message','El código no existe, ya venció o no está disponible para ti');
  end if;

  if v_coupon.discount_type='percent' then
    v_discount:=round(v_fare*v_coupon.value/100,2);
  else
    v_discount:=round(v_coupon.value,2);
  end if;
  if v_coupon.max_discount is not null then
    v_discount:=least(v_discount,v_coupon.max_discount);
  end if;
  v_discount:=least(greatest(v_discount,0),v_fare);
  v_final:=public.fare_round_value(greatest(v_fare-v_discount,0),public.fare_rounding_increment(coalesce(v_currency,'BOB'),p_channel));
  v_discount:=v_fare-v_final;

  return jsonb_build_object('valid',true,'kind','user','code',v_code,
    'name','Cupón de regalo','discount',v_discount,'final_fare',v_final,'currency',v_currency,
    'message','Cupón válido: descuento de '||v_discount::text||' '||coalesce(v_currency,''));
end $$;

revoke all on function public.validate_benefit_coupon(text,text,numeric,numeric,text,numeric,text) from public,anon;
grant execute on function public.validate_benefit_coupon(text,text,numeric,numeric,text,numeric,text) to authenticated;

-- 3. Aceptación directa del conductor en viaje con precio fijo por cupón ----------

create or replace function public.driver_accept_fixed_price_ride_v1(
  p_ride_request_id uuid,
  p_channel text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_channel text := public.normalize_runtime_channel(p_channel);
  v_ride public.ride_requests%rowtype;
  v_offer_id bigint;
  v_trip_id uuid;
  v_pin text;
  v_driver_name text;
  v_amount text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select * into v_ride
  from public.ride_requests r
  where r.id = p_ride_request_id
  for update;

  if not found then
    raise exception 'Solicitud no disponible';
  end if;
  if v_ride.channel is distinct from v_channel then
    raise exception 'Solicitud fuera del entorno seleccionado';
  end if;
  if v_ride.pricing_mode <> 'fixed' or coalesce(v_ride.benefit_discount_amount, 0) <= 0 then
    raise exception 'Esta solicitud no es de precio fijo';
  end if;
  if v_ride.service_mode = 'parcel' then
    raise exception 'Esta solicitud no es de viaje';
  end if;
  if v_ride.status not in ('searching', 'offers_received')
     or v_ride.expires_at is null or v_ride.expires_at <= now() then
    raise exception 'Solicitud vencida o no disponible';
  end if;
  if v_ride.passenger_id = v_uid then
    raise exception 'No puedes asignarte tu propia solicitud';
  end if;

  perform pg_advisory_xact_lock(hashtext('driver_trip:' || v_uid::text));
  if public.driver_has_active_trip(v_uid) then
    raise exception 'Tienes un viaje activo. Termínalo antes de aceptar otro.';
  end if;
  if not public.same_operational_scope(v_ride.passenger_id, v_uid) then
    raise exception 'Oferta fuera de tu entorno operativo';
  end if;

  perform set_config('app.runtime_channel', v_channel, true);

  -- La aceptación queda como oferta seleccionada para que pasen los controles del conductor
  -- (suscripción, zona, entorno y deuda). No se notifica al pasajero como oferta pendiente.
  insert into public.driver_offers (
    ride_request_id, driver_id, channel, proposed_fare, eta_minutes, status, created_at, expires_at
  )
  values (
    v_ride.id, v_uid, v_channel, v_ride.proposed_fare, null, 'selected',
    now(), now() + interval '1 minute'
  )
  on conflict (ride_request_id, driver_id) do update set
    status = 'selected',
    proposed_fare = excluded.proposed_fare,
    channel = excluded.channel,
    eta_minutes = null,
    created_at = excluded.created_at,
    expires_at = excluded.expires_at
  returning id into v_offer_id;

  select nullif(trim(u.full_name), '') into v_driver_name
  from public.users u
  where u.id = v_uid;

  v_amount := trim(to_char(v_ride.proposed_fare, 'FM999999990.00'));

  insert into public.notifications(user_id, title, body, type)
  select distinct o.driver_id,
    'Oferta no seleccionada',
    'Este viaje fue asignado a otro conductor.',
    'ride_offer_declined'
  from public.driver_offers o
  where o.ride_request_id = v_ride.id
    and o.status = 'pending'
    and o.id <> v_offer_id
    and o.driver_id <> v_uid
    and public.same_operational_scope(v_ride.passenger_id, o.driver_id);

  update public.driver_offers
  set status = 'declined'
  where ride_request_id = v_ride.id
    and status = 'pending'
    and id <> v_offer_id;

  update public.ride_requests
  set status = 'driver_selected', updated_at = now()
  where id = v_ride.id;

  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');

  insert into public.trips (
    ride_request_id, passenger_id, driver_id, status, final_fare,
    payment_status, boarding_pin
  )
  values (
    v_ride.id, v_ride.passenger_id, v_uid, 'driver_arriving', v_ride.proposed_fare,
    'pending', v_pin
  )
  returning id into v_trip_id;

  insert into public.trip_status_history (trip_id, status, changed_by)
  values (v_trip_id, 'driver_arriving', v_uid);

  update public.driver_profiles
  set online_status = 'busy', updated_at = now()
  where id = v_uid;

  insert into public.notifications (user_id, title, body, type)
  values
    (
      v_uid,
      '¡Viaje confirmado!',
      'Viaje con precio fijo de ' || public.express_push_currency_label(v_ride.currency) || v_amount ||
        '. Ya estás en camino al punto de recogida.',
      'ride_assigned'
    ),
    (
      v_ride.passenger_id,
      'Conductor confirmado',
      coalesce(v_driver_name, 'Tu conductor') ||
        ' fue asignado y ya va en camino. Sigue su llegada en el mapa.',
      'ride_assigned'
    );

  return v_trip_id;
end;
$$;

revoke all on function public.driver_accept_fixed_price_ride_v1(uuid, text) from public, anon;
grant execute on function public.driver_accept_fixed_price_ride_v1(uuid, text) to authenticated;

commit;
