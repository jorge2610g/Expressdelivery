-- Repair of the passenger coupon flow (benefit programs and generated coupons).
--
-- 1. Coupons only apply to cash or driver QR rides. Settlement only processes
--    those methods, so any other method used to leave the reservation stuck.
-- 2. Coupons never apply to parcels (envíos).
-- 3. Generated coupons (activation/loyalty) get the same reservation checks
--    as program coupons.
-- 4. first_ride_only and one-use rules also count reservations that are
--    still pending, not only completed trips.
-- 5. Admin validation reports the specific failing rule.
-- 6. Coupon programs are always transport-only.
-- 7. Repairs reservations left stuck by the previous rules: they are released
--    only when their ride request is already terminal, and the coupon returns
--    to the passenger as available.
begin;

create or replace function public.reserve_benefit_coupon_for_request()
returns trigger language plpgsql security definer set search_path=public as $$
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
  if new.service_mode='parcel' then
    raise exception 'Los cupones no se aplican a envíos';
  end if;
  if coalesce(new.payment_method,'') not in ('cash','driver_qr') then
    raise exception 'Los cupones de viaje solo se aplican a pago en efectivo o QR del conductor';
  end if;

  select * into v_program from public.benefit_programs p
  where p.channel=new.channel and p.zone_id=new.zone_id
    and p.program_type='coupon' and p.state='active'
    and upper(coalesce(p.config->>'code',''))=new.benefit_coupon_code
    and (p.starts_at is null or p.starts_at<=now())
    and (p.ends_at is null or p.ends_at>now())
  for update;

  if found then
    v_config:=v_program.config;
    if coalesce(v_config->>'audience','passengers') not in ('passengers','clients') then
      raise exception 'El cupón no aplica a este tipo de cliente';
    end if;
    if coalesce(v_config->>'service_mode','transport') not in ('transport','taxi') then
      raise exception 'El cupón solo aplica a viajes de transporte';
    end if;
    if coalesce(v_config->>'service_type','all') not in ('all',new.category)
       and not (v_config->>'service_type'='moto' and new.category in ('motorcycle','moto')) then
      raise exception 'El cupón no aplica a esta categoría de vehículo';
    end if;
    if coalesce(new.proposed_fare,0)<coalesce(nullif(v_config->>'min_fare','')::numeric,0) then
      raise exception 'La tarifa es menor al mínimo de este cupón';
    end if;
    if v_config->>'discount_type' not in ('fixed','percent')
       or coalesce(nullif(v_config->>'value','')::numeric,0)<=0 then
      raise exception 'El cupón no tiene un descuento válido';
    end if;

    v_has_trips:=exists(
      select 1 from public.trips t where t.passenger_id=new.passenger_id
        and t.channel=new.channel and t.status='completed' and t.payment_status='paid');
    if coalesce((v_config->>'first_ride_only')::boolean,false) then
      if v_has_trips then
        raise exception 'Este cupón es válido solo para el primer viaje';
      end if;
      if exists(select 1 from public.benefit_coupon_reservations r
        where r.program_id=v_program.id and r.user_id=new.passenger_id
          and r.state in ('reserved','redeemed')) then
        raise exception 'Ya tienes un viaje con este cupón pendiente o usado';
      end if;
    end if;
    if coalesce(v_config->>'target_audience','all')='new' and v_has_trips then
      raise exception 'Este cupón es solo para usuarios nuevos';
    end if;
    if coalesce(v_config->>'target_audience','all')='returning' and not v_has_trips then
      raise exception 'Este cupón es para usuarios frecuentes';
    end if;

    v_max_total:=nullif(v_config->>'max_total_uses','')::integer;
    v_per_user:=nullif(v_config->>'uses_per_user','')::integer;
    select count(*) into v_used_total from public.benefit_coupon_reservations r
      where r.program_id=v_program.id and r.channel=new.channel and r.state in ('reserved','redeemed');
    select count(*) into v_used_user from public.benefit_coupon_reservations r
      where r.program_id=v_program.id and r.user_id=new.passenger_id
        and r.channel=new.channel and r.state in ('reserved','redeemed');
    if v_max_total is not null and v_used_total>=v_max_total then
      raise exception 'Este cupón ya alcanzó su límite de usos';
    end if;
    if v_per_user is not null and v_used_user>=v_per_user then
      raise exception 'Ya utilizaste el máximo permitido de este cupón';
    end if;

    perform set_config('app.benefit_coupon_write','on',true);
    update public.ride_requests set benefit_coupon_program_id=v_program.id where id=new.id;
    insert into public.benefit_coupon_reservations(ride_request_id,channel,zone_id,user_id,program_id)
      values(new.id,new.channel,new.zone_id,new.passenger_id,v_program.id);
    return new;
  end if;

  select * into v_coupon from public.benefit_user_coupons c
  where c.code=new.benefit_coupon_code and c.user_id=new.passenger_id
    and c.zone_id=new.zone_id and c.channel=new.channel and c.state='available'
    and c.expires_at>now()
  for update;
  if not found then
    raise exception 'El código de cupón no es válido o no está disponible';
  end if;
  update public.benefit_user_coupons set state='reserved',reserved_request_id=new.id where id=v_coupon.id;
  perform set_config('app.benefit_coupon_write','on',true);
  update public.ride_requests set benefit_user_coupon_id=v_coupon.id where id=new.id;
  insert into public.benefit_coupon_reservations(ride_request_id,channel,zone_id,user_id,user_coupon_id)
    values(new.id,new.channel,new.zone_id,new.passenger_id,v_coupon.id);
  return new;
end $$;
revoke all on function public.reserve_benefit_coupon_for_request() from public,anon,authenticated;

create or replace function public.admin_benefit_program_save(
  p_id uuid,p_zone_id uuid,p_channel text,p_type text,p_name text,
  p_description text,p_config jsonb,p_state text,
  p_starts_at timestamptz default null,p_ends_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_context jsonb;v_record public.benefit_programs%rowtype;
begin
  if auth.uid() is null or not public.is_admin()
    or p_channel not in ('preview','production')
    or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso a beneficios no autorizado';
  end if;
  v_context:=public.admin_access_context();
  if coalesce(v_context->>'role','')<>'super_admin' then
    raise exception 'Solo el superadministrador puede configurar programas de beneficios';
  end if;
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid<>p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  if not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active) then
    raise exception 'La zona no existe o está inactiva';
  end if;
  if p_type not in ('coupon','activation','loyalty','referral','referral_commission','driver_challenge')
    or p_state not in ('draft','active','paused','closed') then
    raise exception 'Tipo o estado de programa inválido';
  end if;
  if length(trim(coalesce(p_name,'')))<2 or length(trim(p_name))>100 then
    raise exception 'El nombre debe tener entre 2 y 100 caracteres';
  end if;
  if length(coalesce(p_description,''))>1000 then
    raise exception 'La descripción no puede superar 1000 caracteres';
  end if;
  if p_config is null or jsonb_typeof(p_config)<>'object' then
    raise exception 'La configuración del programa es inválida';
  end if;
  if p_ends_at is not null and p_starts_at is not null and p_ends_at<=p_starts_at then
    raise exception 'La fecha de fin debe ser posterior a la de inicio';
  end if;

  if p_type='coupon' then
    if coalesce(p_config->>'code','') !~ '^[A-Z0-9_-]{3,64}$' then
      raise exception 'El código debe tener de 3 a 64 caracteres: letras mayúsculas, números, guion o guion bajo';
    end if;
    if p_config->>'discount_type' not in ('fixed','percent') then
      raise exception 'El tipo de descuento debe ser monto fijo o porcentaje';
    end if;
    if coalesce((p_config->>'value')::numeric,0)<=0 then
      raise exception 'El descuento debe ser mayor que cero';
    end if;
    if p_config->>'discount_type'='percent' and (p_config->>'value')::numeric>100 then
      raise exception 'El porcentaje de descuento no puede superar 100';
    end if;
    if coalesce((p_config->>'max_discount')::numeric,0)<0
       or coalesce((p_config->>'min_fare')::numeric,0)<0 then
      raise exception 'El tope de descuento y la tarifa mínima no pueden ser negativos';
    end if;
    if coalesce(p_config->>'service_mode','transport')<>'transport' then
      raise exception 'Los cupones solo se aplican a viajes de transporte';
    end if;
    if coalesce(p_config->>'audience','passengers') not in ('passengers','clients') then
      raise exception 'El público de un cupón debe ser pasajeros o clientes';
    end if;
  end if;

  if p_state='active' and p_type not in ('referral_commission','coupon','activation','loyalty','driver_challenge') then
    raise exception 'Este tipo de programa requiere reglas de liquidación antes de activarse';
  end if;
  if p_type='activation' and p_state='active' then
    if p_config->>'trigger_type'<>'first_trip' then
      raise exception 'La bienvenida solo puede activarse con el primer viaje';
    end if;
    if p_config->>'reward_destination'='wallet' then
      raise exception 'La recompensa de bienvenida debe ser un cupón, no billetera';
    end if;
    if coalesce((p_config->>'value')::numeric,0)<=0 then
      raise exception 'La bienvenida requiere un valor mayor que cero';
    end if;
    if p_config->>'reward_type' not in ('fixed','percent','coupon') then
      raise exception 'El tipo de recompensa de bienvenida no es válido';
    end if;
    if p_config->>'reward_type'='percent' and (p_config->>'value')::numeric>100 then
      raise exception 'El porcentaje de la bienvenida no puede superar 100';
    end if;
  end if;
  if p_type='loyalty' and p_state='active' then
    if coalesce((p_config->>'trip_threshold')::integer,0)<=0 then
      raise exception 'La lealtad requiere una meta de viajes mayor que cero';
    end if;
    if coalesce((p_config->>'free_trip_cap')::numeric,0)<0 then
      raise exception 'El tope del viaje gratis no puede ser negativo';
    end if;
  end if;
  if p_type='driver_challenge' and p_state='active' then
    if coalesce((p_config->>'trip_goal')::integer,(p_config->>'trip_threshold')::integer,0)<=0 then
      raise exception 'El reto requiere una meta de viajes mayor que cero';
    end if;
    if coalesce((p_config->>'value')::numeric,0)<=0 then
      raise exception 'El reto requiere un bono mayor que cero';
    end if;
    if p_config->>'period' not in ('daily','weekly','monthly','custom') then
      raise exception 'El periodo del reto no es válido';
    end if;
  end if;
  if p_type='referral_commission' and (
    not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.country_code='BO')
    or coalesce((p_config->>'plan_payment_percent')::numeric,0)<=0
    or coalesce((p_config->>'plan_payment_percent')::numeric,0)>100
  ) then
    raise exception 'El referido de pagos de plan requiere porcentaje válido y una zona de Bolivia';
  end if;
  if p_id is not null and not exists(select 1 from public.benefit_programs
    where id=p_id and zone_id=p_zone_id and channel=p_channel) then
    raise exception 'No se puede modificar un programa ajeno';
  end if;

  insert into public.benefit_programs(id,channel,zone_id,program_type,name,description,config,state,starts_at,ends_at,created_by)
  values(coalesce(p_id,gen_random_uuid()),p_channel,p_zone_id,p_type,trim(p_name),coalesce(p_description,''),p_config,p_state,p_starts_at,p_ends_at,auth.uid())
  on conflict(id) do update set program_type=excluded.program_type,name=excluded.name,
    description=excluded.description,config=excluded.config,state=excluded.state,
    starts_at=excluded.starts_at,ends_at=excluded.ends_at,updated_at=now()
  returning * into v_record;
  perform public.admin_log_action('upsert','benefit_program',v_record.id::text,
    jsonb_build_object('channel',p_channel,'zone_id',p_zone_id,'type',p_type,'state',p_state));
  return to_jsonb(v_record);
end $$;

-- Repair: reservations left pending by the previous rules whose ride is already
-- terminal. The coupon goes back to the passenger as available.
update public.benefit_coupon_reservations r
set state='released'
from public.ride_requests q
where q.id=r.ride_request_id
  and r.state='reserved'
  and r.user_coupon_id is not null
  and q.status in ('completed','cancelled','canceled','expired','rejected')
  and (q.service_mode='parcel' or coalesce(q.payment_method,'') not in ('cash','driver_qr')
       or q.status<>'completed');

update public.benefit_user_coupons c
set state='available', reserved_request_id=null
from public.benefit_coupon_reservations r
where r.user_coupon_id=c.id
  and r.state='released'
  and c.state='reserved'
  and c.reserved_request_id=r.ride_request_id;

commit;
