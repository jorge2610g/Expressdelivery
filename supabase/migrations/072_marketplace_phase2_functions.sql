-- Express Delivery / Market Phase 2 runtime functions.
-- Generated from the verified Preview database state on 2026-10-03.
-- Production feature flags remain disabled.

-- admin_marketplace_assign_merchant_user
CREATE OR REPLACE FUNCTION public.admin_marketplace_assign_merchant_user(p_merchant_id uuid, p_email text, p_role text DEFAULT 'manager'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid;
  v_email text:=lower(trim(coalesce(p_email,'')));
  v_role text:=lower(trim(coalesce(p_role,'manager')));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_email='' then raise exception 'Correo requerido'; end if;

  select id into v_uid
  from auth.users
  where lower(email)=v_email
  limit 1;

  if v_uid is null then
    raise exception 'No existe una cuenta Express con ese correo';
  end if;

  if not exists(
    select 1 from public.marketplace_merchants
    where id=p_merchant_id
  ) then
    raise exception 'Comercio no encontrado';
  end if;

  insert into public.marketplace_merchant_users(
    merchant_id,user_id,role,active
  )
  values(
    p_merchant_id,
    v_uid,
    case
      when v_role in ('owner','manager','staff') then v_role
      else 'manager'
    end,
    true
  )
  on conflict(merchant_id,user_id) do update set
    role=excluded.role,
    active=true;

  return jsonb_build_object(
    'merchant_id',p_merchant_id,
    'user_id',v_uid,
    'email',v_email,
    'role',case
      when v_role in ('owner','manager','staff') then v_role
      else 'manager'
    end
  );
end;
$function$;

-- admin_marketplace_merchant_users
CREATE OR REPLACE FUNCTION public.admin_marketplace_merchant_users(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'user_id',mu.user_id,
          'role',mu.role,
          'active',mu.active,
          'full_name',u.full_name,
          'phone',u.phone,
          'email',au.email
        )
        order by mu.created_at
      ),
      '[]'::jsonb
    )
    from public.marketplace_merchant_users mu
    left join public.users u on u.id=mu.user_id
    left join auth.users au on au.id=mu.user_id
    where mu.merchant_id=p_merchant_id
  );
end;
$function$;

-- admin_marketplace_phase2_state
CREATE OR REPLACE FUNCTION public.admin_marketplace_phase2_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'zones',(
      select coalesce(
        jsonb_agg(
          to_jsonb(s) || jsonb_build_object(
            'zone_key',z.zone_key,
            'zone_name',z.name,
            'currency_code',z.currency_code
          )
          order by z.country,z.city,z.name
        ),
        '[]'::jsonb
      )
      from public.marketplace_zone_settings s
      join public.service_zones z on z.id=s.zone_id
    ),
    'plus_plans',(
      select coalesce(
        jsonb_agg(
          to_jsonb(p) || jsonb_build_object(
            'zone_key',z.zone_key,
            'zone_name',z.name
          )
          order by z.name,p.name
        ),
        '[]'::jsonb
      )
      from public.marketplace_plus_plans p
      join public.service_zones z on z.id=p.zone_id
    ),
    'benefits',(
      select coalesce(
        jsonb_agg(
          to_jsonb(b) || jsonb_build_object(
            'merchant_name',m.name,
            'zone_id',m.zone_id
          )
          order by m.name
        ),
        '[]'::jsonb
      )
      from public.marketplace_plus_merchant_benefits b
      join public.marketplace_merchants m on m.id=b.merchant_id
    ),
    'merchants',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id',m.id,
            'name',m.name,
            'zone_id',m.zone_id,
            'zone_key',z.zone_key,
            'active',m.active
          )
          order by z.name,m.name
        ),
        '[]'::jsonb
      )
      from public.marketplace_merchants m
      left join public.service_zones z on z.id=m.zone_id
    ),
    'recent_orders',(
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.created_at desc),
        '[]'::jsonb
      )
      from (
        select
          o.id,o.status,o.payment_method,o.payment_status,
          o.currency_code,o.total_amount,o.driver_payout,
          o.tip_amount,o.express_margin,o.created_at,
          o.transfer_receipt_url,o.transfer_submitted_at,
          m.name merchant_name,z.zone_key
        from public.marketplace_orders o
        join public.marketplace_merchants m on m.id=o.merchant_id
        join public.service_zones z on z.id=o.zone_id
        order by o.created_at desc
        limit 50
      ) x
    )
  );
end;
$function$;

-- admin_marketplace_set_merchant_user_active
CREATE OR REPLACE FUNCTION public.admin_marketplace_set_merchant_user_active(p_merchant_id uuid, p_user_id uuid, p_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  update public.marketplace_merchant_users
  set active=coalesce(p_active,false)
  where merchant_id=p_merchant_id
    and user_id=p_user_id;
end;
$function$;

-- admin_marketplace_set_plus_merchant_benefit
CREATE OR REPLACE FUNCTION public.admin_marketplace_set_plus_merchant_benefit(p_merchant_id uuid, p_enabled boolean, p_discount_percent numeric, p_free_delivery boolean, p_exclusive_promo boolean, p_funded_by text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  insert into public.marketplace_plus_merchant_benefits(
    merchant_id,enabled,discount_percent,free_delivery,
    exclusive_promo,funded_by,updated_at
  )
  values(
    p_merchant_id,
    coalesce(p_enabled,false),
    greatest(least(coalesce(p_discount_percent,0),100),0),
    coalesce(p_free_delivery,false),
    coalesce(p_exclusive_promo,false),
    case when p_funded_by='merchant' then 'merchant' else 'express' end,
    now()
  )
  on conflict(merchant_id) do update set
    enabled=excluded.enabled,
    discount_percent=excluded.discount_percent,
    free_delivery=excluded.free_delivery,
    exclusive_promo=excluded.exclusive_promo,
    funded_by=excluded.funded_by,
    updated_at=now();
end;
$function$;

-- admin_marketplace_update_merchant_logistics
CREATE OR REPLACE FUNCTION public.admin_marketplace_update_merchant_logistics(p_merchant_id uuid, p_address text, p_latitude numeric, p_longitude numeric, p_transfer_instructions text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  update public.marketplace_merchants
  set
    address=nullif(trim(coalesce(p_address,'')),''),
    latitude=p_latitude,
    longitude=p_longitude,
    transfer_instructions=nullif(trim(coalesce(p_transfer_instructions,'')),''),
    updated_at=now()
  where id=p_merchant_id;

  if not found then raise exception 'Comercio no encontrado'; end if;
end;
$function$;

-- admin_marketplace_update_zone_phase2
CREATE OR REPLACE FUNCTION public.admin_marketplace_update_zone_phase2(p_zone_id uuid, p_preview_enabled boolean, p_production_enabled boolean, p_customer_base_fee numeric, p_customer_per_km numeric, p_customer_min_fee numeric, p_driver_base_payout numeric, p_driver_per_km numeric, p_driver_min_payout numeric, p_priority_enabled boolean, p_priority_customer_fee numeric, p_priority_driver_bonus numeric, p_tips_enabled boolean, p_cash_enabled boolean, p_transfer_enabled boolean, p_online_enabled boolean, p_plus_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  insert into public.marketplace_zone_settings(
    zone_id,preview_enabled,production_enabled,
    customer_base_fee,customer_per_km,customer_min_fee,
    driver_base_payout,driver_per_km,driver_min_payout,
    priority_enabled,priority_customer_fee,priority_driver_bonus,
    tips_enabled,cash_enabled,transfer_enabled,
    online_enabled,plus_enabled,updated_at
  )
  values(
    p_zone_id,
    coalesce(p_preview_enabled,true),
    coalesce(p_production_enabled,false),
    greatest(coalesce(p_customer_base_fee,0),0),
    greatest(coalesce(p_customer_per_km,0),0),
    greatest(coalesce(p_customer_min_fee,0),0),
    greatest(coalesce(p_driver_base_payout,0),0),
    greatest(coalesce(p_driver_per_km,0),0),
    greatest(coalesce(p_driver_min_payout,0),0),
    coalesce(p_priority_enabled,true),
    greatest(coalesce(p_priority_customer_fee,0),0),
    greatest(coalesce(p_priority_driver_bonus,0),0),
    coalesce(p_tips_enabled,true),
    coalesce(p_cash_enabled,true),
    coalesce(p_transfer_enabled,false),
    coalesce(p_online_enabled,true),
    coalesce(p_plus_enabled,false),
    now()
  )
  on conflict(zone_id) do update set
    preview_enabled=excluded.preview_enabled,
    production_enabled=excluded.production_enabled,
    customer_base_fee=excluded.customer_base_fee,
    customer_per_km=excluded.customer_per_km,
    customer_min_fee=excluded.customer_min_fee,
    driver_base_payout=excluded.driver_base_payout,
    driver_per_km=excluded.driver_per_km,
    driver_min_payout=excluded.driver_min_payout,
    priority_enabled=excluded.priority_enabled,
    priority_customer_fee=excluded.priority_customer_fee,
    priority_driver_bonus=excluded.priority_driver_bonus,
    tips_enabled=excluded.tips_enabled,
    cash_enabled=excluded.cash_enabled,
    transfer_enabled=excluded.transfer_enabled,
    online_enabled=excluded.online_enabled,
    plus_enabled=excluded.plus_enabled,
    updated_at=now();
end;
$function$;

-- admin_marketplace_upsert_plus_plan
CREATE OR REPLACE FUNCTION public.admin_marketplace_upsert_plus_plan(p_id uuid, p_zone_id uuid, p_name text, p_monthly_price numeric, p_active boolean, p_preview_visible boolean, p_production_visible boolean, p_free_delivery boolean, p_included_priority_deliveries integer, p_default_discount_percent numeric, p_description text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid:=coalesce(p_id,gen_random_uuid());
  v_currency text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select currency_code into v_currency
  from public.service_zones
  where id=p_zone_id;

  if v_currency is null then raise exception 'Zona no encontrada'; end if;

  insert into public.marketplace_plus_plans(
    id,zone_id,name,monthly_price,currency_code,
    active,preview_visible,production_visible,
    free_delivery,included_priority_deliveries,
    default_discount_percent,description,updated_at
  )
  values(
    v_id,p_zone_id,
    coalesce(nullif(trim(p_name),''),'Express Plus'),
    greatest(coalesce(p_monthly_price,0),0),
    v_currency,
    coalesce(p_active,false),
    coalesce(p_preview_visible,true),
    coalesce(p_production_visible,false),
    coalesce(p_free_delivery,true),
    greatest(coalesce(p_included_priority_deliveries,0),0),
    greatest(least(coalesce(p_default_discount_percent,0),100),0),
    nullif(trim(coalesce(p_description,'')),''),
    now()
  )
  on conflict(id) do update set
    zone_id=excluded.zone_id,
    name=excluded.name,
    monthly_price=excluded.monthly_price,
    currency_code=excluded.currency_code,
    active=excluded.active,
    preview_visible=excluded.preview_visible,
    production_visible=excluded.production_visible,
    free_delivery=excluded.free_delivery,
    included_priority_deliveries=excluded.included_priority_deliveries,
    default_discount_percent=excluded.default_discount_percent,
    description=excluded.description,
    updated_at=now();

  return v_id;
end;
$function$;

-- advance_delivery
CREATE OR REPLACE FUNCTION public.advance_delivery(p_delivery_id uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current text;
  v_courier uuid;
  v_customer uuid;
  v_fare numeric;
  v_payment_method text;
  v_currency text;
  v_body text;
  v_marketplace_order_id uuid;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;

  select
    status,courier_id,customer_id,proposed_fare,
    payment_method,currency,marketplace_order_id
  into
    v_current,v_courier,v_customer,v_fare,
    v_payment_method,v_currency,v_marketplace_order_id
  from public.delivery_requests
  where id=p_delivery_id
  for update;

  if v_courier is distinct from auth.uid() then
    raise exception 'No autorizado';
  end if;

  if not (
    (v_current='accepted' and p_status='picked_up')
    or (v_current='picked_up' and p_status='in_transit')
    or (v_current='in_transit' and p_status='delivered')
  ) then
    raise exception 'Transición de delivery inválida';
  end if;

  update public.delivery_requests
  set
    status=p_status,
    updated_at=now(),
    completed_at=case
      when p_status='delivered' then now()
      else completed_at
    end
  where id=p_delivery_id;

  insert into public.delivery_status_history(delivery_id,status,changed_by)
  values(p_delivery_id,p_status,auth.uid());

  v_body:=case p_status
    when 'picked_up' then 'El repartidor recogió tu envío.'
    when 'in_transit' then 'Tu envío está en camino.'
    when 'delivered' then 'Tu envío fue entregado. Ya puedes calificar al repartidor.'
    else 'El estado de tu delivery cambió.'
  end;

  insert into public.notifications(user_id,title,body,type)
  values(v_customer,'Actualización de delivery',v_body,'delivery_status');

  if v_marketplace_order_id is not null then
    update public.marketplace_orders
    set
      status=case p_status
        when 'picked_up' then 'picked_up'
        when 'in_transit' then 'delivering'
        when 'delivered' then 'delivered'
        else status
      end,
      completed_at=case
        when p_status='delivered' then now()
        else completed_at
      end,
      updated_at=now()
    where id=v_marketplace_order_id;
  end if;

  if p_status='delivered' then
    insert into public.payment_transactions(
      payer_id,payee_id,delivery_id,method,amount,currency,status,paid_at
    )
    values(
      v_customer,v_courier,p_delivery_id,v_payment_method,
      coalesce(v_fare,0),coalesce(v_currency,'BOB'),
      case
        when v_payment_method in ('cash','transfer') then 'paid'
        else 'pending'
      end,
      case
        when v_payment_method in ('cash','transfer') then now()
        else null
      end
    )
    on conflict(delivery_id)
      where delivery_id is not null
      do nothing;

    update public.driver_profiles
    set online_status='online',updated_at=now()
    where id=v_courier;

    insert into public.notifications(user_id,title,body,type)
    values(
      v_courier,
      'Delivery completado',
      'La entrega quedó finalizada y registrada en tus ganancias.',
      'delivery_completed'
    );
  end if;
end;
$function$;

-- cancel_delivery
CREATE OR REPLACE FUNCTION public.cancel_delivery(p_delivery_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_customer uuid;
  v_courier uuid;
  v_status text;
  v_other uuid;
  v_marketplace_order_id uuid;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select customer_id,courier_id,status,marketplace_order_id
  into v_customer,v_courier,v_status,v_marketplace_order_id
  from public.delivery_requests
  where id=p_delivery_id
  for update;

  if auth.uid()<>v_customer
     and (v_courier is null or auth.uid()<>v_courier) then
    raise exception 'No autorizado';
  end if;

  if v_status='cancelled' then return; end if;

  if auth.uid()=v_customer and v_status not in ('searching','accepted') then
    raise exception 'El cliente ya no puede cancelar este delivery';
  end if;

  if v_courier is not null
     and auth.uid()=v_courier
     and v_status<>'accepted' then
    raise exception 'El repartidor ya no puede cancelar este delivery';
  end if;

  update public.delivery_requests
  set status='cancelled',updated_at=now()
  where id=p_delivery_id;

  insert into public.delivery_status_history(delivery_id,status,changed_by)
  values(p_delivery_id,'cancelled',auth.uid());

  if v_marketplace_order_id is not null then
    if auth.uid()=v_customer then
      update public.marketplace_orders
      set status='cancelled',completed_at=now(),updated_at=now()
      where id=v_marketplace_order_id;
    else
      update public.marketplace_orders
      set
        status='ready',
        assigned_driver_id=null,
        delivery_request_id=null,
        updated_at=now()
      where id=v_marketplace_order_id;
    end if;
  end if;

  if v_courier is not null then
    update public.driver_profiles
    set online_status='online',updated_at=now()
    where id=v_courier and approval_status='approved';

    v_other:=case
      when auth.uid()=v_customer then v_courier
      else v_customer
    end;

    insert into public.notifications(user_id,title,body,type)
    values(
      v_other,
      'Delivery cancelado',
      coalesce(
        nullif(trim(p_reason),''),
        'El delivery fue cancelado por la otra parte.'
      ),
      'delivery_cancelled'
    );
  end if;

  insert into public.notifications(user_id,title,body,type)
  values(
    auth.uid(),
    'Delivery cancelado',
    coalesce(nullif(trim(p_reason),''),'El delivery fue cancelado.'),
    'delivery_cancelled'
  );
end;
$function$;

-- claim_delivery
CREATE OR REPLACE FUNCTION public.claim_delivery(p_delivery_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_customer uuid;
  v_marketplace_order_id uuid;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists (
    select 1
    from public.driver_profiles dp
    where dp.id=auth.uid()
      and dp.approval_status='approved'
      and dp.online_status in ('online','busy')
  ) then
    raise exception 'Conductor no aprobado o fuera de línea';
  end if;

  select customer_id,marketplace_order_id
  into v_customer,v_marketplace_order_id
  from public.delivery_requests
  where id=p_delivery_id
    and courier_id is null
    and status='searching'
  for update;

  if v_customer is null
     or not public.same_operational_scope(v_customer,auth.uid()) then
    raise exception 'Delivery no disponible en tu entorno';
  end if;

  update public.delivery_requests
  set courier_id=auth.uid(),status='accepted',updated_at=now()
  where id=p_delivery_id
    and customer_id=v_customer
    and courier_id is null
    and status='searching';

  if not found then raise exception 'Delivery no disponible'; end if;

  insert into public.delivery_status_history(delivery_id,status,changed_by)
  values(p_delivery_id,'accepted',auth.uid());

  if v_marketplace_order_id is not null then
    update public.marketplace_orders
    set
      assigned_driver_id=auth.uid(),
      status='driver_assigned',
      updated_at=now()
    where id=v_marketplace_order_id;
  end if;
end;
$function$;

-- marketplace_activate_plus
CREATE OR REPLACE FUNCTION public.marketplace_activate_plus(p_customer_id uuid, p_plan_id uuid, p_provider text, p_provider_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_plan public.marketplace_plus_plans%rowtype;
  v_existing public.marketplace_plus_subscriptions%rowtype;
  v_start timestamptz:=now();
  v_end timestamptz;
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
  limit 1;

  if found and v_existing.expires_at>now() then
    v_start:=v_existing.expires_at;
  end if;

  v_end:=v_start+interval '30 days';

  insert into public.marketplace_plus_subscriptions(
    customer_id,plan_id,status,started_at,expires_at,
    auto_renew,provider,provider_reference,updated_at
  )
  values(
    p_customer_id,p_plan_id,'active',now(),v_end,
    false,p_provider,p_provider_reference,now()
  );

  return jsonb_build_object(
    'active',true,
    'plan_id',p_plan_id,
    'expires_at',v_end
  );
end;
$function$;

-- marketplace_compute_quote
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

  if coalesce(p_priority,false) and v_cfg.priority_enabled then
    v_priority_fee:=v_cfg.priority_customer_fee;
    v_driver_bonus:=v_cfg.priority_driver_bonus;
    v_driver_payout:=v_driver_payout+v_driver_bonus;
  end if;

  if not v_cfg.tips_enabled then
    v_tip:=0;
  end if;

  if v_cfg.plus_enabled then
    v_has_plus:=public.marketplace_has_plus(
      p_customer_id,
      v_zone.id
    );
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
      select
        coalesce(p.default_discount_percent,0),
        coalesce(p.free_delivery,false)
      into v_plus_discount,v_free_delivery
      from public.marketplace_plus_plans p
      join public.marketplace_plus_subscriptions s
        on s.plan_id=p.id
      where s.customer_id=p_customer_id
        and p.zone_id=v_zone.id
        and s.status='active'
        and s.expires_at>now()
        and p.active=true
      order by s.expires_at desc
      limit 1;

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
    'plus_free_delivery_applied',
      v_has_plus and v_free_delivery,
    'plus_discount_percent',
      case
        when v_has_plus then coalesce(v_plus_discount,0)
        else 0
      end,
    'tips_enabled',v_cfg.tips_enabled,
    'cash_enabled',v_cfg.cash_enabled,
    'transfer_enabled',v_cfg.transfer_enabled,
    'online_enabled',v_cfg.online_enabled,
    'priority_enabled',v_cfg.priority_enabled
  );
end;
$function$;

-- marketplace_create_order
CREATE OR REPLACE FUNCTION public.marketplace_create_order(p_merchant_id uuid, p_items jsonb, p_distance_km numeric, p_tip numeric, p_priority boolean, p_payment_method text, p_dropoff_address text, p_dropoff_lat numeric DEFAULT NULL::numeric, p_dropoff_lng numeric DEFAULT NULL::numeric, p_customer_note text DEFAULT NULL::text, p_channel text DEFAULT 'production'::text)
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
  v_margin numeric;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if v_method not in (
    'cash','transfer','mercado_pago','wallet'
  ) then
    raise exception 'Método de pago no válido';
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
    plus_free_delivery_applied,plus_discount_percent,
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
    (v_quote->>'plus_free_delivery_applied')::boolean,
    (v_quote->>'plus_discount_percent')::numeric,
    p_dropoff_address,
    p_dropoff_lat,
    p_dropoff_lng,
    p_customer_note
  )
  returning * into v_order;

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
      when v_collector='merchant'
           and v_margin<0
      then abs(v_margin)
      else 0
    end,

    case
      when v_collector='express'
      then v_order.driver_payout+v_order.tip_amount
      when v_collector='driver'
           and v_margin<0
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

-- marketplace_has_plus
CREATE OR REPLACE FUNCTION public.marketplace_has_plus(p_customer_id uuid, p_zone_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1
    from public.marketplace_plus_subscriptions s
    join public.marketplace_plus_plans p on p.id=s.plan_id
    where s.customer_id=p_customer_id
      and p.zone_id=p_zone_id
      and s.status='active'
      and s.expires_at>now()
      and p.active=true
  );
$function$;

-- marketplace_mark_driver_paid
CREATE OR REPLACE FUNCTION public.marketplace_mark_driver_paid(p_order_id uuid, p_note text DEFAULT NULL::text)
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
  where id=p_order_id;
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

  update public.marketplace_order_financials
  set
    merchant_owes_driver=0,
    settlement_status=case
      when merchant_owes_express=0
       and driver_owes_merchant=0
       and driver_owes_express=0
       and express_owes_merchant=0
       and express_owes_driver=0
      then 'settled'
      else 'partial'
    end,
    updated_at=now()
  where order_id=p_order_id;

  insert into public.marketplace_order_messages(
    order_id,sender_id,sender_role,message_type,body
  )
  values(
    p_order_id,v_uid,
    case when public.is_admin() then 'admin' else 'merchant' end,
    'system',
    coalesce(
      nullif(trim(coalesce(p_note,'')),''),
      'El comercio confirmó el pago de la tarifa al repartidor.'
    )
  );

  return public.marketplace_order_detail(p_order_id);
end;
$function$;

-- marketplace_merchant_orders
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
        o.driver_payout,o.express_margin,o.created_at,
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

-- marketplace_my_merchant_access
CREATE OR REPLACE FUNCTION public.marketplace_my_merchant_access()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'merchant_id',m.id,
        'merchant_name',m.name,
        'zone_id',m.zone_id,
        'role',mu.role,
        'active',mu.active
      )
      order by m.name
    ),
    '[]'::jsonb
  )
  from public.marketplace_merchant_users mu
  join public.marketplace_merchants m on m.id=mu.merchant_id
  where mu.user_id=auth.uid()
    and mu.active=true
    and m.active=true;
$function$;

-- marketplace_my_orders
CREATE OR REPLACE FUNCTION public.marketplace_my_orders(p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  from (
    select
      o.id,o.status,o.payment_method,o.payment_status,o.currency_code,
      o.subtotal,o.product_discount,o.customer_delivery_fee,o.priority_fee,
      o.tip_amount,o.total_amount,o.driver_payout,o.express_margin,
      o.is_priority,o.plus_subscription_applied,o.created_at,
      m.name merchant_name,m.image_url merchant_image
    from public.marketplace_orders o
    join public.marketplace_merchants m on m.id=o.merchant_id
    where o.customer_id=auth.uid()
    order by o.created_at desc
    limit greatest(least(coalesce(p_limit,30),100),1)
  ) x;
$function$;

-- marketplace_order_detail
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
    'order',to_jsonb(v_order),
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
      select to_jsonb(f)
      from public.marketplace_order_financials f
      where f.order_id=p_order_id
    )
  );
end;
$function$;

-- marketplace_order_mark_paid
CREATE OR REPLACE FUNCTION public.marketplace_order_mark_paid(p_order_id uuid, p_provider_reference text, p_provider_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order public.marketplace_orders%rowtype;
begin
  select * into v_order
  from public.marketplace_orders
  where id=p_order_id
  for update;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if v_order.payment_status='paid' then
    return public.marketplace_order_detail(p_order_id);
  end if;

  update public.marketplace_orders
  set
    payment_status='paid',
    status=case when status in ('pending','awaiting_transfer','payment_review')
      then 'confirmed' else status end,
    provider_reference=coalesce(
      nullif(trim(coalesce(p_provider_reference,'')),''),
      provider_reference
    ),
    updated_at=now()
  where id=p_order_id;

  return public.marketplace_order_detail(p_order_id);
end;
$function$;

-- marketplace_order_set_status
CREATE OR REPLACE FUNCTION public.marketplace_order_set_status(p_order_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_merchant public.marketplace_merchants%rowtype;
  v_allowed boolean:=false;
  v_delivery_id uuid;
  v_payment_method text;
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

  if p_status not in ('confirmed','preparing','ready','cancelled') then
    raise exception 'Estado no permitido para comercio';
  end if;

  if p_status='confirmed'
     and v_order.payment_method<>'cash'
     and v_order.payment_status<>'paid' then
    raise exception 'El pago debe estar confirmado';
  end if;

  if p_status='preparing'
     and v_order.status not in ('confirmed','preparing') then
    raise exception 'El pedido todavía no está confirmado';
  end if;

  if p_status='ready' then
    if v_order.status not in (
      'confirmed','preparing','ready','searching_driver'
    ) then
      raise exception 'El pedido no puede pasar a listo';
    end if;

    select * into v_merchant
    from public.marketplace_merchants
    where id=v_order.merchant_id;

    if v_merchant.latitude is null
       or v_merchant.longitude is null then
      raise exception 'Configura la ubicación del comercio antes de despachar';
    end if;

    if v_order.delivery_request_id is null then
      v_payment_method:=case
        when v_order.payment_method='transfer' then 'transfer'
        when v_order.payment_method='mercado_pago' then 'mercado_pago'
        when v_order.payment_method='wallet' then 'wallet'
        else 'cash'
      end;

      insert into public.delivery_requests(
        customer_id,package_type,
        pickup_address,pickup_latitude,pickup_longitude,
        dropoff_address,dropoff_latitude,dropoff_longitude,
        details,proposed_fare,customer_charge_amount,
        currency,payment_method,status,
        route_distance_km,marketplace_order_id
      )
      values(
        v_order.customer_id,
        'purchase',
        coalesce(v_merchant.address,v_merchant.name),
        v_merchant.latitude,
        v_merchant.longitude,
        v_order.dropoff_address,
        v_order.dropoff_latitude,
        v_order.dropoff_longitude,
        'Pedido Express Delivery #' || left(v_order.id::text,8)
          || case
             when v_order.payment_method='cash'
             then ' · COBRAR AL CLIENTE '
               || v_order.currency_code || ' '
               || v_order.total_amount::text
             else ' · PEDIDO PREPAGADO: no cobrar al cliente'
             end,
        greatest(v_order.driver_payout+v_order.tip_amount,0.01),
        v_order.total_amount,
        v_order.currency_code,
        v_payment_method,
        'searching',
        v_order.distance_km,
        v_order.id
      )
      returning id into v_delivery_id;

      update public.marketplace_orders
      set
        delivery_request_id=v_delivery_id,
        status='searching_driver',
        updated_at=now()
      where id=v_order.id;
    else
      update public.marketplace_orders
      set status='searching_driver',updated_at=now()
      where id=v_order.id;
    end if;
  else
    update public.marketplace_orders
    set
      status=p_status,
      updated_at=now(),
      completed_at=case
        when p_status='cancelled' then now()
        else completed_at
      end
    where id=v_order.id;
  end if;

  return public.marketplace_order_detail(p_order_id);
end;
$function$;

-- marketplace_plus_state
CREATE OR REPLACE FUNCTION public.marketplace_plus_state(p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  select to_jsonb(s) || jsonb_build_object('plan_name',p.name)
  into v_subscription
  from public.marketplace_plus_subscriptions s
  join public.marketplace_plus_plans p on p.id=s.plan_id
  where s.customer_id=v_uid
    and p.zone_id=v_zone_id
    and s.status='active'
    and s.expires_at>now()
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

-- marketplace_quote_order
CREATE OR REPLACE FUNCTION public.marketplace_quote_order(p_merchant_id uuid, p_items jsonb, p_distance_km numeric DEFAULT 0, p_tip numeric DEFAULT 0, p_priority boolean DEFAULT false, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  return public.marketplace_compute_quote(
    v_uid,p_merchant_id,p_items,p_distance_km,p_tip,p_priority,p_channel
  );
end;
$function$;

-- marketplace_review_transfer
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

-- marketplace_send_order_message
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