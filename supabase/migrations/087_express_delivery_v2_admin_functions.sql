-- Express Delivery V2 admin APIs.
-- Admin-only RPCs for Home sections, coupons, menu sections, modifiers and promotions.

create or replace function public.admin_marketplace_v2_state(
  p_zone_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $$
declare
  v_zones jsonb;
  v_sections jsonb;
  v_coupons jsonb;
  v_merchants jsonb;
  v_menu_sections jsonb;
  v_products jsonb;
  v_groups jsonb;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.country,x.city),'[]'::jsonb)
  into v_zones
  from (
    select z.id,z.zone_key,z.name,z.city,z.country,z.country_code,z.currency_code,
           mz.preview_enabled,mz.production_enabled
    from public.service_zones z
    join public.marketplace_zone_settings mz on mz.zone_id=z.id
    where z.active=true
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.title),'[]'::jsonb)
  into v_sections
  from (
    select hs.*
    from public.marketplace_home_sections hs
    where p_zone_id is null or hs.zone_id=p_zone_id
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_coupons
  from (
    select c.*
    from public.marketplace_coupons c
    where p_zone_id is null or c.zone_id=p_zone_id or c.zone_id is null
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]'::jsonb)
  into v_merchants
  from (
    select m.*,z.zone_key,z.country_code,z.currency_code
    from public.marketplace_merchants m
    join public.service_zones z on z.id=m.zone_id
    where p_zone_id is null or m.zone_id=p_zone_id
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.merchant_id,x.sort_order,x.name),'[]'::jsonb)
  into v_menu_sections
  from (
    select s.*
    from public.marketplace_menu_sections s
    join public.marketplace_merchants m on m.id=s.merchant_id
    where p_zone_id is null or m.zone_id=p_zone_id
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.merchant_id,x.sort_order,x.name),'[]'::jsonb)
  into v_products
  from (
    select p.*,m.zone_id,m.name merchant_name
    from public.marketplace_products p
    join public.marketplace_merchants m on m.id=p.merchant_id
    where p_zone_id is null or m.zone_id=p_zone_id
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.product_id,x.sort_order,x.name),'[]'::jsonb)
  into v_groups
  from (
    select g.*,
      coalesce((
        select jsonb_agg(to_jsonb(o) order by o.sort_order,o.name)
        from public.marketplace_product_modifiers o
        where o.group_id=g.id
      ),'[]'::jsonb) options
    from public.marketplace_product_modifier_groups g
    join public.marketplace_products p on p.id=g.product_id
    join public.marketplace_merchants m on m.id=p.merchant_id
    where p_zone_id is null or m.zone_id=p_zone_id
  ) x;

  return jsonb_build_object(
    'zones',v_zones,
    'home_sections',v_sections,
    'coupons',v_coupons,
    'merchants',v_merchants,
    'menu_sections',v_menu_sections,
    'products',v_products,
    'modifier_groups',v_groups
  );
end;
$$;

create or replace function public.admin_marketplace_upsert_home_section(
  p_id uuid,
  p_zone_id uuid,
  p_country_code text,
  p_section_key text,
  p_title text,
  p_subtitle text,
  p_section_type text,
  p_source_rule text,
  p_config jsonb,
  p_sort_order integer,
  p_active boolean,
  p_preview_visible boolean,
  p_production_visible boolean,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_row public.marketplace_home_sections%rowtype;
  v_country text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_section_type not in ('merchants','products','promotions') then raise exception 'Tipo no válido'; end if;
  if p_source_rule not in ('popular','trusted','preferences','deals','lowest_price','sponsored','manual') then
    raise exception 'Regla no válida';
  end if;

  if p_zone_id is not null then
    select z.country_code into v_country
    from public.service_zones z
    where z.id=p_zone_id and z.active=true;
    if v_country is null then raise exception 'Zona no válida'; end if;
    if nullif(upper(trim(coalesce(p_country_code,''))),'') is not null
       and upper(trim(p_country_code))<>v_country then
      raise exception 'El país no coincide con la zona';
    end if;
  else
    v_country:=nullif(upper(trim(coalesce(p_country_code,''))),'');
    if v_country is null then
      raise exception 'Selecciona un país cuando no uses una zona específica';
    end if;
    if not exists(
      select 1 from public.service_zones z
      where z.active=true and z.country_code=v_country
    ) then
      raise exception 'País no válido';
    end if;
  end if;

  if p_id is null then
    insert into public.marketplace_home_sections(
      zone_id,country_code,section_key,title,subtitle,section_type,source_rule,config,
      sort_order,active,preview_visible,production_visible,starts_at,ends_at
    )
    values(
      p_zone_id,v_country,trim(p_section_key),
      trim(p_title),nullif(trim(coalesce(p_subtitle,'')),''),
      p_section_type,p_source_rule,coalesce(p_config,'{}'::jsonb),
      coalesce(p_sort_order,100),coalesce(p_active,true),
      coalesce(p_preview_visible,true),coalesce(p_production_visible,false),
      p_starts_at,p_ends_at
    )
    returning * into v_row;
  else
    update public.marketplace_home_sections
    set zone_id=p_zone_id,
        country_code=nullif(upper(trim(coalesce(p_country_code,''))),''),
        section_key=trim(p_section_key),title=trim(p_title),
        subtitle=nullif(trim(coalesce(p_subtitle,'')),''),
        section_type=p_section_type,source_rule=p_source_rule,
        config=coalesce(p_config,'{}'::jsonb),sort_order=coalesce(p_sort_order,100),
        active=coalesce(p_active,true),preview_visible=coalesce(p_preview_visible,true),
        production_visible=coalesce(p_production_visible,false),
        starts_at=p_starts_at,ends_at=p_ends_at,updated_at=now()
    where id=p_id
    returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'Sección no encontrada'; end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.admin_marketplace_upsert_coupon(
  p_id uuid,
  p_zone_id uuid,
  p_country_code text,
  p_code text,
  p_title text,
  p_description text,
  p_discount_type text,
  p_discount_value numeric,
  p_min_order numeric,
  p_max_discount numeric,
  p_funded_by text,
  p_usage_limit integer,
  p_per_user_limit integer,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_active boolean,
  p_preview_visible boolean,
  p_production_visible boolean
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_row public.marketplace_coupons%rowtype;
  v_country text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_discount_type not in ('percent','fixed') then raise exception 'Tipo de descuento no válido'; end if;
  if p_funded_by not in ('express','merchant') then raise exception 'Financiamiento no válido'; end if;

  if p_zone_id is not null then
    select z.country_code into v_country
    from public.service_zones z
    where z.id=p_zone_id and z.active=true;
    if v_country is null then raise exception 'Zona no válida'; end if;
    if nullif(upper(trim(coalesce(p_country_code,''))),'') is not null
       and upper(trim(p_country_code))<>v_country then
      raise exception 'El país no coincide con la zona';
    end if;
  else
    v_country:=nullif(upper(trim(coalesce(p_country_code,''))),'');
    if v_country is null then
      raise exception 'Selecciona un país cuando el cupón aplique a todas sus zonas';
    end if;
    if not exists(
      select 1 from public.service_zones z
      where z.active=true and z.country_code=v_country
    ) then
      raise exception 'País no válido';
    end if;
  end if;

  if p_id is null then
    insert into public.marketplace_coupons(
      zone_id,country_code,code,title,description,discount_type,discount_value,
      min_order,max_discount,funded_by,usage_limit,per_user_limit,starts_at,ends_at,
      active,preview_visible,production_visible
    )
    values(
      p_zone_id,v_country,upper(trim(p_code)),
      trim(p_title),nullif(trim(coalesce(p_description,'')),''),
      p_discount_type,greatest(coalesce(p_discount_value,0),0.01),
      greatest(coalesce(p_min_order,0),0),p_max_discount,p_funded_by,p_usage_limit,
      greatest(coalesce(p_per_user_limit,1),1),p_starts_at,p_ends_at,
      coalesce(p_active,true),coalesce(p_preview_visible,true),coalesce(p_production_visible,false)
    )
    returning * into v_row;
  else
    update public.marketplace_coupons
    set zone_id=p_zone_id,country_code=nullif(upper(trim(coalesce(p_country_code,''))),''),
        code=upper(trim(p_code)),title=trim(p_title),
        description=nullif(trim(coalesce(p_description,'')),''),
        discount_type=p_discount_type,discount_value=greatest(coalesce(p_discount_value,0),0.01),
        min_order=greatest(coalesce(p_min_order,0),0),max_discount=p_max_discount,
        funded_by=p_funded_by,usage_limit=p_usage_limit,
        per_user_limit=greatest(coalesce(p_per_user_limit,1),1),
        starts_at=p_starts_at,ends_at=p_ends_at,active=coalesce(p_active,true),
        preview_visible=coalesce(p_preview_visible,true),
        production_visible=coalesce(p_production_visible,false),updated_at=now()
    where id=p_id
    returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'Cupón no encontrado'; end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.admin_marketplace_upsert_menu_section(
  p_id uuid,
  p_merchant_id uuid,
  p_section_key text,
  p_name text,
  p_subtitle text,
  p_sort_order integer,
  p_active boolean,
  p_preview_visible boolean,
  p_production_visible boolean
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare v_row public.marketplace_menu_sections%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_id is null then
    insert into public.marketplace_menu_sections(
      merchant_id,section_key,name,subtitle,sort_order,active,preview_visible,production_visible
    )
    values(
      p_merchant_id,trim(p_section_key),trim(p_name),
      nullif(trim(coalesce(p_subtitle,'')),''),
      coalesce(p_sort_order,100),coalesce(p_active,true),
      coalesce(p_preview_visible,true),coalesce(p_production_visible,false)
    )
    returning * into v_row;
  else
    update public.marketplace_menu_sections
    set merchant_id=p_merchant_id,section_key=trim(p_section_key),name=trim(p_name),
        subtitle=nullif(trim(coalesce(p_subtitle,'')),''),
        sort_order=coalesce(p_sort_order,100),active=coalesce(p_active,true),
        preview_visible=coalesce(p_preview_visible,true),
        production_visible=coalesce(p_production_visible,false),updated_at=now()
    where id=p_id
    returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'Sección no encontrada'; end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.admin_marketplace_upsert_modifier_group(
  p_id uuid,
  p_product_id uuid,
  p_name text,
  p_description text,
  p_min_select integer,
  p_max_select integer,
  p_required boolean,
  p_sort_order integer,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare v_row public.marketplace_product_modifier_groups%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if coalesce(p_min_select,0)<0 or coalesce(p_max_select,1)<greatest(coalesce(p_min_select,0),0) then
    raise exception 'Límites de selección no válidos';
  end if;
  if p_id is null then
    insert into public.marketplace_product_modifier_groups(
      product_id,name,description,min_select,max_select,required,sort_order,active
    )
    values(
      p_product_id,trim(p_name),nullif(trim(coalesce(p_description,'')),''),
      greatest(coalesce(p_min_select,0),0),greatest(coalesce(p_max_select,1),1),
      coalesce(p_required,false),coalesce(p_sort_order,100),coalesce(p_active,true)
    )
    returning * into v_row;
  else
    update public.marketplace_product_modifier_groups
    set product_id=p_product_id,name=trim(p_name),
        description=nullif(trim(coalesce(p_description,'')),''),
        min_select=greatest(coalesce(p_min_select,0),0),
        max_select=greatest(coalesce(p_max_select,1),1),
        required=coalesce(p_required,false),sort_order=coalesce(p_sort_order,100),
        active=coalesce(p_active,true),updated_at=now()
    where id=p_id
    returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'Grupo no encontrado'; end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.admin_marketplace_upsert_modifier(
  p_id uuid,
  p_group_id uuid,
  p_name text,
  p_price_delta numeric,
  p_sort_order integer,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare v_row public.marketplace_product_modifiers%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_id is null then
    insert into public.marketplace_product_modifiers(
      group_id,name,price_delta,sort_order,active
    )
    values(
      p_group_id,trim(p_name),coalesce(p_price_delta,0),
      coalesce(p_sort_order,100),coalesce(p_active,true)
    )
    returning * into v_row;
  else
    update public.marketplace_product_modifiers
    set group_id=p_group_id,name=trim(p_name),price_delta=coalesce(p_price_delta,0),
        sort_order=coalesce(p_sort_order,100),active=coalesce(p_active,true),updated_at=now()
    where id=p_id
    returning * into v_row;
  end if;
  if v_row.id is null then raise exception 'Opción no encontrada'; end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.admin_marketplace_update_product_v2(
  p_product_id uuid,
  p_menu_section_id uuid,
  p_compare_at_price numeric,
  p_promo_price numeric,
  p_promo_label text,
  p_promo_start_at timestamptz,
  p_promo_end_at timestamptz,
  p_is_sponsored boolean,
  p_is_featured boolean,
  p_tags text[]
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare v_row public.marketplace_products%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  if p_menu_section_id is not null and not exists(
    select 1
    from public.marketplace_menu_sections s
    join public.marketplace_products p on p.merchant_id=s.merchant_id
    where s.id=p_menu_section_id and p.id=p_product_id
  ) then
    raise exception 'La sección no pertenece al comercio del producto';
  end if;

  update public.marketplace_products
  set menu_section_id=p_menu_section_id,
      compare_at_price=p_compare_at_price,
      promo_price=p_promo_price,
      promo_label=nullif(trim(coalesce(p_promo_label,'')),''),
      promo_start_at=p_promo_start_at,promo_end_at=p_promo_end_at,
      is_sponsored=coalesce(p_is_sponsored,false),
      is_featured=coalesce(p_is_featured,false),
      tags=coalesce(p_tags,'{}'::text[]),updated_at=now()
  where id=p_product_id
  returning * into v_row;

  if v_row.id is null then raise exception 'Producto no encontrado'; end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.admin_marketplace_update_merchant_v2(
  p_merchant_id uuid,
  p_business_hours jsonb,
  p_open_override boolean,
  p_minimum_order numeric,
  p_is_sponsored boolean,
  p_tags text[]
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare v_row public.marketplace_merchants%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  update public.marketplace_merchants
  set business_hours=coalesce(p_business_hours,'{}'::jsonb),
      open_override=p_open_override,
      minimum_order=greatest(coalesce(p_minimum_order,0),0),
      is_sponsored=coalesce(p_is_sponsored,false),
      tags=coalesce(p_tags,'{}'::text[]),updated_at=now()
  where id=p_merchant_id
  returning * into v_row;

  if v_row.id is null then raise exception 'Comercio no encontrado'; end if;
  return to_jsonb(v_row);
end;
$$;

do $$
declare f regprocedure;
begin
  foreach f in array array[
    'public.admin_marketplace_v2_state(uuid)'::regprocedure,
    'public.admin_marketplace_upsert_home_section(uuid,uuid,text,text,text,text,text,text,jsonb,integer,boolean,boolean,boolean,timestamptz,timestamptz)'::regprocedure,
    'public.admin_marketplace_upsert_coupon(uuid,uuid,text,text,text,text,text,numeric,numeric,numeric,text,integer,integer,timestamptz,timestamptz,boolean,boolean,boolean)'::regprocedure,
    'public.admin_marketplace_upsert_menu_section(uuid,uuid,text,text,text,integer,boolean,boolean,boolean)'::regprocedure,
    'public.admin_marketplace_upsert_modifier_group(uuid,uuid,text,text,integer,integer,boolean,integer,boolean)'::regprocedure,
    'public.admin_marketplace_upsert_modifier(uuid,uuid,text,numeric,integer,boolean)'::regprocedure,
    'public.admin_marketplace_update_product_v2(uuid,uuid,numeric,numeric,text,timestamptz,timestamptz,boolean,boolean,text[])'::regprocedure,
    'public.admin_marketplace_update_merchant_v2(uuid,jsonb,boolean,numeric,boolean,text[])'::regprocedure
  ]
  loop
    execute format('revoke execute on function %s from public,anon',f);
    execute format('grant execute on function %s to authenticated',f);
  end loop;
end $$;
