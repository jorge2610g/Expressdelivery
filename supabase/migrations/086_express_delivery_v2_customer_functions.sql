-- Express Delivery V2 customer APIs.
-- All customer-facing SECURITY DEFINER RPCs validate auth.uid() and account state.
-- PUBLIC/anon execute is revoked explicitly at the end of this migration.

create or replace function public.marketplace_product_effective_price(
  p_product_id uuid
)
returns numeric
language sql
stable
security definer
set search_path='public'
as $$
  select
    case
      when p.promo_price is not null
       and p.promo_price >= 0
       and (p.promo_start_at is null or p.promo_start_at <= now())
       and (p.promo_end_at is null or p.promo_end_at > now())
      then p.promo_price
      else p.price
    end
  from public.marketplace_products p
  where p.id=p_product_id and p.active=true
$$;

create or replace function public.marketplace_available_zones(
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
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.country,x.city),'[]'::jsonb)
  into v_result
  from (
    select
      z.id,z.zone_key,z.name,z.city,z.country,z.country_code,z.currency_code,
      z.center_latitude,z.center_longitude,z.radius_km,z.payment_provider,
      case when v_preview then mz.preview_enabled else mz.production_enabled end as enabled
    from public.service_zones z
    join public.marketplace_zone_settings mz on mz.zone_id=z.id
    where z.active=true
      and case when v_preview then mz.preview_enabled else mz.production_enabled end
  ) x;

  return v_result;
end;
$$;

create or replace function public.marketplace_saved_addresses_v2(
  p_zone_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $$
declare
  v_uid uuid:=auth.uid();
  v_zone_id uuid:=p_zone_id;
  v_country text;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if v_zone_id is null then
    select u.last_zone_id into v_zone_id
    from public.users u where u.id=v_uid;
  end if;

  select z.country_code into v_country
  from public.service_zones z where z.id=v_zone_id;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.is_default desc,x.created_at),'[]'::jsonb)
  into v_result
  from (
    select a.id,a.label,a.address,a.latitude,a.longitude,a.zone_id,a.country_code,
           a.is_default,a.delivery_instructions,a.created_at
    from public.saved_addresses a
    where a.user_id=v_uid
      and (
        v_country is null
        or a.country_code=v_country
        or (
          a.country_code is null
          and (
            a.zone_id is null
            or a.zone_id=v_zone_id
          )
        )
      )
  ) x;

  return v_result;
end;
$$;

create or replace function public.marketplace_add_saved_address_v2(
  p_label text,
  p_address text,
  p_lat numeric default null,
  p_lng numeric default null,
  p_zone_id uuid default null,
  p_instructions text default null,
  p_make_default boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_uid uuid:=auth.uid();
  v_zone_id uuid:=p_zone_id;
  v_country text;
  v_row public.saved_addresses%rowtype;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if nullif(trim(coalesce(p_address,'')),'') is null then
    raise exception 'Dirección requerida';
  end if;

  if v_zone_id is null and p_lat is not null and p_lng is not null then
    v_zone_id:=public.service_zone_id_for_point(p_lat,p_lng);
  end if;

  if v_zone_id is null then
    select u.last_zone_id into v_zone_id
    from public.users u where u.id=v_uid;
  end if;

  select z.country_code into v_country
  from public.service_zones z where z.id=v_zone_id and z.active=true;

  if v_zone_id is null or v_country is null then
    raise exception 'No se pudo determinar la zona de esta dirección';
  end if;

  if coalesce(p_make_default,false) then
    update public.saved_addresses
    set is_default=false,updated_at=now()
    where user_id=v_uid and country_code=v_country;
  end if;

  insert into public.saved_addresses(
    user_id,label,address,latitude,longitude,zone_id,country_code,
    is_default,delivery_instructions
  )
  values(
    v_uid,
    coalesce(nullif(trim(p_label),''),'Dirección'),
    trim(p_address),
    p_lat,p_lng,v_zone_id,v_country,
    coalesce(p_make_default,false),
    nullif(trim(coalesce(p_instructions,'')),'')
  )
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

create or replace function public.marketplace_home_v2(
  p_channel text default 'production',
  p_zone_id uuid default null,
  p_lat numeric default null,
  p_lng numeric default null,
  p_address_id uuid default null
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
  v_zone_id uuid:=p_zone_id;
  v_country text;
  v_zone jsonb;
  v_settings jsonb;
  v_enabled boolean:=false;
  v_categories jsonb:='[]'::jsonb;
  v_banners jsonb:='[]'::jsonb;
  v_merchants jsonb:='[]'::jsonb;
  v_products jsonb:='[]'::jsonb;
  v_sections jsonb:='[]'::jsonb;
  v_addresses jsonb:='[]'::jsonb;
  v_selected_address jsonb;
  v_unread integer:=0;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if p_address_id is not null then
    select a.zone_id into v_zone_id
    from public.saved_addresses a
    where a.id=p_address_id and a.user_id=v_uid;
  end if;

  if v_zone_id is null and p_lat is not null and p_lng is not null then
    v_zone_id:=public.service_zone_id_for_point(p_lat,p_lng);
  end if;

  if v_zone_id is null then
    select u.last_zone_id into v_zone_id
    from public.users u where u.id=v_uid;
  end if;

  select z.country_code,
         jsonb_build_object(
           'id',z.id,'zone_key',z.zone_key,'name',z.name,'city',z.city,
           'country',z.country,'country_code',z.country_code,
           'currency_code',z.currency_code,'payment_provider',z.payment_provider
         )
  into v_country,v_zone
  from public.service_zones z
  join public.marketplace_zone_settings mz on mz.zone_id=z.id
  where z.id=v_zone_id
    and z.active=true
    and case when v_preview then mz.preview_enabled else mz.production_enabled end;

  if v_zone is null then
    return jsonb_build_object(
      'enabled',false,
      'channel',case when v_preview then 'preview' else 'production' end,
      'reason','zone_unavailable',
      'zone',null,
      'settings','{}'::jsonb,
      'categories','[]'::jsonb,
      'banners','[]'::jsonb,
      'merchants','[]'::jsonb,
      'featured_products','[]'::jsonb,
      'home_sections','[]'::jsonb,
      'addresses','[]'::jsonb,
      'unread_notifications',0
    );
  end if;

  select case when v_preview then s.preview_enabled else s.production_enabled end,
         jsonb_build_object(
           'module_name',s.module_name,
           'search_placeholder',s.search_placeholder,
           'hero_title',s.hero_title,
           'hero_subtitle',s.hero_subtitle,
           'preview_enabled',s.preview_enabled,
           'production_enabled',s.production_enabled
         )
  into v_enabled,v_settings
  from public.marketplace_settings s
  where s.id=true;

  if not coalesce(v_enabled,false) then
    return jsonb_build_object(
      'enabled',false,
      'channel',case when v_preview then 'preview' else 'production' end,
      'reason','module_disabled',
      'zone',v_zone,
      'settings',coalesce(v_settings,'{}'::jsonb),
      'categories','[]'::jsonb,
      'banners','[]'::jsonb,
      'merchants','[]'::jsonb,
      'featured_products','[]'::jsonb,
      'home_sections','[]'::jsonb,
      'addresses','[]'::jsonb,
      'unread_notifications',0
    );
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb)
  into v_categories
  from (
    select c.id,c.category_key,c.name,c.icon_key,c.sort_order
    from public.marketplace_categories c
    where c.active=true
      and case when v_preview then c.preview_visible else c.production_visible end
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order),'[]'::jsonb)
  into v_banners
  from (
    select b.id,b.title,b.subtitle,b.cta_label,b.style_key,b.sort_order
    from public.marketplace_banners b
    where b.active=true
      and (b.zone_id is null or b.zone_id=v_zone_id)
      and (b.country_code is null or b.country_code=v_country)
      and case when v_preview then b.preview_visible else b.production_visible end
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb)
  into v_merchants
  from (
    select
      m.id,m.category_key,m.name,m.description,m.image_url,m.rating,
      m.eta_min_minutes,m.eta_max_minutes,m.delivery_fee,m.sort_order,
      m.address,m.minimum_order,m.is_sponsored,m.tags,m.business_hours,m.open_override,
      z.currency_code,z.country_code,z.zone_key,c.name as category_name,
      coalesce(pb.enabled,false) as plus_enabled,
      coalesce(pb.discount_percent,0) as plus_discount_percent,
      coalesce(pb.free_delivery,false) as plus_free_delivery,
      coalesce(pb.exclusive_promo,false) as plus_exclusive_promo,
      exists(
        select 1
        from public.marketplace_products p
        where p.merchant_id=m.id and p.active=true
          and p.promo_price is not null
          and (p.promo_start_at is null or p.promo_start_at<=now())
          and (p.promo_end_at is null or p.promo_end_at>now())
      ) as has_deals,
      coalesce((
        select string_agg(
          lower(concat_ws(' ',p.name,coalesce(p.description,''),array_to_string(p.tags,' '))),
          ' '
        )
        from public.marketplace_products p
        where p.merchant_id=m.id and p.active=true
      ),'') as search_terms
    from public.marketplace_merchants m
    join public.service_zones z on z.id=m.zone_id
    left join public.marketplace_categories c on c.category_key=m.category_key
    left join public.marketplace_plus_merchant_benefits pb on pb.merchant_id=m.id
    where m.active=true
      and m.zone_id=v_zone_id
      and case when v_preview then m.preview_visible else m.production_visible end
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.is_sponsored desc,x.is_featured desc,x.sold_count desc,x.sort_order),'[]'::jsonb)
  into v_products
  from (
    select
      p.id,p.merchant_id,p.menu_section_id,p.name,p.description,p.price,p.compare_at_price,
      public.marketplace_product_effective_price(p.id) as effective_price,
      p.promo_price,p.promo_start_at,p.promo_end_at,p.promo_label,
      p.currency_code,p.image_url,p.sort_order,p.is_sponsored,p.is_featured,
      p.rating,p.review_count,p.sold_count,p.tags,
      m.name as merchant_name,m.category_key,z.zone_key,z.country_code,
      case
        when p.promo_price is not null
         and (p.promo_start_at is null or p.promo_start_at<=now())
         and (p.promo_end_at is null or p.promo_end_at>now())
         and p.price>0
        then round((p.price-p.promo_price)*100/p.price)
        else 0
      end as discount_percent
    from public.marketplace_products p
    join public.marketplace_merchants m on m.id=p.merchant_id
    join public.service_zones z on z.id=m.zone_id
    where p.active=true
      and m.active=true
      and m.zone_id=v_zone_id
      and case when v_preview then m.preview_visible else m.production_visible end
    order by p.is_sponsored desc,p.is_featured desc,p.sold_count desc,p.sort_order
    limit 80
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order),'[]'::jsonb)
  into v_sections
  from (
    select distinct on (hs.section_key)
      hs.id,hs.section_key,hs.title,hs.subtitle,hs.section_type,hs.source_rule,
      hs.config,hs.sort_order
    from public.marketplace_home_sections hs
    where hs.active=true
      and (hs.starts_at is null or hs.starts_at<=now())
      and (hs.ends_at is null or hs.ends_at>now())
      and (
        hs.zone_id=v_zone_id
        or (hs.zone_id is null and hs.country_code=v_country)
        or (hs.zone_id is null and hs.country_code is null)
      )
      and case when v_preview then hs.preview_visible else hs.production_visible end
    order by hs.section_key,
      case
        when hs.zone_id=v_zone_id then 1
        when hs.zone_id is null and hs.country_code=v_country then 2
        else 3
      end,
      hs.sort_order
  ) x;

  select public.marketplace_saved_addresses_v2(v_zone_id) into v_addresses;

  if p_address_id is not null then
    select to_jsonb(a) into v_selected_address
    from public.saved_addresses a
    where a.id=p_address_id and a.user_id=v_uid;
  else
    select to_jsonb(a) into v_selected_address
    from public.saved_addresses a
    where a.user_id=v_uid
      and (a.country_code=v_country or a.country_code is null)
    order by a.is_default desc,a.updated_at desc
    limit 1;
  end if;

  select count(*)::int into v_unread
  from public.notifications n
  where n.user_id=v_uid
    and n.is_read=false
    and (
      n.type in ('marketplace_order','marketplace_promo','marketplace_plus','admin_announcement')
      or n.metadata ? 'marketplace_order_id'
    );

  return jsonb_build_object(
    'enabled',true,
    'channel',case when v_preview then 'preview' else 'production' end,
    'zone',v_zone,
    'settings',coalesce(v_settings,'{}'::jsonb),
    'categories',v_categories,
    'banners',v_banners,
    'merchants',v_merchants,
    'featured_products',v_products,
    'home_sections',v_sections,
    'addresses',v_addresses,
    'selected_address',v_selected_address,
    'unread_notifications',v_unread
  );
end;
$$;

create or replace function public.marketplace_category_feed_v2(
  p_category_key text,
  p_channel text default 'production',
  p_zone_id uuid default null,
  p_sort text default 'recommended',
  p_only_deals boolean default false,
  p_only_plus boolean default false,
  p_max_eta integer default null
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
  v_zone_id uuid:=p_zone_id;
  v_merchants jsonb;
  v_products jsonb;
  v_tags jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if v_zone_id is null then
    select u.last_zone_id into v_zone_id from public.users u where u.id=v_uid;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_merchants
  from (
    select
      m.id,m.name,m.description,m.image_url,m.rating,m.eta_min_minutes,m.eta_max_minutes,
      m.delivery_fee,m.minimum_order,m.is_sponsored,m.tags,z.currency_code,z.country_code,
      coalesce(pb.enabled,false) as plus_enabled,
      coalesce(pb.free_delivery,false) as plus_free_delivery,
      exists(
        select 1 from public.marketplace_products p
        where p.merchant_id=m.id and p.active=true
          and p.promo_price is not null
          and (p.promo_start_at is null or p.promo_start_at<=now())
          and (p.promo_end_at is null or p.promo_end_at>now())
      ) as has_deals
    from public.marketplace_merchants m
    join public.service_zones z on z.id=m.zone_id
    left join public.marketplace_plus_merchant_benefits pb on pb.merchant_id=m.id
    where m.active=true
      and m.zone_id=v_zone_id
      and m.category_key=p_category_key
      and case when v_preview then m.preview_visible else m.production_visible end
      and (not coalesce(p_only_deals,false) or exists(
        select 1 from public.marketplace_products p
        where p.merchant_id=m.id and p.active=true
          and p.promo_price is not null
          and (p.promo_start_at is null or p.promo_start_at<=now())
          and (p.promo_end_at is null or p.promo_end_at>now())
      ))
      and (not coalesce(p_only_plus,false) or coalesce(pb.enabled,false))
      and (p_max_eta is null or m.eta_max_minutes<=p_max_eta)
    order by
      case when p_sort='rating' then m.rating end desc nulls last,
      case when p_sort='eta' then m.eta_max_minutes end asc nulls last,
      case when p_sort='delivery_fee' then m.delivery_fee end asc nulls last,
      m.is_sponsored desc,m.sort_order,m.name
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_products
  from (
    select
      p.id,p.merchant_id,p.name,p.description,p.price,p.compare_at_price,
      public.marketplace_product_effective_price(p.id) effective_price,
      p.promo_label,p.image_url,p.is_sponsored,p.rating,p.review_count,p.sold_count,p.tags,
      m.name merchant_name,z.currency_code,
      case when p.price>0 and public.marketplace_product_effective_price(p.id)<p.price
        then round((p.price-public.marketplace_product_effective_price(p.id))*100/p.price)
        else 0 end discount_percent
    from public.marketplace_products p
    join public.marketplace_merchants m on m.id=p.merchant_id
    join public.service_zones z on z.id=m.zone_id
    where p.active=true and m.active=true
      and m.zone_id=v_zone_id and m.category_key=p_category_key
      and case when v_preview then m.preview_visible else m.production_visible end
    order by p.is_sponsored desc,p.sold_count desc,p.rating desc,p.sort_order
    limit 80
  ) x;

  select coalesce(jsonb_agg(t.tag order by t.tag),'[]'::jsonb) into v_tags
  from (
    select distinct unnest(p.tags) tag
    from public.marketplace_products p
    join public.marketplace_merchants m on m.id=p.merchant_id
    where p.active=true and m.active=true
      and m.zone_id=v_zone_id and m.category_key=p_category_key
  ) t
  where nullif(trim(t.tag),'') is not null;

  return jsonb_build_object(
    'category_key',p_category_key,
    'zone_id',v_zone_id,
    'merchants',v_merchants,
    'products',v_products,
    'tags',v_tags
  );
end;
$$;

create or replace function public.marketplace_merchant_detail_v2(
  p_merchant_id uuid,
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
  v_merchant jsonb;
  v_sections jsonb;
  v_products jsonb;
  v_reviews jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'id',m.id,'zone_id',m.zone_id,'category_key',m.category_key,
    'name',m.name,'description',m.description,'image_url',m.image_url,
    'rating',m.rating,'eta_min_minutes',m.eta_min_minutes,'eta_max_minutes',m.eta_max_minutes,
    'delivery_fee',m.delivery_fee,'address',m.address,'latitude',m.latitude,'longitude',m.longitude,
    'minimum_order',m.minimum_order,'business_hours',m.business_hours,'open_override',m.open_override,
    'is_sponsored',m.is_sponsored,'tags',m.tags,
    'currency_code',z.currency_code,'country_code',z.country_code,'zone_key',z.zone_key,
    'plus_enabled',coalesce(pb.enabled,false),
    'plus_discount_percent',coalesce(pb.discount_percent,0),
    'plus_free_delivery',coalesce(pb.free_delivery,false),
    'plus_exclusive_promo',coalesce(pb.exclusive_promo,false)
  )
  into v_merchant
  from public.marketplace_merchants m
  join public.service_zones z on z.id=m.zone_id
  left join public.marketplace_plus_merchant_benefits pb on pb.merchant_id=m.id
  where m.id=p_merchant_id and m.active=true
    and case when v_preview then m.preview_visible else m.production_visible end;

  if v_merchant is null then raise exception 'Comercio no disponible'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb)
  into v_sections
  from (
    select s.id,s.section_key,s.name,s.subtitle,s.sort_order
    from public.marketplace_menu_sections s
    where s.merchant_id=p_merchant_id and s.active=true
      and case when v_preview then s.preview_visible else s.production_visible end
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.section_sort,x.sort_order,x.name),'[]'::jsonb)
  into v_products
  from (
    select
      p.id,p.merchant_id,p.menu_section_id,p.name,p.description,p.price,p.compare_at_price,
      public.marketplace_product_effective_price(p.id) effective_price,
      p.promo_price,p.promo_start_at,p.promo_end_at,p.promo_label,p.currency_code,
      p.image_url,p.sort_order,p.is_sponsored,p.is_featured,p.rating,p.review_count,p.sold_count,p.tags,
      coalesce(ms.name,'Menú') section_name,coalesce(ms.sort_order,100) section_sort,
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id',g.id,'name',g.name,'description',g.description,'min_select',g.min_select,
            'max_select',g.max_select,'required',g.required,'sort_order',g.sort_order,
            'options',coalesce((
              select jsonb_agg(jsonb_build_object(
                'id',o.id,'name',o.name,'price_delta',o.price_delta,'sort_order',o.sort_order
              ) order by o.sort_order,o.name)
              from public.marketplace_product_modifiers o
              where o.group_id=g.id and o.active=true
            ),'[]'::jsonb)
          )
          order by g.sort_order,g.name
        )
        from public.marketplace_product_modifier_groups g
        where g.product_id=p.id and g.active=true
      ),'[]'::jsonb) modifier_groups,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',r.id,'rating',r.rating,'comment',r.comment,'created_at',r.created_at
        ) order by r.created_at desc)
        from (
          select * from public.marketplace_reviews rr
          where rr.product_id=p.id and rr.active=true
          order by rr.created_at desc
          limit 5
        ) r
      ),'[]'::jsonb) reviews
    from public.marketplace_products p
    left join public.marketplace_menu_sections ms on ms.id=p.menu_section_id
    where p.merchant_id=p_merchant_id and p.active=true
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_reviews
  from (
    select r.id,r.rating,r.comment,r.created_at
    from public.marketplace_reviews r
    where r.merchant_id=p_merchant_id and r.product_id is null and r.active=true
    order by r.created_at desc
    limit 30
  ) x;

  return jsonb_build_object(
    'merchant',v_merchant,
    'menu_sections',v_sections,
    'products',v_products,
    'reviews',v_reviews
  );
end;
$$;

create or replace function public.marketplace_product_detail_v2(
  p_product_id uuid,
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
  v_product jsonb;
  v_groups jsonb;
  v_reviews jsonb;
  v_recommendations jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'id',p.id,'merchant_id',p.merchant_id,'menu_section_id',p.menu_section_id,
    'name',p.name,'description',p.description,'price',p.price,'compare_at_price',p.compare_at_price,
    'effective_price',public.marketplace_product_effective_price(p.id),
    'promo_label',p.promo_label,'currency_code',z.currency_code,'image_url',p.image_url,
    'rating',p.rating,'review_count',p.review_count,'sold_count',p.sold_count,'tags',p.tags,
    'merchant_name',m.name,'merchant_image_url',m.image_url,'zone_id',m.zone_id,
    'country_code',z.country_code,'zone_key',z.zone_key
  )
  into v_product
  from public.marketplace_products p
  join public.marketplace_merchants m on m.id=p.merchant_id
  join public.service_zones z on z.id=m.zone_id
  where p.id=p_product_id and p.active=true and m.active=true
    and case when v_preview then m.preview_visible else m.production_visible end;

  if v_product is null then raise exception 'Producto no disponible'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb)
  into v_groups
  from (
    select g.id,g.name,g.description,g.min_select,g.max_select,g.required,g.sort_order,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',o.id,'name',o.name,'price_delta',o.price_delta,'sort_order',o.sort_order
        ) order by o.sort_order,o.name)
        from public.marketplace_product_modifiers o
        where o.group_id=g.id and o.active=true
      ),'[]'::jsonb) options
    from public.marketplace_product_modifier_groups g
    where g.product_id=p_product_id and g.active=true
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_reviews
  from (
    select r.id,r.rating,r.comment,r.created_at
    from public.marketplace_reviews r
    where r.product_id=p_product_id and r.active=true
    order by r.created_at desc
    limit 50
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order),'[]'::jsonb)
  into v_recommendations
  from (
    select p.id,p.name,p.description,p.image_url,p.price,
           public.marketplace_product_effective_price(p.id) effective_price,
           p.currency_code,c.sort_order
    from public.marketplace_product_cross_sells c
    join public.marketplace_products p on p.id=c.recommended_product_id
    where c.product_id=p_product_id and p.active=true
    order by c.sort_order
    limit 12
  ) x;

  return jsonb_build_object(
    'product',v_product,
    'modifier_groups',v_groups,
    'reviews',v_reviews,
    'recommendations',v_recommendations
  );
end;
$$;

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

create or replace function public.marketplace_quote_order_v2(
  p_merchant_id uuid,
  p_items jsonb,
  p_distance_km numeric default 0,
  p_tip numeric default 0,
  p_priority boolean default false,
  p_coupon_code text default null,
  p_donation numeric default 0,
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

  v_merchant_products:=v_actual_subtotal;
  if v_plus_funded_by='merchant' then
    v_merchant_products:=greatest(v_merchant_products-v_plus_discount,0);
  end if;
  if v_coupon_funded_by='merchant' then
    v_merchant_products:=greatest(v_merchant_products-v_coupon_discount,0);
  end if;

  v_total:=greatest(v_actual_subtotal-v_plus_discount-v_coupon_discount,0)
    +coalesce((v_base->>'customer_delivery_fee')::numeric,0)
    +coalesce((v_base->>'priority_fee')::numeric,0)
    +coalesce((v_base->>'tip_amount')::numeric,0)
    +v_donation;

  v_margin:=v_total
    -v_merchant_products
    -coalesce((v_base->>'driver_payout')::numeric,0)
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
    'express_margin',v_margin
  );
end;
$$;

create or replace function public.marketplace_create_order_v2(
  p_merchant_id uuid,
  p_items jsonb,
  p_distance_km numeric,
  p_tip numeric,
  p_priority boolean,
  p_payment_method text,
  p_dropoff_address text,
  p_dropoff_lat numeric default null,
  p_dropoff_lng numeric default null,
  p_saved_address_id uuid default null,
  p_merchant_note text default null,
  p_delivery_instructions text default null,
  p_delivery_option text default 'door',
  p_coupon_code text default null,
  p_donation numeric default 0,
  p_billing_profile_id uuid default null,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
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
    currency_code,subtotal,product_discount,customer_delivery_fee,priority_fee,tip_amount,
    total_amount,driver_base_payout,driver_distance_payout,driver_priority_bonus,driver_payout,
    express_margin,merchant_products_amount,collector,distance_km,is_priority,
    plus_subscription_applied,plus_subscription_id,plus_free_delivery_applied,
    plus_priority_included_applied,plus_discount_percent,
    dropoff_address,dropoff_latitude,dropoff_longitude,saved_address_id,
    merchant_note,delivery_instructions,delivery_option,coupon_id,coupon_code,coupon_discount,
    billing_profile_snapshot,donation_amount
  )
  values(
    v_uid,p_merchant_id,(v_quote->>'zone_id')::uuid,lower(coalesce(p_channel,'production')),
    case when v_method='transfer' then 'awaiting_transfer' else 'pending' end,
    v_method,
    case when v_method='transfer' then 'awaiting_receipt' else 'pending' end,
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
      when v_method='transfer' then 'Pedido creado. Esperando comprobante de transferencia.'
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
$$;

create or replace function public.marketplace_delivery_notifications(
  p_limit integer default 80
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $$
declare
  v_uid uuid:=auth.uid();
  v_rows jsonb;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_rows
  from (
    select n.id,n.title,n.body,n.type,n.is_read,n.created_at,n.metadata
    from public.notifications n
    where n.user_id=v_uid
      and (
        n.type in ('marketplace_order','marketplace_promo','marketplace_plus','admin_announcement')
        or n.metadata ? 'marketplace_order_id'
      )
    order by n.created_at desc
    limit greatest(1,least(coalesce(p_limit,80),200))
  ) x;
  return v_rows;
end;
$$;

create or replace function public.marketplace_mark_notification_read(
  p_notification_id uuid
)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'No autorizado'; end if;
  update public.notifications
  set is_read=true
  where id=p_notification_id and user_id=v_uid;
  return found;
end;
$$;

create or replace function public.marketplace_upsert_billing_profile(
  p_country_code text,
  p_legal_name text,
  p_tax_id text default null,
  p_email text default null,
  p_billing_address text default null
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text:=upper(trim(coalesce(p_country_code,'')));
  v_row public.marketplace_billing_profiles%rowtype;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if length(v_country)<>2 then raise exception 'País no válido'; end if;
  if nullif(trim(coalesce(p_legal_name,'')),'') is null then raise exception 'Nombre requerido'; end if;

  insert into public.marketplace_billing_profiles(
    user_id,country_code,legal_name,tax_id,email,billing_address,is_default
  )
  values(
    v_uid,v_country,trim(p_legal_name),nullif(trim(coalesce(p_tax_id,'')),''),
    nullif(trim(coalesce(p_email,'')),''),
    nullif(trim(coalesce(p_billing_address,'')),''),
    true
  )
  on conflict(user_id,country_code) do update set
    legal_name=excluded.legal_name,tax_id=excluded.tax_id,email=excluded.email,
    billing_address=excluded.billing_address,updated_at=now()
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

create or replace function public.marketplace_issue_order_code(
  p_order_id uuid,
  p_kind text
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_bytes bytea:=extensions.gen_random_bytes(4);
  v_number bigint;
  v_code text;
  v_hash text;
  v_kind text:=lower(trim(coalesce(p_kind,'')));
  v_authorized boolean:=false;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  select * into v_order from public.marketplace_orders where id=p_order_id;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if v_kind='delivery' then
    v_authorized:=v_order.customer_id=v_uid;
  elsif v_kind='pickup' then
    v_authorized:=exists(
      select 1 from public.marketplace_merchant_users mu
      where mu.merchant_id=v_order.merchant_id and mu.user_id=v_uid
    );
  else
    raise exception 'Tipo de código no válido';
  end if;

  if not v_authorized then raise exception 'No autorizado'; end if;

  v_number:=(
    get_byte(v_bytes,0)::bigint*16777216
    +get_byte(v_bytes,1)::bigint*65536
    +get_byte(v_bytes,2)::bigint*256
    +get_byte(v_bytes,3)::bigint
  )%1000000;
  v_code:=lpad(v_number::text,6,'0');
  v_hash:=encode(extensions.digest(v_code,'sha256'),'hex');

  if v_kind='pickup' then
    update public.marketplace_orders set pickup_code_hash=v_hash,updated_at=now()
    where id=p_order_id;
  else
    update public.marketplace_orders set delivery_code_hash=v_hash,updated_at=now()
    where id=p_order_id;
  end if;

  return jsonb_build_object('kind',v_kind,'code',v_code,'order_id',p_order_id);
end;
$$;

create or replace function public.marketplace_verify_order_code(
  p_order_id uuid,
  p_kind text,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_kind text:=lower(trim(coalesce(p_kind,'')));
  v_hash text:=encode(extensions.digest(trim(coalesce(p_code,'')),'sha256'),'hex');
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  select * into v_order from public.marketplace_orders where id=p_order_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if v_order.assigned_driver_id is distinct from v_uid then
    raise exception 'Solo el repartidor asignado puede validar el código';
  end if;

  if v_kind='pickup' then
    if v_order.pickup_code_hash is null or v_order.pickup_code_hash<>v_hash then
      raise exception 'Código de retiro incorrecto';
    end if;
    update public.marketplace_orders
    set pickup_verified_at=now(),status='picked_up',updated_at=now()
    where id=p_order_id;
  elsif v_kind='delivery' then
    if v_order.delivery_code_hash is null or v_order.delivery_code_hash<>v_hash then
      raise exception 'Código de entrega incorrecto';
    end if;
    update public.marketplace_orders
    set delivery_verified_at=now(),status='delivered',completed_at=coalesce(completed_at,now()),updated_at=now()
    where id=p_order_id;
  else
    raise exception 'Tipo de código no válido';
  end if;

  return jsonb_build_object('ok',true,'kind',v_kind,'order_id',p_order_id);
end;
$$;

create or replace function public.marketplace_submit_review(
  p_order_id uuid,
  p_rating integer,
  p_comment text default null,
  p_product_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_row public.marketplace_reviews%rowtype;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if p_rating<1 or p_rating>5 then raise exception 'Calificación no válida'; end if;

  select * into v_order
  from public.marketplace_orders
  where id=p_order_id and customer_id=v_uid and status='delivered';
  if not found then raise exception 'Solo puedes calificar pedidos entregados'; end if;

  if p_product_id is not null and not exists(
    select 1 from public.marketplace_order_items oi
    where oi.order_id=p_order_id and oi.product_id=p_product_id
  ) then
    raise exception 'Producto no pertenece al pedido';
  end if;

  insert into public.marketplace_reviews(
    user_id,order_id,merchant_id,product_id,rating,comment
  )
  values(
    v_uid,p_order_id,v_order.merchant_id,p_product_id,p_rating,
    nullif(trim(coalesce(p_comment,'')),'')
  )
  on conflict(
    order_id,merchant_id,
    (coalesce(product_id,'00000000-0000-0000-0000-000000000000'::uuid))
  )
  do update set
    rating=excluded.rating,comment=excluded.comment,active=true,updated_at=now()
  returning * into v_row;

  update public.marketplace_merchants m
  set rating=coalesce((
    select round(avg(r.rating)::numeric,2)
    from public.marketplace_reviews r
    where r.merchant_id=m.id and r.product_id is null and r.active=true
  ),m.rating),
  updated_at=now()
  where m.id=v_order.merchant_id;

  if p_product_id is not null then
    update public.marketplace_products p
    set rating=coalesce((
          select round(avg(r.rating)::numeric,2)
          from public.marketplace_reviews r
          where r.product_id=p.id and r.active=true
        ),0),
        review_count=(
          select count(*)::int from public.marketplace_reviews r
          where r.product_id=p.id and r.active=true
        ),
        updated_at=now()
    where p.id=p_product_id;
  end if;

  return to_jsonb(v_row);
end;
$$;

create or replace function public.marketplace_order_status_notification()
returns trigger
language plpgsql
set search_path='public'
as $$
declare
  v_title text;
  v_body text;
begin
  if new.status is not distinct from old.status then return new; end if;

  v_title:=case new.status
    when 'confirmed' then 'Pedido confirmado'
    when 'preparing' then 'Tu pedido se está preparando'
    when 'ready' then 'Tu pedido está listo'
    when 'searching_driver' then 'Buscando repartidor'
    when 'driver_assigned' then 'Repartidor asignado'
    when 'picked_up' then 'Tu pedido salió del local'
    when 'delivering' then 'Tu pedido está en camino'
    when 'delivered' then 'Pedido entregado'
    when 'cancelled' then 'Pedido cancelado'
    else 'Actualización de tu pedido'
  end;

  v_body:=case new.status
    when 'confirmed' then 'El comercio confirmó tu pedido.'
    when 'preparing' then 'El local está preparando tus productos.'
    when 'ready' then 'El pedido está listo para retiro.'
    when 'searching_driver' then 'Estamos buscando un repartidor disponible.'
    when 'driver_assigned' then 'Ya asignamos un repartidor.'
    when 'picked_up' then 'El repartidor retiró tu pedido.'
    when 'delivering' then 'Tu pedido va hacia tu dirección.'
    when 'delivered' then 'La entrega fue completada.'
    when 'cancelled' then 'El pedido fue cancelado.'
    else 'Tu pedido cambió de estado.'
  end;

  insert into public.notifications(user_id,title,body,type,metadata)
  values(
    new.customer_id,v_title,v_body,'marketplace_order',
    jsonb_build_object(
      'marketplace_order_id',new.id,
      'merchant_id',new.merchant_id,
      'status',new.status,
      'zone_id',new.zone_id,
      'country_code',new.country_code
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_marketplace_order_status_notification
  on public.marketplace_orders;
create trigger trg_marketplace_order_status_notification
after update of status on public.marketplace_orders
for each row execute function public.marketplace_order_status_notification();

do $$
declare f regprocedure;
begin
  foreach f in array array[
    'public.marketplace_product_effective_price(uuid)'::regprocedure,
    'public.marketplace_available_zones(text)'::regprocedure,
    'public.marketplace_saved_addresses_v2(uuid)'::regprocedure,
    'public.marketplace_add_saved_address_v2(text,text,numeric,numeric,uuid,text,boolean)'::regprocedure,
    'public.marketplace_home_v2(text,uuid,numeric,numeric,uuid)'::regprocedure,
    'public.marketplace_category_feed_v2(text,text,uuid,text,boolean,boolean,integer)'::regprocedure,
    'public.marketplace_merchant_detail_v2(uuid,text)'::regprocedure,
    'public.marketplace_product_detail_v2(uuid,text)'::regprocedure,
    'public.marketplace_validate_coupon(text,uuid,numeric,text)'::regprocedure,
    'public.marketplace_quote_order_v2(uuid,jsonb,numeric,numeric,boolean,text,numeric,text)'::regprocedure,
    'public.marketplace_create_order_v2(uuid,jsonb,numeric,numeric,boolean,text,text,numeric,numeric,uuid,text,text,text,text,numeric,uuid,text)'::regprocedure,
    'public.marketplace_delivery_notifications(integer)'::regprocedure,
    'public.marketplace_mark_notification_read(uuid)'::regprocedure,
    'public.marketplace_upsert_billing_profile(text,text,text,text,text)'::regprocedure,
    'public.marketplace_issue_order_code(uuid,text)'::regprocedure,
    'public.marketplace_verify_order_code(uuid,text,text)'::regprocedure,
    'public.marketplace_submit_review(uuid,integer,text,uuid)'::regprocedure
  ]
  loop
    execute format('revoke execute on function %s from public,anon',f);
    execute format('grant execute on function %s to authenticated',f);
  end loop;
end $$;

revoke execute on function public.marketplace_product_effective_price(uuid) from authenticated;
