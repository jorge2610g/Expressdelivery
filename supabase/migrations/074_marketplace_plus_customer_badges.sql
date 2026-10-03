
create or replace function public.marketplace_home(
  p_channel text default 'production'::text,
  p_lat numeric default null::numeric,
  p_lng numeric default null::numeric
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_preview boolean := lower(coalesce(p_channel,'production')) = 'preview';
  v_enabled boolean;
  v_settings jsonb;
  v_categories jsonb;
  v_banners jsonb;
  v_merchants jsonb;
  v_zone_id uuid;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if p_lat is not null and p_lng is not null then
    v_zone_id := public.service_zone_id_for_point(p_lat,p_lng);
  else
    select last_zone_id into v_zone_id
    from public.users where id=v_uid;
  end if;

  select
    case when v_preview then preview_enabled else production_enabled end,
    jsonb_build_object(
      'module_name',module_name,
      'search_placeholder',search_placeholder,
      'hero_title',hero_title,
      'hero_subtitle',hero_subtitle,
      'preview_enabled',preview_enabled,
      'production_enabled',production_enabled
    )
  into v_enabled,v_settings
  from public.marketplace_settings
  where id=true;

  if coalesce(v_enabled,false) is false then
    return jsonb_build_object(
      'enabled',false,
      'channel',case when v_preview then 'preview' else 'production' end,
      'settings',coalesce(v_settings,'{}'::jsonb),
      'categories','[]'::jsonb,
      'banners','[]'::jsonb,
      'merchants','[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),
    '[]'::jsonb
  )
  into v_categories
  from (
    select id,category_key,name,icon_key,sort_order
    from public.marketplace_categories
    where active=true
      and case when v_preview then preview_visible else production_visible end
  ) x;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.sort_order),
    '[]'::jsonb
  )
  into v_banners
  from (
    select id,title,subtitle,cta_label,style_key,sort_order
    from public.marketplace_banners
    where active=true
      and case when v_preview then preview_visible else production_visible end
  ) x;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),
    '[]'::jsonb
  )
  into v_merchants
  from (
    select
      m.id,m.category_key,m.name,m.description,m.image_url,m.rating,
      m.eta_min_minutes,m.eta_max_minutes,m.delivery_fee,m.sort_order,
      z.currency_code,
      c.name as category_name,
      coalesce(b.enabled,false) as plus_enabled,
      coalesce(b.discount_percent,0) as plus_discount_percent,
      coalesce(b.free_delivery,false) as plus_free_delivery,
      coalesce(b.exclusive_promo,false) as plus_exclusive_promo,
      coalesce((
        select string_agg(
          lower(concat_ws(' ',p.name,coalesce(p.description,''))),
          ' '
        )
        from public.marketplace_products p
        where p.merchant_id=m.id and p.active=true
      ),'') as search_terms
    from public.marketplace_merchants m
    left join public.service_zones z on z.id=m.zone_id
    left join public.marketplace_categories c
      on c.category_key=m.category_key
    left join public.marketplace_plus_merchant_benefits b
      on b.merchant_id=m.id
    where m.active=true
      and (m.zone_id is null or v_zone_id is null or m.zone_id=v_zone_id)
      and case when v_preview then m.preview_visible else m.production_visible end
  ) x;

  return jsonb_build_object(
    'enabled',true,
    'channel',case when v_preview then 'preview' else 'production' end,
    'settings',coalesce(v_settings,'{}'::jsonb),
    'categories',coalesce(v_categories,'[]'::jsonb),
    'banners',coalesce(v_banners,'[]'::jsonb),
    'merchants',coalesce(v_merchants,'[]'::jsonb)
  );
end;
$function$;

create or replace function public.marketplace_merchant_detail(
  p_merchant_id uuid,
  p_channel text default 'production'::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
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
    'currency_code',coalesce(z.currency_code,'CLP'),
    'latitude',m.latitude,
    'longitude',m.longitude,
    'address',m.address,
    'plus_enabled',coalesce(b.enabled,false),
    'plus_discount_percent',coalesce(b.discount_percent,0),
    'plus_free_delivery',coalesce(b.free_delivery,false),
    'plus_exclusive_promo',coalesce(b.exclusive_promo,false)
  )
  into v_merchant
  from public.marketplace_merchants m
  left join public.service_zones z on z.id=m.zone_id
  left join public.marketplace_plus_merchant_benefits b
    on b.merchant_id=m.id
  where m.id=p_merchant_id
    and m.active=true
    and case when v_preview then m.preview_visible else m.production_visible end;

  if v_merchant is null then
    raise exception 'Comercio no disponible';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),
    '[]'::jsonb
  )
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
