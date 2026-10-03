-- Admin CRUD and client detail for Express Market merchants/products.

create or replace function public.admin_marketplace_upsert_merchant(
  p_id uuid,
  p_zone_id uuid,
  p_category_key text,
  p_name text,
  p_description text,
  p_image_url text,
  p_active boolean,
  p_preview_visible boolean,
  p_production_visible boolean,
  p_rating numeric,
  p_eta_min_minutes integer,
  p_eta_max_minutes integer,
  p_delivery_fee numeric,
  p_sort_order integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_eta_min_minutes < 0 or p_eta_max_minutes < p_eta_min_minutes then
    raise exception 'Rango de entrega no válido';
  end if;

  if p_id is null then
    insert into public.marketplace_merchants(
      zone_id,category_key,name,description,image_url,active,
      preview_visible,production_visible,rating,
      eta_min_minutes,eta_max_minutes,delivery_fee,sort_order,updated_at
    ) values(
      p_zone_id,lower(trim(p_category_key)),trim(p_name),p_description,p_image_url,
      coalesce(p_active,true),coalesce(p_preview_visible,true),
      coalesce(p_production_visible,false),
      least(5,greatest(0,coalesce(p_rating,5))),
      greatest(0,coalesce(p_eta_min_minutes,15)),
      greatest(coalesce(p_eta_min_minutes,15),coalesce(p_eta_max_minutes,40)),
      greatest(0,coalesce(p_delivery_fee,0)),
      coalesce(p_sort_order,100),now()
    ) returning id into v_id;
  else
    update public.marketplace_merchants
    set zone_id=p_zone_id,
        category_key=lower(trim(p_category_key)),
        name=trim(p_name),
        description=p_description,
        image_url=p_image_url,
        active=coalesce(p_active,true),
        preview_visible=coalesce(p_preview_visible,true),
        production_visible=coalesce(p_production_visible,false),
        rating=least(5,greatest(0,coalesce(p_rating,5))),
        eta_min_minutes=greatest(0,coalesce(p_eta_min_minutes,15)),
        eta_max_minutes=greatest(coalesce(p_eta_min_minutes,15),coalesce(p_eta_max_minutes,40)),
        delivery_fee=greatest(0,coalesce(p_delivery_fee,0)),
        sort_order=coalesce(p_sort_order,100),
        updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;

  perform public.admin_log_action(
    'upsert','marketplace_merchant',v_id::text,
    jsonb_build_object('name',p_name,'zone_id',p_zone_id,'category_key',p_category_key)
  );
  return v_id;
end;
$function$;

create or replace function public.admin_marketplace_merchant_detail(p_merchant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return jsonb_build_object(
    'merchant',(select to_jsonb(m) from public.marketplace_merchants m where m.id=p_merchant_id),
    'products',(
      select coalesce(jsonb_agg(to_jsonb(p) order by p.sort_order,p.name),'[]'::jsonb)
      from public.marketplace_products p where p.merchant_id=p_merchant_id
    )
  );
end;
$function$;

create or replace function public.admin_marketplace_upsert_product(
  p_id uuid,
  p_merchant_id uuid,
  p_name text,
  p_description text,
  p_price numeric,
  p_currency_code text,
  p_image_url text,
  p_active boolean,
  p_sort_order integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_price < 0 then raise exception 'Precio no válido'; end if;

  if p_id is null then
    insert into public.marketplace_products(
      merchant_id,name,description,price,currency_code,image_url,active,sort_order,updated_at
    ) values(
      p_merchant_id,trim(p_name),p_description,p_price,
      upper(coalesce(nullif(trim(p_currency_code),''),'CLP')),
      p_image_url,coalesce(p_active,true),coalesce(p_sort_order,100),now()
    ) returning id into v_id;
  else
    update public.marketplace_products
    set merchant_id=p_merchant_id,
        name=trim(p_name),
        description=p_description,
        price=p_price,
        currency_code=upper(coalesce(nullif(trim(p_currency_code),''),'CLP')),
        image_url=p_image_url,
        active=coalesce(p_active,true),
        sort_order=coalesce(p_sort_order,100),
        updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;

  perform public.admin_log_action(
    'upsert','marketplace_product',v_id::text,
    jsonb_build_object('merchant_id',p_merchant_id,'name',p_name,'price',p_price)
  );
  return v_id;
end;
$function$;

create or replace function public.marketplace_merchant_detail(
  p_merchant_id uuid,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_preview boolean := lower(coalesce(p_channel,'production'))='preview';
  v_merchant jsonb;
  v_products jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'id',m.id,
    'category_key',m.category_key,
    'name',m.name,
    'description',m.description,
    'image_url',m.image_url,
    'rating',m.rating,
    'eta_min_minutes',m.eta_min_minutes,
    'eta_max_minutes',m.eta_max_minutes,
    'delivery_fee',m.delivery_fee,
    'currency_code',coalesce(z.currency_code,'CLP')
  )
  into v_merchant
  from public.marketplace_merchants m
  left join public.service_zones z on z.id=m.zone_id
  where m.id=p_merchant_id
    and m.active=true
    and case when v_preview then m.preview_visible else m.production_visible end;

  if v_merchant is null then raise exception 'Comercio no disponible'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb)
  into v_products
  from (
    select id,name,description,price,currency_code,image_url,sort_order
    from public.marketplace_products
    where merchant_id=p_merchant_id and active=true
  ) x;

  return jsonb_build_object(
    'merchant',v_merchant,
    'products',coalesce(v_products,'[]'::jsonb)
  );
end;
$function$;

revoke all on function public.admin_marketplace_upsert_merchant(uuid,uuid,text,text,text,text,boolean,boolean,boolean,numeric,integer,integer,numeric,integer) from public,anon;
revoke all on function public.admin_marketplace_merchant_detail(uuid) from public,anon;
revoke all on function public.admin_marketplace_upsert_product(uuid,uuid,text,text,numeric,text,text,boolean,integer) from public,anon;
revoke all on function public.marketplace_merchant_detail(uuid,text) from public,anon;
grant execute on function public.admin_marketplace_upsert_merchant(uuid,uuid,text,text,text,text,boolean,boolean,boolean,numeric,integer,integer,numeric,integer) to authenticated;
grant execute on function public.admin_marketplace_merchant_detail(uuid) to authenticated;
grant execute on function public.admin_marketplace_upsert_product(uuid,uuid,text,text,numeric,text,text,boolean,integer) to authenticated;
grant execute on function public.marketplace_merchant_detail(uuid,text) to authenticated;
