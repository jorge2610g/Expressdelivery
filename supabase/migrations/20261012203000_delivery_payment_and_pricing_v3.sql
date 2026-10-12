-- Delivery v3 Preview-safe: separate fees, merchant approval and private finance surface.
begin;
alter table public.marketplace_zone_settings
 add column if not exists driver_pickup_fee numeric(14,2),
 add column if not exists driver_dropoff_fee numeric(14,2) not null default 0,
 add column if not exists customer_service_fee numeric(14,2) not null default 0;
alter table public.marketplace_orders
 add column if not exists driver_pickup_payout numeric(14,2) not null default 0,
 add column if not exists driver_dropoff_payout numeric(14,2) not null default 0,
 add column if not exists customer_service_fee numeric(14,2) not null default 0;
-- Production remains disabled; all new rates are initially zero / legacy equivalent.

CREATE OR REPLACE FUNCTION public.marketplace_compute_quote(p_customer_id uuid, p_merchant_id uuid, p_items jsonb, p_distance_km numeric DEFAULT 0, p_tip numeric DEFAULT 0, p_priority boolean DEFAULT false, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_merchant public.marketplace_merchants%rowtype;
  v_zone public.service_zones%rowtype;
  v_cfg public.marketplace_zone_settings%rowtype;
  v_subscription public.marketplace_plus_subscriptions%rowtype;
  v_plan public.marketplace_plus_plans%rowtype;
  v_subtotal numeric(12,2):=0;
  v_discount numeric(12,2):=0;
  v_customer_fee numeric(12,2):=0;
  v_priority_fee numeric(12,2):=0;
  v_driver_base numeric(12,2):=0;
  v_driver_distance numeric(12,2):=0;
  v_driver_bonus numeric(12,2):=0;
  v_driver_payout numeric(12,2):=0;
  v_tip numeric(12,2):=greatest(coalesce(p_tip,0),0);
  v_total numeric(12,2):=0;
  v_margin numeric(12,2):=0;
  v_merchant_products numeric(12,2):=0;
  v_has_plus boolean:=false;
  v_benefit public.marketplace_plus_merchant_benefits%rowtype;
  v_plus_discount numeric(6,2):=0;
  v_free_delivery boolean:=false;
  v_discount_funded_by text:='express';
  v_priority_remaining integer:=0;
  v_priority_included boolean:=false;
  v_rows integer:=0;
begin
  select * into v_merchant
  from public.marketplace_merchants
  where id=p_merchant_id and active=true;
  if not found then raise exception 'Comercio no disponible'; end if;

  select * into v_zone
  from public.service_zones
  where id=v_merchant.zone_id;
  if not found then raise exception 'Zona no encontrada'; end if;

  select * into v_cfg
  from public.marketplace_zone_settings
  where zone_id=v_zone.id;
  if not found then
    raise exception 'Tarifas Delivery no configuradas para esta zona';
  end if;

  if lower(coalesce(p_channel,'production'))='preview' then
    if not v_cfg.preview_enabled then
      raise exception 'Delivery Preview desactivado';
    end if;
  else
    if not v_cfg.production_enabled then
      raise exception 'Delivery Producción desactivado';
    end if;
  end if;

  with requested as (
    select
      nullif(x->>'product_id','')::uuid product_id,
      greatest(coalesce((x->>'quantity')::int,1),1) quantity
    from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
  ),
  valid as (
    select
      p.id,p.name,p.price,r.quantity,
      (p.price*r.quantity)::numeric line_total
    from requested r
    join public.marketplace_products p on p.id=r.product_id
    where p.merchant_id=p_merchant_id and p.active=true
  )
  select coalesce(sum(line_total),0),count(*)
  into v_subtotal,v_rows
  from valid;

  if v_rows=0 or v_subtotal<=0 then
    raise exception 'Carrito vacío';
  end if;

  v_customer_fee:=greatest(
    v_cfg.customer_min_fee,
    v_cfg.customer_base_fee
      + greatest(coalesce(p_distance_km,0),0)*v_cfg.customer_per_km
  );

  v_driver_base:=coalesce(v_cfg.driver_pickup_fee,v_cfg.driver_base_payout);
  v_driver_distance:=
    greatest(coalesce(p_distance_km,0),0)*v_cfg.driver_per_km;
  v_driver_payout:=greatest(
    v_cfg.driver_min_payout,
    v_driver_base+v_driver_distance+coalesce(v_cfg.driver_dropoff_fee,0)
  );

  if v_cfg.plus_enabled then
    select s.* into v_subscription
    from public.marketplace_plus_subscriptions s
    join public.marketplace_plus_plans p on p.id=s.plan_id
    where s.customer_id=p_customer_id
      and p.zone_id=v_zone.id
      and s.status='active'
      and s.started_at<=now()
      and s.expires_at>now()
      and p.active=true
    order by s.expires_at desc
    limit 1;

    v_has_plus:=found;

    if v_has_plus then
      select * into v_plan
      from public.marketplace_plus_plans
      where id=v_subscription.plan_id;

      v_priority_remaining:=greatest(
        coalesce(v_plan.included_priority_deliveries,0)
          - coalesce(v_subscription.priority_deliveries_used,0),
        0
      );
    end if;
  end if;

  if coalesce(p_priority,false) and v_cfg.priority_enabled then
    v_priority_fee:=v_cfg.priority_customer_fee;
    v_driver_bonus:=v_cfg.priority_driver_bonus;
    v_driver_payout:=v_driver_payout+v_driver_bonus;

    if v_has_plus and v_priority_remaining>0 then
      v_priority_fee:=0;
      v_priority_included:=true;
    end if;
  end if;

  if not v_cfg.tips_enabled then
    v_tip:=0;
  end if;

  if v_has_plus then
    select * into v_benefit
    from public.marketplace_plus_merchant_benefits
    where merchant_id=p_merchant_id and enabled=true;

    if found then
      v_plus_discount:=greatest(
        least(coalesce(v_benefit.discount_percent,0),100),
        0
      );
      v_discount:=round(v_subtotal*v_plus_discount/100,2);
      v_free_delivery:=coalesce(v_benefit.free_delivery,false);
      v_discount_funded_by:=coalesce(v_benefit.funded_by,'express');
    else
      v_plus_discount:=coalesce(v_plan.default_discount_percent,0);
      v_free_delivery:=coalesce(v_plan.free_delivery,false);
      v_discount:=round(
        v_subtotal*coalesce(v_plus_discount,0)/100,
        2
      );
      v_discount_funded_by:='express';
    end if;

    if v_free_delivery then
      v_customer_fee:=0;
    end if;
  end if;

  v_merchant_products:=case
    when v_discount_funded_by='merchant'
    then greatest(v_subtotal-v_discount,0)
    else v_subtotal
  end;

  v_total:=greatest(v_subtotal-v_discount,0)
    +v_customer_fee+v_priority_fee+v_tip+coalesce(v_cfg.customer_service_fee,0);

  v_margin:=v_total
    - v_merchant_products
    - v_driver_payout
    - v_tip;

  return jsonb_build_object(
    'zone_id',v_zone.id,
    'zone_key',v_zone.zone_key,
    'currency_code',v_zone.currency_code,
    'subtotal',v_subtotal,
    'product_discount',v_discount,
    'discount_funded_by',v_discount_funded_by,
    'customer_delivery_fee',v_customer_fee,
    'priority_fee',v_priority_fee,
    'tip_amount',v_tip,
    'total_amount',v_total,
    'driver_base_payout',v_driver_base,
    'driver_pickup_payout',v_driver_base,
    'driver_dropoff_payout',coalesce(v_cfg.driver_dropoff_fee,0),
    'customer_service_fee',coalesce(v_cfg.customer_service_fee,0),
    'driver_distance_payout',v_driver_distance,
    'driver_priority_bonus',v_driver_bonus,
    'driver_payout',v_driver_payout,
    'merchant_products_amount',v_merchant_products,
    'express_margin',v_margin,
    'is_priority',
      coalesce(p_priority,false) and v_cfg.priority_enabled,
    'plus_subscription_applied',v_has_plus,
    'plus_subscription_id',
      case when v_has_plus then v_subscription.id else null end,
    'plus_free_delivery_applied',
      v_has_plus and v_free_delivery,
    'plus_discount_percent',
      case
        when v_has_plus then coalesce(v_plus_discount,0)
        else 0
      end,
    'plus_priority_included_applied',v_priority_included,
    'plus_priority_deliveries_remaining',v_priority_remaining,
    'plus_priority_deliveries_remaining_after_order',
      case
        when v_priority_included
        then greatest(v_priority_remaining-1,0)
        else v_priority_remaining
      end,
    'tips_enabled',v_cfg.tips_enabled,
    'cash_enabled',v_cfg.cash_enabled,
    'transfer_enabled',v_cfg.transfer_enabled,
    'online_enabled',v_cfg.online_enabled,
    'priority_enabled',v_cfg.priority_enabled
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.marketplace_create_order_v2(p_merchant_id uuid, p_items jsonb, p_distance_km numeric, p_tip numeric, p_priority boolean, p_payment_method text, p_dropoff_address text, p_dropoff_lat numeric DEFAULT NULL::numeric, p_dropoff_lng numeric DEFAULT NULL::numeric, p_saved_address_id uuid DEFAULT NULL::uuid, p_merchant_note text DEFAULT NULL::text, p_delivery_instructions text DEFAULT NULL::text, p_delivery_option text DEFAULT 'door'::text, p_coupon_code text DEFAULT NULL::text, p_donation numeric DEFAULT 0, p_billing_profile_id uuid DEFAULT NULL::uuid, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_quote jsonb;
  v_order public.marketplace_orders%rowtype;
  v_method text:=lower(trim(coalesce(p_payment_method,'')));
  v_collector text;
  v_item jsonb;
  v_product public.marketplace_products%rowtype;
  v_qty integer;
  v_modifier_ids uuid[];
  v_modifier_total numeric(12,2);
  v_selected_modifiers jsonb;
  v_effective numeric(12,2);
  v_billing jsonb:='{}'::jsonb;
  v_coupon_id uuid;
  v_coupon_discount numeric(12,2):=0;
  v_consumed integer;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if v_method not in ('cash','transfer','mercado_pago','wallet') then
    raise exception 'Método de pago no válido';
  end if;

  if p_delivery_option not in ('door','call','concierge','leave_at_door') then
    raise exception 'Opción de entrega no válida';
  end if;

  v_quote:=public.marketplace_quote_order_v2(
    p_merchant_id,p_items,p_distance_km,p_tip,p_priority,
    p_coupon_code,p_donation,p_channel
  );

  if v_method='cash' and coalesce((v_quote->>'cash_enabled')::boolean,false)=false then
    raise exception 'Efectivo no disponible';
  end if;
  if v_method='transfer' and coalesce((v_quote->>'transfer_enabled')::boolean,false)=false then
    raise exception 'Transferencia no disponible';
  end if;
  if v_method in ('mercado_pago','wallet')
     and coalesce((v_quote->>'online_enabled')::boolean,false)=false then
    raise exception 'Pago online no disponible';
  end if;

  if p_saved_address_id is not null and not exists(
    select 1 from public.saved_addresses a
    where a.id=p_saved_address_id and a.user_id=v_uid
  ) then
    raise exception 'Dirección no válida';
  end if;

  if p_billing_profile_id is not null then
    select to_jsonb(b) into v_billing
    from public.marketplace_billing_profiles b
    where b.id=p_billing_profile_id and b.user_id=v_uid
      and b.country_code=(select z.country_code from public.service_zones z where z.id=(v_quote->>'zone_id')::uuid);
    if v_billing is null then raise exception 'Datos de facturación no válidos'; end if;
  end if;

  v_collector:=case
    when v_method='cash' then 'driver'
    when v_method='transfer' then 'merchant'
    else 'express'
  end;

  v_coupon_id:=nullif(v_quote->'coupon'->>'coupon_id','')::uuid;
  v_coupon_discount:=coalesce((v_quote->>'coupon_discount')::numeric,0);

  insert into public.marketplace_orders(
    customer_id,merchant_id,zone_id,channel,status,payment_method,payment_status,
    currency_code,subtotal,product_discount,customer_delivery_fee,customer_service_fee,priority_fee,tip_amount,
    total_amount,driver_base_payout,driver_pickup_payout,driver_distance_payout,driver_dropoff_payout,driver_priority_bonus,driver_payout,
    express_margin,merchant_products_amount,collector,distance_km,is_priority,
    plus_subscription_applied,plus_subscription_id,plus_free_delivery_applied,
    plus_priority_included_applied,plus_discount_percent,
    dropoff_address,dropoff_latitude,dropoff_longitude,saved_address_id,
    merchant_note,delivery_instructions,delivery_option,coupon_id,coupon_code,coupon_discount,
    billing_profile_snapshot,donation_amount
  )
  values(
    v_uid,p_merchant_id,(v_quote->>'zone_id')::uuid,lower(coalesce(p_channel,'production')),
    case when v_method='transfer' then 'awaiting_merchant' else 'pending' end,
    v_method,
    case when v_method='transfer' then 'awaiting_merchant' else 'pending' end,
    v_quote->>'currency_code',
    (v_quote->>'subtotal')::numeric,
    (v_quote->>'product_discount')::numeric,
    (v_quote->>'customer_delivery_fee')::numeric,
    (v_quote->>'customer_service_fee')::numeric,
    (v_quote->>'priority_fee')::numeric,
    (v_quote->>'tip_amount')::numeric,
    (v_quote->>'total_amount')::numeric,
    (v_quote->>'driver_base_payout')::numeric,
    (v_quote->>'driver_pickup_payout')::numeric,
    (v_quote->>'driver_distance_payout')::numeric,
    (v_quote->>'driver_dropoff_payout')::numeric,
    (v_quote->>'driver_priority_bonus')::numeric,
    (v_quote->>'driver_payout')::numeric,
    (v_quote->>'express_margin')::numeric,
    (v_quote->>'merchant_products_amount')::numeric,
    v_collector,greatest(coalesce(p_distance_km,0),0),
    (v_quote->>'is_priority')::boolean,
    (v_quote->>'plus_subscription_applied')::boolean,
    nullif(v_quote->>'plus_subscription_id','')::uuid,
    (v_quote->>'plus_free_delivery_applied')::boolean,
    coalesce((v_quote->>'plus_priority_included_applied')::boolean,false),
    (v_quote->>'plus_discount_percent')::numeric,
    trim(p_dropoff_address),p_dropoff_lat,p_dropoff_lng,p_saved_address_id,
    nullif(trim(coalesce(p_merchant_note,'')),''),
    nullif(trim(coalesce(p_delivery_instructions,'')),''),
    p_delivery_option,v_coupon_id,
    case when v_coupon_id is null then null else upper(trim(p_coupon_code)) end,
    v_coupon_discount,coalesce(v_billing,'{}'::jsonb),greatest(coalesce(p_donation,0),0)
  )
  returning * into v_order;

  if v_order.plus_priority_included_applied then
    update public.marketplace_plus_subscriptions s
    set priority_deliveries_used=s.priority_deliveries_used+1,updated_at=now()
    from public.marketplace_plus_plans p
    where s.id=v_order.plus_subscription_id and p.id=s.plan_id
      and s.status='active' and s.started_at<=now() and s.expires_at>now()
      and s.priority_deliveries_used<p.included_priority_deliveries
    returning s.priority_deliveries_used into v_consumed;
    if not found then
      raise exception 'El cupo de envíos prioritarios cambió; vuelve a cotizar';
    end if;
  end if;

  for v_item in
    select value from jsonb_array_elements(coalesce(p_items,'[]'::jsonb))
  loop
    select * into v_product
    from public.marketplace_products p
    where p.id=nullif(v_item->>'product_id','')::uuid
      and p.merchant_id=p_merchant_id and p.active=true;
    if not found then raise exception 'Producto no válido'; end if;

    v_qty:=greatest(coalesce((v_item->>'quantity')::int,1),1);
    v_modifier_ids:=array(
      select value::uuid
      from jsonb_array_elements_text(coalesce(v_item->'modifier_ids','[]'::jsonb))
    );
    select coalesce(sum(o.price_delta),0),
           coalesce(jsonb_agg(jsonb_build_object(
             'id',o.id,'group_id',g.id,'group_name',g.name,'name',o.name,'price_delta',o.price_delta
           ) order by g.sort_order,o.sort_order),'[]'::jsonb)
    into v_modifier_total,v_selected_modifiers
    from public.marketplace_product_modifiers o
    join public.marketplace_product_modifier_groups g on g.id=o.group_id
    where g.product_id=v_product.id and g.active=true and o.active=true
      and o.id=any(v_modifier_ids);

    v_effective:=public.marketplace_product_effective_price(v_product.id);

    insert into public.marketplace_order_items(
      order_id,product_id,product_name,quantity,unit_price,line_total,
      base_unit_price,modifiers_total,selected_modifiers,customer_note,promotion_discount
    )
    values(
      v_order.id,v_product.id,v_product.name,v_qty,
      v_effective+v_modifier_total,
      (v_effective+v_modifier_total)*v_qty,
      v_effective,v_modifier_total,coalesce(v_selected_modifiers,'[]'::jsonb),
      nullif(trim(coalesce(v_item->>'note','')),''),
      greatest(v_product.price-v_effective,0)*v_qty
    );

    update public.marketplace_products
    set sold_count=sold_count+v_qty,updated_at=now()
    where id=v_product.id;
  end loop;

  if v_coupon_id is not null and v_coupon_discount>0 then
    insert into public.marketplace_coupon_redemptions(
      coupon_id,user_id,order_id,discount_amount
    )
    values(v_coupon_id,v_uid,v_order.id,v_coupon_discount);
  end if;

  insert into public.marketplace_order_financials(
    order_id,customer_total,merchant_products_amount,driver_payout,driver_tip,
    express_margin,collector,merchant_owes_driver,merchant_owes_express,
    driver_owes_merchant,driver_owes_express,express_owes_merchant,express_owes_driver
  )
  values(
    v_order.id,v_order.total_amount,v_order.merchant_products_amount,v_order.driver_payout,
    v_order.tip_amount,v_order.express_margin,v_collector,
    case when v_collector='merchant' then v_order.driver_payout+v_order.tip_amount else 0 end,
    case when v_collector='merchant' then greatest(v_order.express_margin,0) else 0 end,
    case when v_collector='driver' then v_order.merchant_products_amount else 0 end,
    case when v_collector='driver' then greatest(v_order.express_margin,0) else 0 end,
    case
      when v_collector='express' then v_order.merchant_products_amount
      when v_collector='merchant' and v_order.express_margin<0 then abs(v_order.express_margin)
      else 0 end,
    case
      when v_collector='express' then v_order.driver_payout+v_order.tip_amount
      when v_collector='driver' and v_order.express_margin<0 then abs(v_order.express_margin)
      else 0 end
  );

  insert into public.marketplace_order_messages(order_id,sender_id,sender_role,message_type,body)
  values(
    v_order.id,v_uid,'system','system',
    case
      when v_method='transfer' then 'Pedido creado. Esperando aceptación del restaurante antes de transferir.'
      when v_method='cash' then 'Pedido creado con pago en efectivo.'
      else 'Pedido creado. Esperando confirmación del pago online.'
    end
  );

  insert into public.notifications(user_id,title,body,type,metadata)
  select mu.user_id,'Nuevo pedido Express Delivery',
         'Tienes un nuevo pedido para revisar.','marketplace_order',
         jsonb_build_object('marketplace_order_id',v_order.id,'merchant_id',p_merchant_id)
  from public.marketplace_merchant_users mu
  where mu.merchant_id=p_merchant_id;

  return jsonb_build_object('order',to_jsonb(v_order),'quote',v_quote);
end;
$function$;

CREATE OR REPLACE FUNCTION public.marketplace_merchant_orders(p_merchant_id uuid, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'No autorizado'; end if;

  if not public.is_admin()
     and not exists(
       select 1
       from public.marketplace_merchant_users mu
       where mu.merchant_id=p_merchant_id
         and mu.user_id=v_uid
         and mu.active=true
     ) then
    raise exception 'No autorizado';
  end if;

  return (
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.created_at desc),
      '[]'::jsonb
    )
    from (
      select
        o.id,o.status,o.payment_method,o.payment_status,
        o.currency_code,o.total_amount,o.tip_amount,
        o.driver_payout,o.created_at,
        o.transfer_receipt_url,o.transfer_submitted_at,
        o.assigned_driver_id,o.is_priority,
        u.full_name customer_name,
        u.phone customer_phone
      from public.marketplace_orders o
      left join public.users u on u.id=o.customer_id
      where o.merchant_id=p_merchant_id
      order by o.created_at desc
      limit greatest(least(coalesce(p_limit,50),100),1)
    ) x
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.marketplace_order_detail(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_allowed boolean:=false;
begin
  if v_uid is null then raise exception 'No autorizado'; end if;

  select * into v_order
  from public.marketplace_orders
  where id=p_order_id;
  if not found then raise exception 'Pedido no encontrado'; end if;

  v_allowed:=v_order.customer_id=v_uid
    or v_order.assigned_driver_id=v_uid
    or public.is_admin()
    or exists(
      select 1
      from public.marketplace_merchant_users mu
      where mu.merchant_id=v_order.merchant_id
        and mu.user_id=v_uid
        and mu.active=true
    );

  if not v_allowed then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'order',to_jsonb(v_order) - 'express_margin' - 'driver_base_payout'
      - 'driver_distance_payout' - 'driver_priority_bonus'
      - 'driver_pickup_payout' - 'driver_dropoff_payout',
    'merchant',(
      select to_jsonb(m)
      from public.marketplace_merchants m
      where m.id=v_order.merchant_id
    ),
    'items',(
      select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb)
      from public.marketplace_order_items i
      where i.order_id=p_order_id
    ),
    'messages',(
      select coalesce(
        jsonb_agg(to_jsonb(msg) order by msg.created_at),
        '[]'::jsonb
      )
      from public.marketplace_order_messages msg
      where msg.order_id=p_order_id
    ),
    'financials',(
      select case
        when public.is_admin() then to_jsonb(f)
        when exists(select 1 from public.marketplace_merchant_users mu
          where mu.merchant_id=v_order.merchant_id
          and mu.user_id=v_uid and mu.active) then
          jsonb_build_object(
            'customer_total',f.customer_total,
            'merchant_products_amount',f.merchant_products_amount,
            'driver_payout',f.driver_payout,
            'driver_tip',f.driver_tip,
            'merchant_owes_driver',f.merchant_owes_driver,
            'merchant_owes_express',f.merchant_owes_express,
            'driver_owes_merchant',f.driver_owes_merchant,
            'settlement_status',f.settlement_status
          )
        else '{}'::jsonb end
      from public.marketplace_order_financials f
      where f.order_id=p_order_id
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.marketplace_send_order_message(p_order_id uuid, p_body text DEFAULT NULL::text, p_attachment_url text DEFAULT NULL::text, p_message_type text DEFAULT 'text'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_role text;
  v_message public.marketplace_order_messages%rowtype;
begin
  if v_uid is null then raise exception 'No autorizado'; end if;

  select * into v_order
  from public.marketplace_orders
  where id=p_order_id;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if v_order.customer_id=v_uid then
    v_role:='customer';
  elsif public.is_admin() then
    v_role:='admin';
  elsif exists(
    select 1 from public.marketplace_merchant_users mu
    where mu.merchant_id=v_order.merchant_id
      and mu.user_id=v_uid
      and mu.active=true
  ) then
    v_role:='merchant';
  else
    raise exception 'No autorizado';
  end if;

  if p_message_type='bank_details' then
    if v_role<>'merchant' or v_order.payment_method<>'transfer'
       or v_order.status not in ('awaiting_transfer','payment_review') then
      raise exception 'Datos bancarios solo tras aceptación del restaurante';
    end if;
  end if;
  if p_message_type='receipt' then
    if v_role<>'customer' or v_order.payment_method<>'transfer'
       or v_order.status<>'awaiting_transfer'
       or (coalesce(nullif(trim(p_body),''),nullif(trim(p_attachment_url),'')) is null) then
      raise exception 'Comprobante solo después de que el restaurante acepte el pedido';
    end if;
  end if;
  insert into public.marketplace_order_messages(
    order_id,sender_id,sender_role,message_type,body,attachment_url
  )
  values(
    p_order_id,v_uid,v_role,
    case when p_message_type in ('text','bank_details','receipt')
      then p_message_type else 'text' end,
    nullif(trim(coalesce(p_body,'')),''),
    nullif(trim(coalesce(p_attachment_url,'')),'')
  )
  returning * into v_message;

  if v_role='customer'
     and v_message.message_type='receipt'
     and v_order.payment_method='transfer' then
    update public.marketplace_orders
    set
      transfer_receipt_url=v_message.attachment_url,
      transfer_submitted_at=now(),
      payment_status='under_review',
      status='payment_review',
      updated_at=now()
    where id=p_order_id;
  end if;

  return to_jsonb(v_message);
end;
$function$;

CREATE OR REPLACE FUNCTION public.marketplace_review_transfer(p_order_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_allowed boolean:=false;
begin
  if v_uid is null then raise exception 'No autorizado'; end if;

  select * into v_order
  from public.marketplace_orders
  where id=p_order_id
  for update;
  if not found then raise exception 'Pedido no encontrado'; end if;

  v_allowed:=public.is_admin()
    or exists(
      select 1
      from public.marketplace_merchant_users mu
      where mu.merchant_id=v_order.merchant_id
        and mu.user_id=v_uid
        and mu.active=true
    );
  if not v_allowed then raise exception 'No autorizado'; end if;

  if v_order.payment_method<>'transfer' then
    raise exception 'El pedido no usa transferencia';
  end if;

  if v_order.status<>'payment_review'
     or v_order.payment_status<>'under_review'
     or v_order.transfer_submitted_at is null then
    raise exception 'No hay un comprobante pendiente de revisión';
  end if;
  if p_approve then
    update public.marketplace_orders
    set
      payment_status='paid',
      status='confirmed',
      transfer_reviewed_at=now(),
      transfer_reviewed_by=v_uid,
      updated_at=now()
    where id=p_order_id;
  else
    update public.marketplace_orders
    set
      payment_status='rejected',
      status='awaiting_transfer',
      transfer_reviewed_at=now(),
      transfer_reviewed_by=v_uid,
      updated_at=now()
    where id=p_order_id;
  end if;

  if nullif(trim(coalesce(p_note,'')),'') is not null then
    insert into public.marketplace_order_messages(
      order_id,sender_id,sender_role,message_type,body
    )
    values(
      p_order_id,v_uid,
      case when public.is_admin() then 'admin' else 'merchant' end,
      'text',trim(p_note)
    );
  end if;

  return public.marketplace_order_detail(p_order_id);
end;
$function$;

create or replace function public.marketplace_merchant_accept_transfer(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_order public.marketplace_orders%rowtype; v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'No autorizado'; end if;
 select * into v_order from public.marketplace_orders where id=p_order_id for update;
 if v_order.id is null or not (
   public.is_admin() or exists(select 1 from public.marketplace_merchant_users mu
     where mu.merchant_id=v_order.merchant_id and mu.user_id=v_uid and mu.active)
 ) then raise exception 'No autorizado para aceptar este pedido'; end if;
 if v_order.payment_method<>'transfer' or v_order.status<>'awaiting_merchant'
   or v_order.payment_status<>'awaiting_merchant' then
   raise exception 'Este pedido no espera aceptación para transferencia'; end if;
 update public.marketplace_orders set status='awaiting_transfer',
    payment_status='awaiting_receipt',updated_at=now() where id=p_order_id;
 insert into public.marketplace_order_messages(
   order_id,sender_id,sender_role,message_type,body
 ) values (p_order_id,v_uid,'merchant','system',
   'Restaurante disponible. Puedes solicitar los datos bancarios y transferir.');
 return public.marketplace_order_detail(p_order_id);
end $$;
revoke all on function public.marketplace_merchant_accept_transfer(uuid) from public,anon;
grant execute on function public.marketplace_merchant_accept_transfer(uuid) to authenticated;

-- Additional delivery rates without altering existing Taxi tariffs.
create or replace function public.admin_marketplace_delivery_rate_components(
 p_zone_id uuid,p_pickup numeric,p_km numeric,p_dropoff numeric,
 p_service_fee numeric
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_access jsonb:=public.admin_access_context();v_zone text;
begin
 if auth.uid() is null or not public.is_admin()
   or v_access->>'role'<>'super_admin'
   or (v_access->>'zone_id' is not null
      and (v_access->>'zone_id')::uuid<>p_zone_id) then
   raise exception 'No autorizado'; end if;
 select z.currency_code into v_zone from public.service_zones z
 where z.id=p_zone_id and z.active;
 if v_zone is null then raise exception 'Zona no disponible'; end if;
 if p_pickup<0 or p_km<0 or p_dropoff<0 or p_service_fee<0
   or greatest(p_pickup,p_km,p_dropoff,p_service_fee)>100000
   or (v_zone='CLP' and (
      mod(p_pickup,1)<>0 or mod(p_km,1)<>0 or
      mod(p_dropoff,1)<>0 or mod(p_service_fee,1)<>0))
   then raise exception 'Tarifas fuera de rango'; end if;
 update public.marketplace_zone_settings
 set driver_pickup_fee=p_pickup,driver_per_km=p_km,
     driver_dropoff_fee=p_dropoff,customer_service_fee=p_service_fee,
     updated_at=now() where zone_id=p_zone_id;
 if not found then raise exception 'Configura primero Delivery para esta ciudad'; end if;
 perform public.admin_log_action('update','marketplace_delivery_rates',p_zone_id::text,
    jsonb_build_object('pickup',p_pickup,'km',p_km,'dropoff',p_dropoff,
      'service_fee',p_service_fee,'currency',v_zone));
 return (select to_jsonb(s) from public.marketplace_zone_settings s
   where s.zone_id=p_zone_id);
end $$;
revoke all on function public.admin_marketplace_delivery_rate_components(uuid,numeric,numeric,numeric,numeric) from public,anon;
grant execute on function public.admin_marketplace_delivery_rate_components(uuid,numeric,numeric,numeric,numeric) to authenticated;
commit;