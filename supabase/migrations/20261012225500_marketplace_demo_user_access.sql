-- Initial demo ownership, role-aware assignment and anti-cross-channel guard.
begin;
create or replace function public.guard_demo_merchant_membership()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_channel text;
begin
 select channel into v_channel from public.marketplace_demo_restaurants
 where merchant_id=new.merchant_id;
 if v_channel is null then return new;end if;
 if not exists(select 1 from public.account_runtime_bindings b
   where b.user_id=new.user_id and b.environment=v_channel) then
   raise exception 'La cuenta no pertenece al entorno de este restaurante demo';
 end if;
 if auth.uid() is not null and not public.admin_environment_allowed(v_channel)
    and auth.uid() is distinct from new.user_id then
   raise exception 'No puedes asignar usuarios a un demo de otro entorno';
 end if;
 return new;
end $$;
create trigger trg_demo_merchant_membership
 before insert or update on public.marketplace_merchant_users
 for each row execute function public.guard_demo_merchant_membership();

create or replace function public.admin_marketplace_assign_demo_user(
 p_merchant_id uuid,p_channel text,p_email text,p_role text default 'owner'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb:=public.admin_access_context();
 v_zone uuid;v_target uuid;v_email text:=lower(trim(coalesce(p_email,'')));
 v_role text:=lower(trim(coalesce(p_role,'owner')));
begin
 select d.zone_id into v_zone from public.marketplace_demo_restaurants d
 where d.merchant_id=p_merchant_id and d.channel=p_channel;
 if v_zone is null or auth.uid() is null or not public.is_admin()
    or v_ctx->>'role'<>'super_admin'
    or not public.admin_environment_allowed(p_channel)
    or (v_ctx->>'zone_id' is not null and (v_ctx->>'zone_id')::uuid<>v_zone)
 then raise exception 'No autorizado a asignar este demo';end if;
 if v_role not in ('owner','manager','staff') or
    v_email not like '%@%' or length(v_email)>254 then
   raise exception 'Correo o rol inválido';end if;
 select id into v_target from auth.users where lower(email)=v_email limit 1;
 if v_target is null then raise exception 'La cuenta no existe. Regístrala primero.';end if;
 if not exists(select 1 from public.account_runtime_bindings
  where user_id=v_target and environment=p_channel) then
   raise exception 'La cuenta pertenece a otro entorno. Usa un usuario de prueba aislado.';
 end if;
 insert into public.marketplace_merchant_users(merchant_id,user_id,role,active)
 values(p_merchant_id,v_target,v_role,true)
 on conflict(merchant_id,user_id) do update set
  role=excluded.role,active=true;
 perform public.admin_log_action('assign','marketplace_demo_merchant_user',
 p_merchant_id::text,jsonb_build_object('user_id',v_target,'channel',p_channel,
 'role',v_role));
 return jsonb_build_object('merchant_id',p_merchant_id,'user_id',v_target,
 'role',v_role,'channel',p_channel);
end $$;
revoke all on function public.admin_marketplace_assign_demo_user(uuid,text,text,text)
 from public,anon;
grant execute on function public.admin_marketplace_assign_demo_user(uuid,text,text,text)
 to authenticated;

CREATE OR REPLACE FUNCTION public.admin_marketplace_create_demo_restaurant(p_zone_id uuid, p_channel text, p_template_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 -- Make the creator an initial test-owner in this same environment.
 -- No passwords or accounts are generated; only the existing admin identity
 -- is attached for immediate portal QA.
 insert into public.marketplace_merchant_users(merchant_id,user_id,role,active)
 values(v_merchant,auth.uid(),'owner',true)
 on conflict(merchant_id,user_id) do update set
   role='owner',active=true;
 perform public.admin_log_action('create','marketplace_demo_restaurant',
   v_merchant::text,jsonb_build_object('zone',p_zone_id,'channel',p_channel,
   'template',p_template_key,'products',v_count,'production_hidden',true));
 return jsonb_build_object('merchant_id',v_merchant,'created',true,
   'channel',p_channel,'template',p_template_key,'name',v_name,
   'currency',v_currency,'product_count',v_count,
   'production_hidden',true,'no_real_charges',true);
end $function$;
commit;