-- Read-only validation of a ride coupon before the passenger confirms the ride.
-- Mirrors the reservation rules in reserve_benefit_coupon_for_request, without
-- reserving or changing anything. The reservation trigger still re-checks on insert.
begin;

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

    return jsonb_build_object('valid',true,'kind','program','code',v_code,
      'name',v_program.name,'discount',v_discount,'currency',v_currency,
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

  return jsonb_build_object('valid',true,'kind','user','code',v_code,
    'name','Cupón de regalo','discount',v_discount,'currency',v_currency,
    'message','Cupón válido: descuento de '||v_discount::text||' '||coalesce(v_currency,''));
end $$;

revoke all on function public.validate_benefit_coupon(text,text,numeric,numeric,text,numeric,text) from public,anon;
grant execute on function public.validate_benefit_coupon(text,text,numeric,numeric,text,numeric,text) to authenticated;

commit;
