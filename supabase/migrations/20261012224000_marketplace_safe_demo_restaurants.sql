-- Demo restaurants for isolated Preview and hidden Production QA.
-- The RPC is idempotent, and existing merchant/product edits are preserved.
begin;
create table if not exists public.marketplace_demo_restaurants(
 merchant_id uuid primary key references public.marketplace_merchants(id) on delete cascade,
 zone_id uuid not null references public.service_zones(id),
 channel text not null check(channel in ('preview','production')),
 template_key text not null check(template_key in ('burgers','pizza','home_cooking')),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 unique(zone_id,channel,template_key)
);
create index if not exists marketplace_demo_environment_idx
 on public.marketplace_demo_restaurants(channel,zone_id);
alter table public.marketplace_demo_restaurants enable row level security;
revoke all on public.marketplace_demo_restaurants from public,anon,authenticated;

-- Disallow accidental public listing and cross-channel reuse, including
-- old admin CRUD RPCs which can otherwise toggle visibility arbitrarily.
create or replace function public.guard_marketplace_demo_visibility()
returns trigger language plpgsql security definer set search_path=public as $$
declare d public.marketplace_demo_restaurants%rowtype;
begin
 select * into d from public.marketplace_demo_restaurants
 where merchant_id=old.id;
 if not found then return new; end if;
 if new.zone_id is distinct from d.zone_id
   or (d.channel='production' and
     (new.production_visible or new.preview_visible))
   or (d.channel='preview' and new.production_visible) then
     raise exception 'Un restaurante demo no puede salir de su entorno';
 end if;
 return new;
end $$;
create trigger trg_guard_marketplace_demo_visibility
 before update on public.marketplace_merchants
 for each row execute function public.guard_marketplace_demo_visibility();

create or replace function public.admin_marketplace_create_demo_restaurant(
 p_zone_id uuid,p_channel text,p_template_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_context jsonb:=public.admin_access_context();
 v_currency text;v_zone_name text;
 v_merchant uuid;v_existing boolean:=false;
 v_name text;v_desc text;v_address text;
 v_sections jsonb;v_products jsonb;v_entry jsonb;
 v_section uuid;v_product uuid;v_group uuid;
 v_key text;v_category text;v_s name;v_price numeric;
 v_sort int:=0;v_count int:=0;
begin
 if auth.uid() is null or not public.is_admin()
    or v_context->>'role'<>'super_admin'
    or p_channel not in ('preview','production')
    or not public.admin_environment_allowed(p_channel)
    or (v_context->>'zone_id' is not null and
       (v_context->>'zone_id')::uuid<>p_zone_id) then
   raise exception 'Solo un superadministrador de este entorno puede crear demos';
 end if;
 if p_template_key not in ('burgers','pizza','home_cooking') then
   raise exception 'Plantilla demo no válida';
 end if;
 select z.currency_code,z.name into v_currency,v_zone_name
 from public.service_zones z where z.id=p_zone_id and z.active;
 if v_currency not in ('BOB','CLP') then
   raise exception 'Solo ciudades con CLP o BOB';
 end if;
 if not exists(select 1 from public.marketplace_categories
     where category_key='restaurants') then
   raise exception 'Categoría restaurantes no configurada';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(
    p_zone_id::text||p_channel||p_template_key,0));
 select d.merchant_id into v_merchant
 from public.marketplace_demo_restaurants d
 where d.zone_id=p_zone_id and d.channel=p_channel
   and d.template_key=p_template_key;
 if v_merchant is not null then
   return jsonb_build_object('merchant_id',v_merchant,'created',false,
      'channel',p_channel,'template',p_template_key,
      'notice','Este demo ya existe. Tus cambios se conservaron.');
 end if;
 v_name:=case p_template_key
   when 'burgers' then 'Express Burger DEMO'
   when 'pizza' then 'La Pizza Express DEMO'
   else 'Sabores Caseros DEMO' end;
 v_desc:=case p_template_key
   when 'burgers' then 'Hamburguesas, papas y bebidas · RESTAURANTE DE PRUEBA'
   when 'pizza' then 'Pizzas artesanales, extras y bebidas · RESTAURANTE DE PRUEBA'
   else 'Almuerzos caseros y combos · RESTAURANTE DE PRUEBA' end;
 v_address:='Dirección simulada · '||v_zone_name||' · NO ES UN COMERCIO REAL';
 insert into public.marketplace_merchants(
   zone_id,category_key,name,description,active,preview_visible,
   production_visible,rating,eta_min_minutes,eta_max_minutes,
   delivery_fee,sort_order,address,business_hours,open_override,tags
 ) values(
   p_zone_id,'restaurants',v_name,v_desc,true,
   p_channel='preview',false,4.8,20,35,0,900,
   v_address,
   '{"mon":{"open":"09:00","close":"23:00"},"tue":{"open":"09:00","close":"23:00"},"wed":{"open":"09:00","close":"23:00"},"thu":{"open":"09:00","close":"23:00"},"fri":{"open":"09:00","close":"23:00"},"sat":{"open":"10:00","close":"23:00"}}'::jsonb,
   p_channel='preview',
   array['DEMO','PRUEBA','SIN DINERO REAL']::text[]
 ) returning id into v_merchant;
 insert into public.marketplace_demo_restaurants(
   merchant_id,zone_id,channel,template_key,created_by
 ) values(v_merchant,p_zone_id,p_channel,p_template_key,auth.uid());
 v_sections:=case p_template_key
   when 'burgers' then
      '[{"key":"hamburguesas","label":"Hamburguesas"},
        {"key":"acompanamientos","label":"Acompañamientos"},
        {"key":"bebidas","label":"Bebidas"}]'::jsonb
   when 'pizza' then
      '[{"key":"pizzas","label":"Pizzas"},
        {"key":"extras","label":"Acompañamientos"},
        {"key":"bebidas","label":"Bebidas"}]'::jsonb
   else
      '[{"key":"almuerzos","label":"Almuerzos"},
        {"key":"combos","label":"Combos"},
        {"key":"bebidas","label":"Bebidas"}]'::jsonb end;
 for v_entry in select value from jsonb_array_elements(v_sections) loop
   v_sort:=v_sort+1;
   insert into public.marketplace_menu_sections(
     merchant_id,section_key,name,sort_order,active,
     preview_visible,production_visible
   )values(v_merchant,v_entry->>'key',v_entry->>'label',
     v_sort*10,true,p_channel='preview',false);
 end loop;
 -- Prices are templates per currency, not a mistaken currency conversion.
 v_products:=case p_template_key
 when 'burgers' then
   '[{"n":"Hamburguesa clásica","d":"Carne, queso, lechuga y salsa de la casa","s":"hamburguesas","clp":6990,"bob":45},
     {"n":"Hamburguesa doble","d":"Doble carne y queso, pepinillos","s":"hamburguesas","clp":8990,"bob":62},
     {"n":"Hamburguesa vegetariana","d":"Medallón vegetal, tomate y lechuga","s":"hamburguesas","clp":6490,"bob":43},
     {"n":"Papas fritas grandes","d":"Porción para compartir","s":"acompanamientos","clp":2990,"bob":20},
     {"n":"Aros de cebolla","d":"Aros crujientes con salsa","s":"acompanamientos","clp":2490,"bob":18},
     {"n":"Bebida 350 ml","d":"Bebida individual fría","s":"bebidas","clp":1490,"bob":10}]'::jsonb
 when 'pizza' then
   '[{"n":"Pizza margarita","d":"Queso, tomate y albahaca","s":"pizzas","clp":9990,"bob":75},
     {"n":"Pizza pepperoni","d":"Pepperoni y queso mozzarella","s":"pizzas","clp":11990,"bob":88},
     {"n":"Pizza vegetariana","d":"Pimientos, champiñones y aceitunas","s":"pizzas","clp":10990,"bob":80},
     {"n":"Pan de ajo","d":"Con mantequilla y perejil","s":"extras","clp":2990,"bob":22},
     {"n":"Porción de lasaña","d":"Salsa casera y queso gratinado","s":"extras","clp":5990,"bob":46},
     {"n":"Gaseosa 1,5 L","d":"Bebida grande para compartir","s":"bebidas","clp":2490,"bob":18}]'::jsonb
 else
   '[{"n":"Menú pollo a la plancha","d":"Pollo con arroz y ensalada","s":"almuerzos","clp":7990,"bob":48},
     {"n":"Menú milanesa","d":"Milanesa, arroz y papas","s":"almuerzos","clp":8490,"bob":52},
     {"n":"Menú vegetariano","d":"Legumbres, verduras y guarnición","s":"almuerzos","clp":6990,"bob":42},
     {"n":"Combo familiar","d":"Dos platos, dos bebidas","s":"combos","clp":15990,"bob":95},
     {"n":"Ensalada de temporada","d":"Verduras frescas y aderezo","s":"combos","clp":3990,"bob":25},
     {"n":"Jugo natural","d":"Jugo del día","s":"bebidas","clp":2490,"bob":15}]'::jsonb
 end;
 for v_entry in select value from jsonb_array_elements(v_products) loop
   v_count:=v_count+1;
   select id into v_section from public.marketplace_menu_sections
     where merchant_id=v_merchant and section_key=v_entry->>'s';
   v_price:=case when v_currency='CLP' then (v_entry->>'clp')::numeric
     else (v_entry->>'bob')::numeric end;
   insert into public.marketplace_products(
     merchant_id,menu_section_id,name,description,price,currency_code,
     active,sort_order,is_featured,tags
   )values(v_merchant,v_section,v_entry->>'n',v_entry->>'d',
      v_price,v_currency,true,v_count*10,v_count<=2,
      array['DEMO','PRUEBA']::text[])
   returning id into v_product;
   if v_count=1 then
     insert into public.marketplace_product_modifier_groups(
       product_id,name,description,min_select,max_select,required,sort_order
     )values(v_product,'Extras','Opciones de ejemplo',0,2,false,10)
     returning id into v_group;
     insert into public.marketplace_product_modifiers(
       group_id,name,price_delta,sort_order
     )values(v_group,'Extra queso',case when v_currency='CLP' then 990 else 7 end,10),
       (v_group,'Sin cebolla',0,20),
       (v_group,'Salsa adicional',case when v_currency='CLP' then 490 else 3 end,30);
   end if;
 end loop;
 -- Plus benefits remain OFF until explicitly configured by Express.
 insert into public.marketplace_plus_merchant_benefits(
   merchant_id,enabled,discount_percent,free_delivery,
   exclusive_promo,funded_by
 )values(v_merchant,false,0,false,false,'express')
 on conflict(merchant_id) do nothing;
 perform public.admin_log_action('create','marketplace_demo_restaurant',
   v_merchant::text,jsonb_build_object('zone',p_zone_id,'channel',p_channel,
   'template',p_template_key,'products',v_count,'production_hidden',true));
 return jsonb_build_object('merchant_id',v_merchant,'created',true,
   'channel',p_channel,'template',p_template_key,'name',v_name,
   'currency',v_currency,'product_count',v_count,
   'production_hidden',true,'no_real_charges',true);
end $$;
revoke all on function public.admin_marketplace_create_demo_restaurant(uuid,text,text)
 from public,anon;
grant execute on function public.admin_marketplace_create_demo_restaurant(uuid,text,text)
 to authenticated;

create or replace function public.admin_marketplace_list_demo_restaurants(
 p_zone_id uuid,p_channel text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_ctx jsonb:=public.admin_access_context();
begin
 if auth.uid() is null or not public.is_admin()
 or p_channel not in ('preview','production')
 or not public.admin_environment_allowed(p_channel)
 or (v_ctx->>'zone_id' is not null and
    (v_ctx->>'zone_id')::uuid<>p_zone_id) then
 raise exception 'No autorizado';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object(
  'merchant_id',m.id,'name',m.name,'template',d.template_key,
  'channel',d.channel,'active',m.active,'preview_visible',m.preview_visible,
  'production_visible',m.production_visible,'created_at',d.created_at,
  'product_count',(select count(*) from public.marketplace_products p
    where p.merchant_id=m.id),
  'merchant_users',(select count(*) from public.marketplace_merchant_users mu
    where mu.merchant_id=m.id and mu.active)
 ) order by d.created_at desc),'[]'::jsonb)
 from public.marketplace_demo_restaurants d
 join public.marketplace_merchants m on m.id=d.merchant_id
 where d.zone_id=p_zone_id and d.channel=p_channel);
end $$;
revoke all on function public.admin_marketplace_list_demo_restaurants(uuid,text)
 from public,anon;
grant execute on function public.admin_marketplace_list_demo_restaurants(uuid,text)
 to authenticated;

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
  -- A demo belongs to exactly one environment. Production demos are
  -- deliberately catalogue-only, never payable or orderable.
  if exists(select 1 from public.marketplace_demo_restaurants d
            where d.merchant_id=p_merchant_id
              and (d.channel<>lower(coalesce(p_channel,'production'))
                   or d.channel='production')) then
    raise exception 'Restaurante demo privado: no permite pedidos reales';
  end if;

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
commit;