-- Merchant self-service catalogue, business availability and statistics,
-- strictly limited to assigned merchants and account-bound runtime.
begin;
create or replace function public.marketplace_merchant_manage_state(
 p_merchant_id uuid,p_channel text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_role text;v_currency text;
begin
 select mu.role into v_role
 from public.marketplace_merchant_users mu
 join public.account_runtime_bindings arb
   on arb.user_id=mu.user_id and arb.environment=p_channel
 where mu.merchant_id=p_merchant_id and mu.user_id=auth.uid()
   and mu.active;
 if v_role is null or p_channel not in ('preview','production') then
   raise exception 'No autorizado';end if;
 select z.currency_code into v_currency
 from public.marketplace_merchants m
 join public.service_zones z on z.id=m.zone_id
 where m.id=p_merchant_id and m.active;
 if v_currency is null then raise exception 'Restaurante no disponible';end if;
 return jsonb_build_object(
   'role',v_role,'currency',v_currency,
   'merchant',(select jsonb_build_object(
     'id',m.id,'name',m.name,'open_override',m.open_override,
     'active',m.active,'business_hours',m.business_hours
   ) from public.marketplace_merchants m where m.id=p_merchant_id),
   'products',(select coalesce(jsonb_agg(jsonb_build_object(
     'id',p.id,'name',p.name,'description',p.description,
     'price',p.price,'active',p.active,'image_url',p.image_url,
     'sold_count',p.sold_count,'currency',p.currency_code
   ) order by p.sort_order,p.name),'[]'::jsonb)
    from public.marketplace_products p where p.merchant_id=p_merchant_id),
   'stats',(select jsonb_build_object(
     'orders',count(o.id),
     'delivered',count(o.id) filter(where o.status='delivered'),
     'sales_products',coalesce(sum(o.merchant_products_amount) filter(
       where o.status='delivered'),0),
     'pending',count(o.id) filter(where o.status not in('delivered','cancelled'))
   ) from public.marketplace_orders o where o.merchant_id=p_merchant_id
       and o.channel=p_channel
       and o.created_at>=now()-interval '30 days')
 );
end $$;
revoke all on function public.marketplace_merchant_manage_state(uuid,text)
 from public,anon;
grant execute on function public.marketplace_merchant_manage_state(uuid,text)
 to authenticated;

create or replace function public.marketplace_merchant_set_open(
 p_merchant_id uuid,p_open boolean,p_channel text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text;
begin
 select mu.role into v_role from public.marketplace_merchant_users mu
 join public.account_runtime_bindings arb on arb.user_id=mu.user_id
 where mu.merchant_id=p_merchant_id and mu.user_id=auth.uid()
   and mu.active and arb.environment=p_channel;
 if v_role not in ('owner','manager') or p_channel not in('preview','production')
 then raise exception 'Solo el propietario o encargado puede abrir/cerrar';end if;
 -- Store-wide operating status; admin controls module visibility separately.
 update public.marketplace_merchants set open_override=p_open,updated_at=now()
 where id=p_merchant_id and active;
 if not found then raise exception 'Comercio no disponible';end if;
 return jsonb_build_object('open_override',p_open);
end $$;
revoke all on function public.marketplace_merchant_set_open(uuid,boolean,text)
 from public,anon;
grant execute on function public.marketplace_merchant_set_open(uuid,boolean,text)
 to authenticated;

create or replace function public.marketplace_merchant_upsert_product(
 p_merchant_id uuid,p_product_id uuid,p_name text,p_description text,
 p_price numeric,p_active boolean,p_image_url text,p_channel text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text;v_currency text;v_result public.marketplace_products%rowtype;
begin
 select mu.role into v_role from public.marketplace_merchant_users mu
 join public.account_runtime_bindings arb
 on arb.user_id=mu.user_id and arb.environment=p_channel
 where mu.merchant_id=p_merchant_id and mu.user_id=auth.uid() and mu.active;
 if v_role not in ('owner','manager') or p_channel not in('preview','production')
 then raise exception 'No tienes permisos para productos';end if;
 select z.currency_code into v_currency
 from public.marketplace_merchants m join public.service_zones z on z.id=m.zone_id
 where m.id=p_merchant_id and m.active;
 if v_currency is null then raise exception 'Comercio no encontrado';end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 100
   or length(coalesce(p_description,''))>1500
   or p_price is null or p_price<0 or p_price>10000000
   or (v_currency='CLP' and mod(p_price,1)<>0)
   or length(coalesce(p_image_url,''))>1000 then
   raise exception 'Producto inválido';end if;
 if p_product_id is not null and not exists(
   select 1 from public.marketplace_products
   where id=p_product_id and merchant_id=p_merchant_id
 ) then raise exception 'No puedes editar un producto ajeno';end if;
 insert into public.marketplace_products(
   id,merchant_id,name,description,price,currency_code,active,image_url
 ) values(
   coalesce(p_product_id,gen_random_uuid()),p_merchant_id,
   trim(p_name),coalesce(p_description,''),p_price,v_currency,
   coalesce(p_active,true),nullif(trim(coalesce(p_image_url,'')),'')
 ) on conflict(id) do update set
    name=excluded.name,description=excluded.description,
    price=excluded.price,active=excluded.active,
    image_url=excluded.image_url,updated_at=now()
 returning * into v_result;
 return jsonb_build_object('id',v_result.id,'name',v_result.name,
   'price',v_result.price,'active',v_result.active);
end $$;
revoke all on function public.marketplace_merchant_upsert_product(
 uuid,uuid,text,text,numeric,boolean,text,text
) from public,anon;
grant execute on function public.marketplace_merchant_upsert_product(
 uuid,uuid,text,text,numeric,boolean,text,text
) to authenticated;
commit;