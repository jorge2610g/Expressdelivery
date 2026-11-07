-- Cupón: la tarifa es la base del servidor (la mínima), no la que manda el pasajero.
--
-- El pasajero no puede subir ni bajar la tarifa con cupón, y el conductor solo acepta o
-- rechaza esa tarifa base con el descuento. Si el cliente pudiera enviar un monto más alto,
-- el descuento se calcularía sobre un precio inflado y la plataforma pagaría la diferencia.
--
-- Por eso, al crear una solicitud con cupón de efectivo o QR del conductor, la tarifa base
-- sale de la cotización del servidor (tarifa mínima permitida, redondeada hacia arriba al
-- incremento de la zona). Después se aplica el descuento como en la versión anterior.
-- Las tarifas especiales fijas (special_fare_zone_id) no cambian.

begin;

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
  v_quote jsonb;
  v_min numeric;
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

  v_inc := public.fare_rounding_increment(coalesce(v_currency, new.currency, 'BOB'), new.channel);

  -- Tarifa base: la mínima que calcula el servidor. Una tarifa especial fija ya viene
  -- definida por el servidor y no se cambia.
  v_orig := round(greatest(coalesce(new.proposed_fare, 0), 0), 2);
  if new.special_fare_zone_id is null
     and new.pickup_latitude is not null and new.pickup_longitude is not null then
    v_quote := public.dynamic_pricing_quote_internal(
      new.category,
      coalesce(new.route_distance_km, 0),
      coalesce(new.route_duration_minutes, 0),
      new.pickup_latitude,
      new.pickup_longitude,
      new.channel
    );
    v_min := coalesce((v_quote->>'minimum_allowed_fare')::numeric, v_orig);
    v_orig := round(ceil(v_min / v_inc) * v_inc, 2);
  end if;

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

revoke all on function public.apply_benefit_coupon_fixed_price() from public, anon, authenticated;

commit;
