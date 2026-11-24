-- Route delivery coupons through marketplace and split the discount between Express and driver.
begin;
alter table public.marketplace_coupons add column if not exists channel text not null default 'production' check(channel in ('preview','production'));
alter table public.marketplace_coupons add column if not exists benefit_program_id uuid references public.benefit_programs(id);
alter table public.marketplace_coupons drop constraint if exists marketplace_coupons_funded_by_check;
alter table public.marketplace_coupons add constraint marketplace_coupons_funded_by_check check(funded_by in ('express','merchant','driver','split'));
drop index if exists public.marketplace_coupons_code_idx;
drop index if exists public.marketplace_coupons_channel_code_idx;
create unique index marketplace_coupons_channel_code_idx on public.marketplace_coupons(channel,coalesce(zone_id,'00000000-0000-0000-0000-000000000000'::uuid),lower(code));
create unique index if not exists marketplace_coupons_benefit_program_idx on public.marketplace_coupons(benefit_program_id) where benefit_program_id is not null;

create or replace function public.marketplace_validate_coupon(
  p_code text,
  p_merchant_id uuid,
  p_subtotal numeric,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $$
declare
  v_uid uuid:=auth.uid();
  v_preview boolean:=lower(coalesce(p_channel,'production'))='preview';
  v_zone_id uuid;
  v_country text;
  v_coupon public.marketplace_coupons%rowtype;
  v_total_uses integer:=0;
  v_user_uses integer:=0;
  v_discount numeric(12,2):=0;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select m.zone_id,z.country_code into v_zone_id,v_country
  from public.marketplace_merchants m
  join public.service_zones z on z.id=m.zone_id
  where m.id=p_merchant_id and m.active=true;

  select * into v_coupon
  from public.marketplace_coupons c
  where lower(c.code)=lower(trim(coalesce(p_code,'')))
    and c.active=true
    and (c.benefit_program_id is null or c.channel=p_channel)
    and (c.starts_at is null or c.starts_at<=now())
    and (c.ends_at is null or c.ends_at>now())
    and (c.zone_id is null or c.zone_id=v_zone_id)
    and (c.country_code is null or c.country_code=v_country)
    and case when v_preview then c.preview_visible else c.production_visible end
  limit 1;

  if not found then
    return jsonb_build_object('valid',false,'reason','Cupón no válido para esta zona');
  end if;

  if coalesce(p_subtotal,0)<v_coupon.min_order then
    return jsonb_build_object(
      'valid',false,'reason','No alcanzas el mínimo de compra','min_order',v_coupon.min_order
    );
  end if;

  select count(*)::int into v_total_uses
  from public.marketplace_coupon_redemptions r where r.coupon_id=v_coupon.id;
  select count(*)::int into v_user_uses
  from public.marketplace_coupon_redemptions r
  where r.coupon_id=v_coupon.id and r.user_id=v_uid;

  if v_coupon.usage_limit is not null and v_total_uses>=v_coupon.usage_limit then
    return jsonb_build_object('valid',false,'reason','Cupón agotado');
  end if;
  if v_user_uses>=v_coupon.per_user_limit then
    return jsonb_build_object('valid',false,'reason','Ya usaste este cupón');
  end if;

  if v_coupon.discount_type='percent' then
    v_discount:=round(greatest(p_subtotal,0)*v_coupon.discount_value/100,2);
  else
    v_discount:=least(greatest(p_subtotal,0),v_coupon.discount_value);
  end if;
  if v_coupon.max_discount is not null then
    v_discount:=least(v_discount,v_coupon.max_discount);
  end if;

  return jsonb_build_object(
    'valid',true,'coupon_id',v_coupon.id,'code',upper(v_coupon.code),
    'title',v_coupon.title,'description',v_coupon.description,
    'discount_amount',v_discount,'funded_by',v_coupon.funded_by
  );
end;
$$;


CREATE OR REPLACE FUNCTION public.marketplace_quote_order_v2(p_merchant_id uuid, p_items jsonb, p_distance_km numeric DEFAULT 0, p_tip numeric DEFAULT 0, p_priority boolean DEFAULT false, p_coupon_code text DEFAULT NULL::text, p_donation numeric DEFAULT 0, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_base jsonb;
  v_item jsonb;
  v_product public.marketplace_products%rowtype;
  v_group public.marketplace_product_modifier_groups%rowtype;
  v_qty integer;
  v_modifier_ids uuid[];
  v_selected_count integer;
  v_modifier_total numeric(12,2);
  v_effective numeric(12,2);
  v_actual_subtotal numeric(12,2):=0;
  v_promo_discount numeric(12,2):=0;
  v_plus_discount numeric(12,2):=0;
  v_coupon jsonb:='{}'::jsonb;
  v_coupon_discount numeric(12,2):=0;
  v_coupon_funded_by text:='express';
  v_coupon_driver_share numeric(12,2):=0;
  v_driver_payout numeric(12,2):=0;
  v_merchant_products numeric(12,2):=0;
  v_total numeric(12,2):=0;
  v_margin numeric(12,2):=0;
  v_donation numeric(12,2):=greatest(coalesce(p_donation,0),0);
  v_plus_pct numeric(12,2):=0;
  v_plus_funded_by text:='express';
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_base:=public.marketplace_compute_quote(
    v_uid,p_merchant_id,p_items,p_distance_km,p_tip,p_priority,p_channel
  );

  for v_item in
    select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb))
  loop
    select * into v_product
    from public.marketplace_products p
    where p.id=nullif(v_item->>'product_id','')::uuid
      and p.merchant_id=p_merchant_id
      and p.active=true;
    if not found then raise exception 'Producto no válido'; end if;

    v_qty:=greatest(coalesce((v_item->>'quantity')::int,1),1);
    v_modifier_ids:=array(
      select value::uuid
      from jsonb_array_elements_text(coalesce(v_item->'modifier_ids','[]'::jsonb))
    );

    for v_group in
      select * from public.marketplace_product_modifier_groups g
      where g.product_id=v_product.id and g.active=true
    loop
      select count(*)::int into v_selected_count
      from public.marketplace_product_modifiers o
      where o.group_id=v_group.id and o.active=true
        and o.id=any(v_modifier_ids);

      if v_selected_count<v_group.min_select
         or v_selected_count>v_group.max_select
         or (v_group.required and v_selected_count=0) then
        raise exception 'Selecciona correctamente las opciones de %',v_group.name;
      end if;
    end loop;

    select coalesce(sum(o.price_delta),0) into v_modifier_total
    from public.marketplace_product_modifiers o
    join public.marketplace_product_modifier_groups g on g.id=o.group_id
    where g.product_id=v_product.id and g.active=true and o.active=true
      and o.id=any(v_modifier_ids);

    v_effective:=public.marketplace_product_effective_price(v_product.id);
    v_actual_subtotal:=v_actual_subtotal+(v_effective+v_modifier_total)*v_qty;
    v_promo_discount:=v_promo_discount+greatest(v_product.price-v_effective,0)*v_qty;
  end loop;

  if v_actual_subtotal<=0 then raise exception 'Carrito vacío'; end if;

  v_plus_pct:=coalesce((v_base->>'plus_discount_percent')::numeric,0);
  v_plus_discount:=round(v_actual_subtotal*v_plus_pct/100,2);
  v_plus_funded_by:=coalesce(v_base->>'discount_funded_by','express');

  if nullif(trim(coalesce(p_coupon_code,'')),'') is not null then
    v_coupon:=public.marketplace_validate_coupon(
      p_coupon_code,p_merchant_id,greatest(v_actual_subtotal-v_plus_discount,0),p_channel
    );
    if coalesce((v_coupon->>'valid')::boolean,false) then
      v_coupon_discount:=coalesce((v_coupon->>'discount_amount')::numeric,0);
      v_coupon_funded_by:=coalesce(v_coupon->>'funded_by','express');
    end if;
  end if;

  v_coupon_driver_share:=case v_coupon_funded_by
    when 'driver' then v_coupon_discount
    when 'split' then round(v_coupon_discount/2,2)
    else 0 end;
  v_driver_payout:=greatest(coalesce((v_base->>'driver_payout')::numeric,0)-v_coupon_driver_share,0);

  v_merchant_products:=v_actual_subtotal;
  if v_plus_funded_by='merchant' then
    v_merchant_products:=greatest(v_merchant_products-v_plus_discount,0);
  end if;
  if v_coupon_funded_by='merchant' then
    v_merchant_products:=greatest(v_merchant_products-v_coupon_discount,0);
  end if;

  v_total:=greatest(v_actual_subtotal-v_plus_discount-v_coupon_discount,0)
    +coalesce((v_base->>'customer_delivery_fee')::numeric,0)
    +coalesce((v_base->>'customer_service_fee')::numeric,0)
    +coalesce((v_base->>'priority_fee')::numeric,0)
    +coalesce((v_base->>'tip_amount')::numeric,0)
    +v_donation;

  v_margin:=v_total
    -v_merchant_products
    -v_driver_payout
    -coalesce((v_base->>'tip_amount')::numeric,0)
    -v_donation;

  return v_base || jsonb_build_object(
    'subtotal',v_actual_subtotal,
    'promotion_discount',v_promo_discount,
    'plus_discount',v_plus_discount,
    'coupon',v_coupon,
    'coupon_discount',v_coupon_discount,
    'donation_amount',v_donation,
    'product_discount',v_plus_discount+v_coupon_discount,
    'merchant_products_amount',v_merchant_products,
    'total_amount',v_total,
    'driver_payout',v_driver_payout,
    'coupon_driver_share',v_coupon_driver_share,
    'express_margin',v_margin
  );
end;
$function$;


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
    if coalesce(p_config->>'service_mode','transport') not in ('transport','delivery') then
      raise exception 'El servicio del cupón no es válido';
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
create or replace function public.sync_benefit_program_marketplace_coupon()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_country text; v_funded_by text;
begin
  if new.program_type<>'coupon' then return new; end if;
  if coalesce(new.config->>'service_mode','transport')<>'delivery' or new.state<>'active' then
    update public.marketplace_coupons set active=false,updated_at=now() where benefit_program_id=new.id;
    return new;
  end if;
  select country_code into v_country from public.service_zones where id=new.zone_id;
  v_funded_by:=case coalesce(new.config->>'discount_absorber','company')
    when 'driver' then 'driver' when 'split' then 'split' else 'express' end;
  insert into public.marketplace_coupons(zone_id,country_code,channel,benefit_program_id,code,title,description,
    discount_type,discount_value,min_order,max_discount,funded_by,usage_limit,per_user_limit,starts_at,ends_at,
    active,preview_visible,production_visible)
  values(new.zone_id,v_country,new.channel,new.id,upper(trim(new.config->>'code')),new.name,nullif(new.description,''),
    new.config->>'discount_type',(new.config->>'value')::numeric,coalesce(nullif(new.config->>'min_fare','')::numeric,0),
    nullif(new.config->>'max_discount','')::numeric,v_funded_by,nullif(new.config->>'max_total_uses','')::integer,
    coalesce(nullif(new.config->>'uses_per_user','')::integer,1),new.starts_at,new.ends_at,true,
    new.channel='preview',new.channel='production')
  on conflict(benefit_program_id) where benefit_program_id is not null do update set
    zone_id=excluded.zone_id,country_code=excluded.country_code,channel=excluded.channel,code=excluded.code,
    title=excluded.title,description=excluded.description,discount_type=excluded.discount_type,
    discount_value=excluded.discount_value,min_order=excluded.min_order,max_discount=excluded.max_discount,
    funded_by=excluded.funded_by,usage_limit=excluded.usage_limit,per_user_limit=excluded.per_user_limit,
    starts_at=excluded.starts_at,ends_at=excluded.ends_at,active=true,
    preview_visible=excluded.preview_visible,production_visible=excluded.production_visible,updated_at=now();
  return new;
end $$;
drop trigger if exists benefit_program_marketplace_coupon_sync on public.benefit_programs;
create trigger benefit_program_marketplace_coupon_sync after insert or update of config,state,starts_at,ends_at,name,description
  on public.benefit_programs for each row execute function public.sync_benefit_program_marketplace_coupon();
revoke all on function public.sync_benefit_program_marketplace_coupon() from public,anon,authenticated;

commit;
