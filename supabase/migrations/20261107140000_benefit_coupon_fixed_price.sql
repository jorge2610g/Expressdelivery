-- Cupón con precio fijo.
--
-- Antes: el cupón solo guardaba el código; el precio del viaje no cambiaba, el conductor
-- veía la tarifa completa y el descuento se aplicaba al cobrar.
--
-- Ahora, al crear la solicitud con un cupón válido de efectivo o QR del conductor:
--   * ride_requests.benefit_original_fare = tarifa antes del descuento;
--   * ride_requests.benefit_discount_amount = descuento calculado en el servidor;
--   * ride_requests.proposed_fare = tarifa final (ya descontada);
--   * ride_requests.pricing_mode = 'fixed': el conductor solo acepta o rechaza, sin oferta
--     ni contraoferta (driver_offers debe igualar la tarifa fija).
-- En la liquidación el precio ya viene descontado: el pasajero paga el final_fare y el
-- descuento se acredita al conductor igual que antes (ajuste de billetera). Los cupones
-- sin precio fijo (original_fare nulo) siguen con el cálculo anterior.

begin;

alter table public.ride_requests
  add column if not exists benefit_original_fare numeric(12,2);

-- 1. Precio fijo al crear la solicitud (corre después de la zona y el precio especial).
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
  if v_discount <= 0 then return new; end if;

  v_inc := public.fare_rounding_increment(coalesce(v_currency, new.currency, 'BOB'), new.channel);

  new.zone_id := v_zone_id;
  new.benefit_original_fare := v_orig;
  new.benefit_discount_amount := v_discount;
  new.proposed_fare := public.fare_round_value(greatest(v_orig - v_discount, 0), v_inc);
  new.base_fare := new.proposed_fare;
  new.pricing_mode := 'fixed';
  return new;
end $$;

revoke all on function public.apply_benefit_coupon_fixed_price() from public, anon, authenticated;

drop trigger if exists zz_benefit_coupon_fixed_price on public.ride_requests;
create trigger zz_benefit_coupon_fixed_price
  before insert on public.ride_requests
  for each row execute function public.apply_benefit_coupon_fixed_price();

-- 2. La reserva valida el mínimo contra la tarifa original, no contra la descontada.
create or replace function public.reserve_benefit_coupon_for_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_program public.benefit_programs%rowtype;
  v_coupon public.benefit_user_coupons%rowtype;
  v_config jsonb;
  v_has_trips boolean;
  v_max_total integer;
  v_per_user integer;
  v_used_total integer;
  v_used_user integer;
begin
  if new.benefit_coupon_code is null then return new; end if;
  if auth.uid() is distinct from new.passenger_id or new.zone_id is null then
    raise exception 'No se pudo validar el cupón para este pasajero y zona';
  end if;
  if new.service_mode = 'parcel' then
    raise exception 'Los cupones no se aplican a envíos';
  end if;
  if coalesce(new.payment_method, '') not in ('cash', 'driver_qr') then
    raise exception 'Los cupones de viaje solo se aplican a pago en efectivo o QR del conductor';
  end if;

  select * into v_program from public.benefit_programs p
  where p.channel = new.channel and p.zone_id = new.zone_id
    and p.program_type = 'coupon' and p.state = 'active'
    and upper(coalesce(p.config->>'code', '')) = new.benefit_coupon_code
    and (p.starts_at is null or p.starts_at <= now())
    and (p.ends_at is null or p.ends_at > now())
  for update;

  if found then
    v_config := v_program.config;
    if coalesce(v_config->>'audience', 'passengers') not in ('passengers', 'clients') then
      raise exception 'El cupón no aplica a este tipo de cliente';
    end if;
    if coalesce(v_config->>'service_mode', 'transport') not in ('transport', 'taxi') then
      raise exception 'El cupón solo aplica a viajes de transporte';
    end if;
    if coalesce(v_config->>'service_type', 'all') not in ('all', new.category)
       and not (v_config->>'service_type' = 'moto' and new.category in ('motorcycle', 'moto')) then
      raise exception 'El cupón no aplica a esta categoría de vehículo';
    end if;
    if coalesce(new.benefit_original_fare, new.proposed_fare, 0)
       < coalesce(nullif(v_config->>'min_fare', '')::numeric, 0) then
      raise exception 'La tarifa es menor al mínimo de este cupón';
    end if;
    if v_config->>'discount_type' not in ('fixed', 'percent')
       or coalesce(nullif(v_config->>'value', '')::numeric, 0) <= 0 then
      raise exception 'El cupón no tiene un descuento válido';
    end if;

    v_has_trips := exists(
      select 1 from public.trips t where t.passenger_id = new.passenger_id
        and t.channel = new.channel and t.status = 'completed' and t.payment_status = 'paid');
    if coalesce((v_config->>'first_ride_only')::boolean, false) then
      if v_has_trips then
        raise exception 'Este cupón es válido solo para el primer viaje';
      end if;
      if exists(select 1 from public.benefit_coupon_reservations r
        where r.program_id = v_program.id and r.user_id = new.passenger_id
          and r.state in ('reserved', 'redeemed')) then
        raise exception 'Ya tienes un viaje con este cupón pendiente o usado';
      end if;
    end if;
    if coalesce(v_config->>'target_audience', 'all') = 'new' and v_has_trips then
      raise exception 'Este cupón es solo para usuarios nuevos';
    end if;
    if coalesce(v_config->>'target_audience', 'all') = 'returning' and not v_has_trips then
      raise exception 'Este cupón es para usuarios frecuentes';
    end if;

    v_max_total := nullif(v_config->>'max_total_uses', '')::integer;
    v_per_user := nullif(v_config->>'uses_per_user', '')::integer;
    select count(*) into v_used_total from public.benefit_coupon_reservations r
      where r.program_id = v_program.id and r.channel = new.channel and r.state in ('reserved', 'redeemed');
    select count(*) into v_used_user from public.benefit_coupon_reservations r
      where r.program_id = v_program.id and r.user_id = new.passenger_id
        and r.channel = new.channel and r.state in ('reserved', 'redeemed');
    if v_max_total is not null and v_used_total >= v_max_total then
      raise exception 'Este cupón ya alcanzó su límite de usos';
    end if;
    if v_per_user is not null and v_used_user >= v_per_user then
      raise exception 'Ya utilizaste el máximo permitido de este cupón';
    end if;

    perform set_config('app.benefit_coupon_write', 'on', true);
    update public.ride_requests set benefit_coupon_program_id = v_program.id where id = new.id;
    insert into public.benefit_coupon_reservations(ride_request_id, channel, zone_id, user_id, program_id)
      values(new.id, new.channel, new.zone_id, new.passenger_id, v_program.id);
    return new;
  end if;

  select * into v_coupon from public.benefit_user_coupons c
  where c.code = new.benefit_coupon_code and c.user_id = new.passenger_id
    and c.zone_id = new.zone_id and c.channel = new.channel and c.state = 'available'
    and c.expires_at > now()
  for update;
  if not found then
    raise exception 'El código de cupón no es válido o no está disponible';
  end if;
  update public.benefit_user_coupons set state = 'reserved', reserved_request_id = new.id where id = v_coupon.id;
  perform set_config('app.benefit_coupon_write', 'on', true);
  update public.ride_requests set benefit_user_coupon_id = v_coupon.id where id = new.id;
  insert into public.benefit_coupon_reservations(ride_request_id, channel, zone_id, user_id, user_coupon_id)
    values(new.id, new.channel, new.zone_id, new.passenger_id, v_coupon.id);
  return new;
end $$;

-- 3. Oferta del conductor: en precio fijo por cupón solo se permite la tarifa fija.
create or replace function public.guard_benefit_coupon_fixed_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.ride_requests%rowtype;
begin
  select * into v_request from public.ride_requests where id = new.ride_request_id;
  if found and v_request.pricing_mode = 'fixed'
     and coalesce(v_request.benefit_discount_amount, 0) > 0
     and round(new.proposed_fare, 2) <> round(v_request.proposed_fare, 2) then
    raise exception 'Este viaje tiene precio fijo por cupón: solo puedes aceptar o rechazar';
  end if;
  return new;
end $$;

revoke all on function public.guard_benefit_coupon_fixed_offer() from public, anon, authenticated;

drop trigger if exists zz_guard_benefit_coupon_fixed_offer on public.driver_offers;
create trigger zz_guard_benefit_coupon_fixed_offer
  before insert or update of proposed_fare on public.driver_offers
  for each row execute function public.guard_benefit_coupon_fixed_offer();

-- 4. Cotización del viaje: con precio fijo el final_fare ya está descontado.
create or replace function public.quote_trip_benefit_amounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_request public.ride_requests%rowtype;v_reservation public.benefit_coupon_reservations%rowtype;
  v_program public.benefit_programs%rowtype;v_coupon public.benefit_user_coupons%rowtype;
  v_config jsonb;v_fare numeric(12,2);v_discount numeric(12,2):=0;
begin
  select * into v_request from public.ride_requests where id=new.ride_request_id;
  if not found then return new; end if;
  v_fare:=round(greatest(coalesce(new.final_fare,v_request.proposed_fare,0),0),2);
  new.passenger_due_amount:=v_fare;
  new.promotion_credit_amount:=0;
  if v_request.service_mode='parcel' or v_request.payment_method not in ('cash','driver_qr') then return new; end if;
  select * into v_reservation from public.benefit_coupon_reservations
    where ride_request_id=v_request.id and state='reserved';
  if not found then return new; end if;
  if v_request.benefit_original_fare is not null then
    v_discount:=least(greatest(coalesce(v_request.benefit_discount_amount,0),0),v_fare);
    new.passenger_due_amount:=v_fare;
    new.promotion_credit_amount:=v_discount;
    return new;
  end if;
  if v_reservation.program_id is not null then
    select * into v_program from public.benefit_programs where id=v_reservation.program_id;
    v_config:=v_program.config;
    if v_config->>'discount_type'='percent' then
      v_discount:=round(v_fare*coalesce((v_config->>'value')::numeric,0)/100,2);
    else v_discount:=round(coalesce((v_config->>'value')::numeric,0),2); end if;
    if nullif(v_config->>'max_discount','') is not null then
      v_discount:=least(v_discount,(v_config->>'max_discount')::numeric);
    end if;
  else
    select * into v_coupon from public.benefit_user_coupons where id=v_reservation.user_coupon_id;
    if v_coupon.discount_type='percent' then v_discount:=round(v_fare*v_coupon.value/100,2);
    else v_discount:=round(v_coupon.value,2); end if;
    if v_coupon.max_discount is not null then v_discount:=least(v_discount,v_coupon.max_discount); end if;
  end if;
  v_discount:=least(greatest(v_discount,0),v_fare);
  new.passenger_due_amount:=greatest(v_fare-v_discount,0);
  new.promotion_credit_amount:=v_discount;
  return new;
end $$;

-- 5. Liquidación: con precio fijo no se vuelve a descontar; el conductor recibe el descuento.
create or replace function public.settle_trip_benefits_for_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trip public.trips%rowtype;
  v_request public.ride_requests%rowtype;
  v_zone public.service_zones%rowtype;
  v_reservation public.benefit_coupon_reservations%rowtype;
  v_program public.benefit_programs%rowtype;
  v_grant public.benefit_user_coupons%rowtype;
  v_fare numeric(12,2);
  v_discount numeric(12,2):=0;
  v_due numeric(12,2);
  v_config jsonb;
  v_trip_count integer;
  v_threshold integer;
  v_award_count integer;
  v_goal integer;
  v_period text;
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_award_id uuid;
  v_wallet_id uuid;
begin
  v_award_id:=null;
  if tg_op='UPDATE' then
    if old.status='paid' then return new; end if;
  end if;
  if new.status<>'paid' or new.trip_id is null then return new; end if;
  select * into v_trip from public.trips where id=new.trip_id for update;
  if not found or v_trip.status<>'completed' or v_trip.payment_status<>'paid' then return new; end if;
  select * into v_request from public.ride_requests where id=v_trip.ride_request_id for update;
  if not found or v_request.service_mode='parcel' then return new; end if;
  if new.method not in ('cash','driver_qr','wallet') then return new; end if;
  select * into v_zone from public.service_zones where id=v_request.zone_id;
  if not found then return new; end if;
  v_fare:=round(greatest(coalesce(v_trip.final_fare,0),0),2);
  v_due:=v_fare;
  select * into v_reservation from public.benefit_coupon_reservations
    where ride_request_id=v_request.id and state='reserved' for update;
  if found then
    if v_request.benefit_original_fare is not null then
      v_discount:=least(greatest(coalesce(v_request.benefit_discount_amount,0),0),v_fare);
      v_due:=v_fare;
    else
      if v_reservation.program_id is not null then
        select * into v_program from public.benefit_programs where id=v_reservation.program_id for update;
        v_config:=v_program.config;
        if v_config->>'discount_type'='percent' then
          v_discount:=round(v_fare*coalesce((v_config->>'value')::numeric,0)/100,2);
        else
          v_discount:=round(coalesce((v_config->>'value')::numeric,0),2);
        end if;
        if nullif(v_config->>'max_discount','') is not null then
          v_discount:=least(v_discount,(v_config->>'max_discount')::numeric);
        end if;
        v_discount:=least(v_discount,v_fare);
      else
        select * into v_grant from public.benefit_user_coupons where id=v_reservation.user_coupon_id for update;
        if v_grant.discount_type='percent' then v_discount:=round(v_fare*v_grant.value/100,2);
        else v_discount:=round(v_grant.value,2); end if;
        if v_grant.max_discount is not null then v_discount:=least(v_discount,v_grant.max_discount); end if;
        v_discount:=least(v_discount,v_fare);
      end if;
      v_due:=greatest(v_fare-v_discount,0);
    end if;
    update public.benefit_coupon_reservations set state='redeemed' where ride_request_id=v_request.id;
    if v_reservation.user_coupon_id is not null then
      update public.benefit_user_coupons set state='redeemed',redeemed_trip_id=v_trip.id where id=v_reservation.user_coupon_id;
    end if;
    perform set_config('app.benefit_coupon_write','on',true);
    update public.ride_requests set benefit_discount_amount=v_discount where id=v_request.id;
    insert into public.benefit_redemptions(program_id,channel,zone_id,user_id,trip_id,benefit_type,amount,currency_code,state,metadata)
    values(coalesce(v_reservation.program_id,v_grant.program_id),v_request.channel,v_request.zone_id,
      v_request.passenger_id,v_trip.id,'ride_coupon',v_discount,v_zone.currency_code,'approved',
      jsonb_build_object('fare',v_fare,'passenger_due',v_due,'driver_credit',v_discount,'code',v_request.benefit_coupon_code))
    on conflict(program_id,user_id,trip_id,benefit_type) do nothing;
    if found and v_discount>0 then
      insert into public.wallet_transactions(user_id,amount,type,status,reference,trip_id,country_code,channel)
      values(v_trip.driver_id,v_discount,'adjustment','completed',
        'benefit:coupon:'||v_trip.id::text,v_trip.id,v_zone.country_code,v_request.channel);
      if v_request.channel='production' then
        perform public.mirror_legacy_wallet_delta(v_trip.driver_id,v_zone.currency_code,v_discount);
      end if;
    end if;
  end if;
  update public.payment_transactions set amount=v_due,commission_percent=0,commission_amount=0,
    driver_net_amount=v_due where id=new.id;
  update public.trips set passenger_due_amount=v_due,promotion_credit_amount=v_discount where id=v_trip.id;

  -- Activation rewards issue a personal, non-cash coupon after the passenger's first paid ride.
  perform 1 from public.users where id=v_request.passenger_id for update;
  select count(*)::integer into v_trip_count from public.trips t
    where t.passenger_id=v_request.passenger_id and t.channel=v_request.channel
      and t.status='completed' and t.payment_status='paid'
      and exists(select 1 from public.ride_requests r where r.id=t.ride_request_id and r.service_mode<>'parcel');
  if v_trip_count=1 then
    for v_program in select * from public.benefit_programs p
      where p.zone_id=v_request.zone_id and p.channel=v_request.channel
        and p.program_type='activation' and p.state='active'
        and p.config->>'trigger_type'='first_trip'
        and (p.starts_at is null or p.starts_at<=now()) and (p.ends_at is null or p.ends_at>now())
      for update
    loop
      v_config:=v_program.config;
      if coalesce(nullif(v_config->>'max_activations','')::integer,2147483647)>
        (select count(*) from public.benefit_user_coupons where program_id=v_program.id) then
        if v_config->>'reward_type'='percent' then
          perform public.issue_benefit_user_coupon(v_program.id,v_request.passenger_id,v_trip.id,
            v_request.channel,v_request.zone_id,'activation','percent',(v_config->>'value')::numeric,
            nullif(v_config->>'max_discount','')::numeric);
        elsif v_config->>'reward_type'='fixed' then
          perform public.issue_benefit_user_coupon(v_program.id,v_request.passenger_id,v_trip.id,
            v_request.channel,v_request.zone_id,'activation','fixed',(v_config->>'value')::numeric,null);
        else
          perform public.issue_benefit_user_coupon(v_program.id,v_request.passenger_id,v_trip.id,
            v_request.channel,v_request.zone_id,'activation','percent',100,
            nullif(v_config->>'free_trip_cap','')::numeric);
        end if;
      end if;
    end loop;
  end if;

  -- Every Nth paid ride earns a one-use coupon for the passenger's next ride.
  for v_program in select * from public.benefit_programs p
    where p.zone_id=v_request.zone_id and p.channel=v_request.channel
      and p.program_type='loyalty' and p.state='active'
      and (p.starts_at is null or p.starts_at<=now()) and (p.ends_at is null or p.ends_at>now())
    for update
  loop
    v_config:=v_program.config;
    v_threshold:=coalesce(nullif(v_config->>'trip_threshold','')::integer,0);
    select count(*)::integer into v_award_count from public.benefit_user_coupons c where c.program_id=v_program.id;
    if v_threshold>0 and v_trip_count%v_threshold=0
       and v_award_count<coalesce(nullif(v_config->>'max_total_rewards','')::integer,2147483647)
       and (select count(*) from public.benefit_user_coupons c where c.program_id=v_program.id and c.user_id=v_request.passenger_id)
          <coalesce(nullif(v_config->>'max_rewards_per_customer','')::integer,2147483647) then
      perform public.issue_benefit_user_coupon(v_program.id,v_request.passenger_id,v_trip.id,
        v_request.channel,v_request.zone_id,'loyalty','percent',100,
        nullif(v_config->>'free_trip_cap','')::numeric);
    end if;
  end loop;

  -- Driver challenge bonuses are internal-wallet credits, capped to one award per cycle.
  for v_program in select * from public.benefit_programs p
    where p.zone_id=v_request.zone_id and p.channel=v_request.channel
      and p.program_type='driver_challenge' and p.state='active'
      and (p.starts_at is null or p.starts_at<=now()) and (p.ends_at is null or p.ends_at>now())
    for update
  loop
    v_config:=v_program.config;
    v_goal:=coalesce(nullif(v_config->>'trip_goal','')::integer,nullif(v_config->>'trip_threshold','')::integer,0);
    v_period:=coalesce(v_config->>'period','weekly');
    v_cycle_start:=greatest(
      case when v_period='daily' then date_trunc('day',now())
        when v_period='monthly' then date_trunc('month',now())
        when v_period='weekly' then date_trunc('week',now())
        else coalesce(v_program.starts_at,date_trunc('week',now())) end,
      coalesce(v_program.starts_at,date_trunc('week',now()))
    );
    v_cycle_end:=least(
      case when v_period='daily' then date_trunc('day',now())+interval '1 day'
        when v_period='monthly' then date_trunc('month',now())+interval '1 month'
        when v_period='weekly' then date_trunc('week',now())+interval '1 week'
        else coalesce(v_program.ends_at,v_cycle_start+interval '1 month') end,
      coalesce(v_program.ends_at,'infinity'::timestamptz)
    );
    if v_goal>0 and coalesce((v_config->>'value')::numeric,0)>0
       and v_cycle_start>=coalesce(v_program.starts_at,v_cycle_start)
       and (v_program.ends_at is null or v_cycle_start<v_program.ends_at)
       and (coalesce(v_config->>'service_type','all') in ('all',v_request.category))
       and (select count(*) from public.benefit_driver_challenge_awards a where a.program_id=v_program.id)
          <coalesce(nullif(v_config->>'max_total_rewards','')::integer,2147483647)
       and (select count(*) from public.benefit_driver_challenge_awards a
          where a.program_id=v_program.id and a.user_id=v_trip.driver_id)
          <coalesce(nullif(v_config->>'max_rewards_per_customer','')::integer,2147483647)
       and (select count(*) from public.trips t join public.ride_requests r on r.id=t.ride_request_id
         where t.driver_id=v_trip.driver_id and t.channel=v_request.channel and t.status='completed'
           and t.payment_status='paid' and t.completed_at>=v_cycle_start and t.completed_at<v_cycle_end
           and r.zone_id=v_request.zone_id and r.service_mode<>'parcel'
           and (coalesce(v_config->>'service_type','all') in ('all',r.category)
             or (v_config->>'service_type'='moto' and r.category in ('motorcycle','moto'))))>=v_goal
    then
      insert into public.benefit_driver_challenge_awards(program_id,user_id,cycle_start,trip_id,channel,zone_id,amount,currency_code)
      values(v_program.id,v_trip.driver_id,v_cycle_start,v_trip.id,v_request.channel,v_request.zone_id,
        (v_config->>'value')::numeric,v_zone.currency_code)
      on conflict(program_id,user_id,cycle_start) do nothing
      returning trip_id into v_award_id;
      if v_award_id is not null then
        insert into public.wallet_transactions(user_id,amount,type,status,reference,trip_id,country_code,channel)
        values(v_trip.driver_id,(v_config->>'value')::numeric,'adjustment','completed',
          'benefit:challenge:'||v_program.id::text||':'||v_cycle_start::date::text,v_trip.id,v_zone.country_code,v_request.channel)
        returning id into v_wallet_id;
        update public.benefit_driver_challenge_awards set wallet_transaction_id=v_wallet_id
          where program_id=v_program.id and user_id=v_trip.driver_id and cycle_start=v_cycle_start;
        if v_request.channel='production' then
          perform public.mirror_legacy_wallet_delta(v_trip.driver_id,v_zone.currency_code,(v_config->>'value')::numeric);
        end if;
      end if;
    end if;
  end loop;
  return new;
end $$;

commit;
