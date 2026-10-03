-- Express Plus priority allowance accounting.
-- Prepared after rollback-only QA against the live schema.
-- Preview/Production feature flags are unchanged by this migration.

alter table public.marketplace_plus_subscriptions
  add column if not exists priority_deliveries_used integer not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname='marketplace_plus_subscriptions_priority_used_check'
      and conrelid='public.marketplace_plus_subscriptions'::regclass
  ) then
    alter table public.marketplace_plus_subscriptions
      add constraint marketplace_plus_subscriptions_priority_used_check
      check(priority_deliveries_used>=0);
  end if;
end
$$;

alter table public.marketplace_orders
  add column if not exists plus_subscription_id uuid
    references public.marketplace_plus_subscriptions(id) on delete set null,
  add column if not exists plus_priority_included_applied boolean not null default false;

create index if not exists marketplace_orders_plus_subscription_idx
  on public.marketplace_orders(plus_subscription_id);

create or replace function public.marketplace_has_plus(
  p_customer_id uuid,
  p_zone_id uuid
)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select exists(
    select 1
    from public.marketplace_plus_subscriptions s
    join public.marketplace_plus_plans p on p.id=s.plan_id
    where s.customer_id=p_customer_id
      and p.zone_id=p_zone_id
      and s.status='active'
      and s.started_at<=now()
      and s.expires_at>now()
      and p.active=true
  );
$function$;

create or replace function public.marketplace_activate_plus(
  p_customer_id uuid,
  p_plan_id uuid,
  p_provider text,
  p_provider_reference text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_plan public.marketplace_plus_plans%rowtype;
  v_existing public.marketplace_plus_subscriptions%rowtype;
  v_start timestamptz:=now();
  v_end timestamptz;
  v_subscription_id uuid;
begin
  select * into v_plan
  from public.marketplace_plus_plans
  where id=p_plan_id and active=true;
  if not found then raise exception 'Plan Express Plus no disponible'; end if;

  select * into v_existing
  from public.marketplace_plus_subscriptions
  where customer_id=p_customer_id
    and plan_id=p_plan_id
    and status='active'
  order by expires_at desc
  limit 1
  for update;

  if found and v_existing.expires_at>now() then
    v_start:=v_existing.expires_at;
  end if;

  v_end:=v_start+interval '30 days';

  insert into public.marketplace_plus_subscriptions(
    customer_id,plan_id,status,started_at,expires_at,
    auto_renew,provider,provider_reference,priority_deliveries_used,updated_at
  )
  values(
    p_customer_id,p_plan_id,'active',v_start,v_end,
    false,p_provider,p_provider_reference,0,now()
  )
  returning id into v_subscription_id;

  return jsonb_build_object(
    'active',v_start<=now(),
    'subscription_id',v_subscription_id,
    'plan_id',p_plan_id,
    'started_at',v_start,
    'expires_at',v_end
  );
end;
$function$;

create or replace function public.marketplace_plus_state(
  p_channel text default 'production'::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_zone_id uuid;
  v_zone_key text;
  v_subscription jsonb;
  v_plans jsonb;
begin
  if v_uid is null then raise exception 'No autorizado'; end if;

  select u.last_zone_id into v_zone_id
  from public.users u
  where u.id=v_uid;

  select zone_key into v_zone_key
  from public.service_zones
  where id=v_zone_id;

  select
    to_jsonb(s) ||
    jsonb_build_object(
      'plan_name',p.name,
      'included_priority_deliveries',p.included_priority_deliveries,
      'priority_deliveries_remaining',
        greatest(
          coalesce(p.included_priority_deliveries,0)
          - coalesce(s.priority_deliveries_used,0),
          0
        )
    )
  into v_subscription
  from public.marketplace_plus_subscriptions s
  join public.marketplace_plus_plans p on p.id=s.plan_id
  where s.customer_id=v_uid
    and p.zone_id=v_zone_id
    and s.status='active'
    and s.started_at<=now()
    and s.expires_at>now()
    and p.active=true
  order by s.expires_at desc
  limit 1;

  select coalesce(
    jsonb_agg(to_jsonb(p) order by p.monthly_price),
    '[]'::jsonb
  )
  into v_plans
  from public.marketplace_plus_plans p
  where p.zone_id=v_zone_id
    and p.active=true
    and case
      when lower(coalesce(p_channel,'production'))='preview'
      then p.preview_visible
      else p.production_visible
    end;

  return jsonb_build_object(
    'zone_id',v_zone_id,
    'zone_key',v_zone_key,
    'active',v_subscription is not null,
    'subscription',v_subscription,
    'plans',coalesce(v_plans,'[]'::jsonb)
  );
end;
$function$;

create or replace function public.marketplace_compute_quote(
  p_customer_id uuid,
  p_merchant_id uuid,
  p_items jsonb,
  p_distance_km numeric default 0,
  p_tip numeric default 0,
  p_priority boolean default false,
  p_channel text default 'production'::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
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

  v_driver_base:=v_cfg.driver_base_payout;
  v_driver_distance:=
    greatest(coalesce(p_distance_km,0),0)*v_cfg.driver_per_km;
  v_driver_payout:=greatest(
    v_cfg.driver_min_payout,
    v_driver_base+v_driver_distance
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
    +v_customer_fee+v_priority_fee+v_tip;

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

create or replace function public.marketplace_create_order(
  p_merchant_id uuid,
  p_items jsonb,
  p_distance_km numeric,
  p_tip numeric,
  p_priority boolean,
  p_payment_method text,
  p_dropoff_address text,
  p_dropoff_lat numeric default null::numeric,
  p_dropoff_lng numeric default null::numeric,
  p_customer_note text default null::text,
  p_channel text default 'production'::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_quote jsonb;
  v_order public.marketplace_orders%rowtype;
  v_method text:=lower(trim(coalesce(p_payment_method,'')));
  v_collector text;
  v_margin numeric;
  v_locked_subscription_id uuid;
  v_consumed integer;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if v_method not in (
    'cash','transfer','mercado_pago','wallet'
  ) then
    raise exception 'Método de pago no válido';
  end if;

  if coalesce(p_priority,false) then
    select s.id into v_locked_subscription_id
    from public.marketplace_plus_subscriptions s
    join public.marketplace_plus_plans p on p.id=s.plan_id
    join public.marketplace_merchants m on m.zone_id=p.zone_id
    where m.id=p_merchant_id
      and s.customer_id=v_uid
      and s.status='active'
      and s.started_at<=now()
      and s.expires_at>now()
      and p.active=true
    order by s.expires_at desc
    limit 1
    for update of s;
  end if;

  v_quote:=public.marketplace_compute_quote(
    v_uid,p_merchant_id,p_items,p_distance_km,
    p_tip,p_priority,p_channel
  );

  if v_method='cash'
     and coalesce(
       (v_quote->>'cash_enabled')::boolean,
       false
     )=false then
    raise exception 'Efectivo no disponible';
  end if;

  if v_method='transfer'
     and coalesce(
       (v_quote->>'transfer_enabled')::boolean,
       false
     )=false then
    raise exception 'Transferencia no disponible';
  end if;

  if v_method in ('mercado_pago','wallet')
     and coalesce(
       (v_quote->>'online_enabled')::boolean,
       false
     )=false then
    raise exception 'Pago online no disponible';
  end if;

  v_collector:=case
    when v_method='cash' then 'driver'
    when v_method='transfer' then 'merchant'
    else 'express'
  end;

  insert into public.marketplace_orders(
    customer_id,merchant_id,zone_id,channel,status,
    payment_method,payment_status,currency_code,
    subtotal,product_discount,customer_delivery_fee,
    priority_fee,tip_amount,total_amount,
    driver_base_payout,driver_distance_payout,
    driver_priority_bonus,driver_payout,express_margin,
    merchant_products_amount,collector,distance_km,
    is_priority,plus_subscription_applied,
    plus_subscription_id,plus_free_delivery_applied,
    plus_priority_included_applied,plus_discount_percent,
    dropoff_address,dropoff_latitude,dropoff_longitude,
    customer_note
  )
  values(
    v_uid,
    p_merchant_id,
    (v_quote->>'zone_id')::uuid,
    lower(coalesce(p_channel,'production')),
    case
      when v_method='transfer' then 'awaiting_transfer'
      else 'pending'
    end,
    v_method,
    case
      when v_method='transfer' then 'awaiting_receipt'
      else 'pending'
    end,
    v_quote->>'currency_code',
    (v_quote->>'subtotal')::numeric,
    (v_quote->>'product_discount')::numeric,
    (v_quote->>'customer_delivery_fee')::numeric,
    (v_quote->>'priority_fee')::numeric,
    (v_quote->>'tip_amount')::numeric,
    (v_quote->>'total_amount')::numeric,
    (v_quote->>'driver_base_payout')::numeric,
    (v_quote->>'driver_distance_payout')::numeric,
    (v_quote->>'driver_priority_bonus')::numeric,
    (v_quote->>'driver_payout')::numeric,
    (v_quote->>'express_margin')::numeric,
    (v_quote->>'merchant_products_amount')::numeric,
    v_collector,
    greatest(coalesce(p_distance_km,0),0),
    (v_quote->>'is_priority')::boolean,
    (v_quote->>'plus_subscription_applied')::boolean,
    nullif(v_quote->>'plus_subscription_id','')::uuid,
    (v_quote->>'plus_free_delivery_applied')::boolean,
    coalesce(
      (v_quote->>'plus_priority_included_applied')::boolean,
      false
    ),
    (v_quote->>'plus_discount_percent')::numeric,
    p_dropoff_address,
    p_dropoff_lat,
    p_dropoff_lng,
    p_customer_note
  )
  returning * into v_order;

  if v_order.plus_priority_included_applied then
    update public.marketplace_plus_subscriptions s
    set
      priority_deliveries_used=s.priority_deliveries_used+1,
      updated_at=now()
    from public.marketplace_plus_plans p
    where s.id=v_order.plus_subscription_id
      and p.id=s.plan_id
      and s.status='active'
      and s.started_at<=now()
      and s.expires_at>now()
      and s.priority_deliveries_used<p.included_priority_deliveries
    returning s.priority_deliveries_used into v_consumed;

    if not found then
      raise exception 'El cupo de envíos prioritarios cambió; vuelve a cotizar';
    end if;
  end if;

  insert into public.marketplace_order_items(
    order_id,product_id,product_name,
    quantity,unit_price,line_total
  )
  select
    v_order.id,p.id,p.name,r.quantity,
    p.price,p.price*r.quantity
  from (
    select
      nullif(x->>'product_id','')::uuid product_id,
      greatest(
        coalesce((x->>'quantity')::int,1),
        1
      ) quantity
    from jsonb_array_elements(
      coalesce(p_items,'[]'::jsonb)
    ) x
  ) r
  join public.marketplace_products p
    on p.id=r.product_id
  where p.merchant_id=p_merchant_id
    and p.active=true;

  v_margin:=v_order.express_margin;

  insert into public.marketplace_order_financials(
    order_id,customer_total,merchant_products_amount,
    driver_payout,driver_tip,express_margin,collector,
    merchant_owes_driver,merchant_owes_express,
    driver_owes_merchant,driver_owes_express,
    express_owes_merchant,express_owes_driver
  )
  values(
    v_order.id,
    v_order.total_amount,
    v_order.merchant_products_amount,
    v_order.driver_payout,
    v_order.tip_amount,
    v_margin,
    v_collector,
    case
      when v_collector='merchant'
      then v_order.driver_payout+v_order.tip_amount
      else 0
    end,
    case
      when v_collector='merchant'
      then greatest(v_margin,0)
      else 0
    end,
    case
      when v_collector='driver'
      then v_order.merchant_products_amount
      else 0
    end,
    case
      when v_collector='driver'
      then greatest(v_margin,0)
      else 0
    end,
    case
      when v_collector='express'
      then v_order.merchant_products_amount
      when v_collector='merchant' and v_margin<0
      then abs(v_margin)
      else 0
    end,
    case
      when v_collector='express'
      then v_order.driver_payout+v_order.tip_amount
      when v_collector='driver' and v_margin<0
      then abs(v_margin)
      else 0
    end
  );

  insert into public.marketplace_order_messages(
    order_id,sender_id,sender_role,message_type,body
  )
  values(
    v_order.id,
    v_uid,
    'system',
    'system',
    case
      when v_method='transfer'
      then 'Pedido creado. Esperando datos/comprobante de transferencia.'
      when v_method='cash'
      then 'Pedido creado con pago en efectivo.'
      else 'Pedido creado. Esperando confirmación del pago online.'
    end
  );

  return jsonb_build_object(
    'order',to_jsonb(v_order),
    'quote',v_quote
  );
end;
$function$;

revoke execute on function public.marketplace_has_plus(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.marketplace_has_plus(uuid,uuid)
  to service_role;

revoke execute on function public.marketplace_activate_plus(
  uuid,uuid,text,text
) from public,anon,authenticated;
grant execute on function public.marketplace_activate_plus(
  uuid,uuid,text,text
) to service_role;

revoke execute on function public.marketplace_compute_quote(
  uuid,uuid,jsonb,numeric,numeric,boolean,text
) from public,anon,authenticated;
grant execute on function public.marketplace_compute_quote(
  uuid,uuid,jsonb,numeric,numeric,boolean,text
) to service_role;

revoke execute on function public.marketplace_plus_state(text)
  from public,anon;
grant execute on function public.marketplace_plus_state(text)
  to authenticated;

revoke execute on function public.marketplace_create_order(
  uuid,jsonb,numeric,numeric,boolean,text,text,numeric,numeric,text,text
) from public,anon;
grant execute on function public.marketplace_create_order(
  uuid,jsonb,numeric,numeric,boolean,text,text,numeric,numeric,text,text
) to authenticated;
