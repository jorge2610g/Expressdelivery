-- Express Delivery V2 follow-up: country-scoped activity, personalization,
-- visible coupons and cross-sell administration.

create or replace function public.marketplace_my_orders_v2(
  p_country_code text default null,
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
  v_country text:=nullif(upper(trim(coalesce(p_country_code,''))),'');
  v_rows jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if v_country is null then
    select z.country_code into v_country
    from public.users u
    join public.service_zones z on z.id=u.last_zone_id
    where u.id=v_uid;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_rows
  from (
    select
      o.id,o.merchant_id,o.zone_id,o.country_code,o.status,
      o.payment_method,o.payment_status,o.currency_code,
      o.subtotal,o.product_discount,o.customer_delivery_fee,o.priority_fee,
      o.tip_amount,o.total_amount,o.is_priority,o.plus_subscription_applied,
      o.plus_free_delivery_applied,o.coupon_code,o.coupon_discount,
      o.donation_amount,o.dropoff_address,o.delivery_option,
      o.delivery_instructions,o.created_at,o.updated_at,o.completed_at,
      m.name merchant_name,m.image_url merchant_image_url,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',oi.id,'product_id',oi.product_id,'product_name',oi.product_name,
          'quantity',oi.quantity,'unit_price',oi.unit_price,'line_total',oi.line_total,
          'selected_modifiers',oi.selected_modifiers,'customer_note',oi.customer_note
        ) order by oi.id)
        from public.marketplace_order_items oi
        where oi.order_id=o.id
      ),'[]'::jsonb) items
    from public.marketplace_orders o
    join public.marketplace_merchants m on m.id=o.merchant_id
    where o.customer_id=v_uid
      and (v_country is null or o.country_code=v_country)
    order by o.created_at desc
    limit greatest(1,least(coalesce(p_limit,80),200))
  ) x;

  return v_rows;
end;
$$;

create or replace function public.marketplace_delivery_notifications_v2(
  p_country_code text default null,
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
  v_country text:=nullif(upper(trim(coalesce(p_country_code,''))),'');
  v_rows jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if v_country is null then
    select z.country_code into v_country
    from public.users u
    join public.service_zones z on z.id=u.last_zone_id
    where u.id=v_uid;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  into v_rows
  from (
    select n.id,n.title,n.body,n.type,n.is_read,n.created_at,n.metadata
    from public.notifications n
    where n.user_id=v_uid
      and (
        n.type='admin_announcement'
        or (
          n.type in ('marketplace_promo','marketplace_plus')
          and (
            v_country is null
            or nullif(n.metadata->>'country_code','') is null
            or upper(n.metadata->>'country_code')=v_country
          )
        )
        or (
          n.type='marketplace_order'
          and (
            v_country is null
            or upper(coalesce(n.metadata->>'country_code',''))=v_country
            or exists(
              select 1
              from public.marketplace_orders o
              where o.id=nullif(n.metadata->>'marketplace_order_id','')::uuid
                and o.customer_id=v_uid
                and o.country_code=v_country
            )
          )
        )
      )
    order by n.created_at desc
    limit greatest(1,least(coalesce(p_limit,80),200))
  ) x;

  return v_rows;
end;
$$;

create or replace function public.marketplace_delivery_extras_v2(
  p_zone_id uuid default null,
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
  v_zone_id uuid:=p_zone_id;
  v_country text;
  v_preview boolean:=lower(coalesce(p_channel,'production'))='preview';
  v_tags jsonb:='[]'::jsonb;
  v_coupons jsonb:='[]'::jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if v_zone_id is null then
    select u.last_zone_id into v_zone_id
    from public.users u where u.id=v_uid;
  end if;

  select z.country_code into v_country
  from public.service_zones z
  join public.marketplace_zone_settings mz on mz.zone_id=z.id
  where z.id=v_zone_id
    and case when v_preview then mz.preview_enabled else mz.production_enabled end;

  select coalesce(jsonb_agg(t.tag order by t.uses desc,t.tag),'[]'::jsonb)
  into v_tags
  from (
    select tag,count(*) uses
    from (
      select unnest(p.tags) tag
      from public.marketplace_orders o
      join public.marketplace_order_items oi on oi.order_id=o.id
      join public.marketplace_products p on p.id=oi.product_id
      where o.customer_id=v_uid
        and o.country_code=v_country
        and o.status='delivered'
        and cardinality(p.tags)>0
      union all
      select m.category_key
      from public.marketplace_orders o
      join public.marketplace_merchants m on m.id=o.merchant_id
      where o.customer_id=v_uid
        and o.country_code=v_country
        and o.status='delivered'
    ) history
    where nullif(trim(tag),'') is not null
    group by tag
    order by count(*) desc,tag
    limit 12
  ) t;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.ends_at nulls last,x.code),'[]'::jsonb)
  into v_coupons
  from (
    select
      c.id,c.code,c.title,c.description,c.discount_type,c.discount_value,
      c.min_order,c.max_discount,c.ends_at,c.funded_by
    from public.marketplace_coupons c
    where c.active=true
      and (c.starts_at is null or c.starts_at<=now())
      and (c.ends_at is null or c.ends_at>now())
      and (c.zone_id is null or c.zone_id=v_zone_id)
      and (c.country_code is null or c.country_code=v_country)
      and case when v_preview then c.preview_visible else c.production_visible end
      and (c.usage_limit is null or (
        select count(*) from public.marketplace_coupon_redemptions r
        where r.coupon_id=c.id
      )<c.usage_limit)
      and (
        select count(*) from public.marketplace_coupon_redemptions r
        where r.coupon_id=c.id and r.user_id=v_uid
      )<c.per_user_limit
  ) x;

  return jsonb_build_object(
    'zone_id',v_zone_id,
    'country_code',v_country,
    'preference_tags',v_tags,
    'available_coupons',v_coupons
  );
end;
$$;

create or replace function public.admin_marketplace_product_cross_sells(
  p_product_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public'
as $$
declare v_rows jsonb;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'product_id',c.product_id,
    'recommended_product_id',c.recommended_product_id,
    'sort_order',c.sort_order,
    'name',p.name
  ) order by c.sort_order,p.name),'[]'::jsonb)
  into v_rows
  from public.marketplace_product_cross_sells c
  join public.marketplace_products p on p.id=c.recommended_product_id
  where c.product_id=p_product_id;
  return v_rows;
end;
$$;

create or replace function public.admin_marketplace_set_cross_sells(
  p_product_id uuid,
  p_recommended_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_merchant uuid;
  v_id uuid;
  v_sort integer:=10;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select merchant_id into v_merchant
  from public.marketplace_products
  where id=p_product_id;
  if v_merchant is null then raise exception 'Producto no encontrado'; end if;

  delete from public.marketplace_product_cross_sells
  where product_id=p_product_id;

  foreach v_id in array coalesce(p_recommended_ids,'{}'::uuid[])
  loop
    if v_id=p_product_id then continue; end if;
    if not exists(
      select 1
      from public.marketplace_products p
      where p.id=v_id and p.merchant_id=v_merchant and p.active=true
    ) then
      raise exception 'Producto recomendado inválido';
    end if;

    insert into public.marketplace_product_cross_sells(
      product_id,recommended_product_id,sort_order
    )
    values(p_product_id,v_id,v_sort);
    v_sort:=v_sort+10;
  end loop;

  return public.admin_marketplace_product_cross_sells(p_product_id);
end;
$$;

do $$
declare f regprocedure;
begin
  foreach f in array array[
    'public.marketplace_my_orders_v2(text,integer)'::regprocedure,
    'public.marketplace_delivery_notifications_v2(text,integer)'::regprocedure,
    'public.marketplace_delivery_extras_v2(uuid,text)'::regprocedure
  ]
  loop
    execute format('revoke execute on function %s from public,anon',f);
    execute format('grant execute on function %s to authenticated',f);
  end loop;

  foreach f in array array[
    'public.admin_marketplace_product_cross_sells(uuid)'::regprocedure,
    'public.admin_marketplace_set_cross_sells(uuid,uuid[])'::regprocedure
  ]
  loop
    execute format('revoke execute on function %s from public,anon',f);
    execute format('grant execute on function %s to authenticated',f);
  end loop;
end $$;
