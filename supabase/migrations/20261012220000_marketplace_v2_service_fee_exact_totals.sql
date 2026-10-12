begin;
CREATE OR REPLACE FUNCTION public.marketplace_quote_order_v2(p_merchant_id uuid, p_items jsonb, p_distance_km numeric DEFAULT 0, p_tip numeric DEFAULT 0, p_priority boolean DEFAULT false, p_coupon_code text DEFAULT NULL::text, p_donation numeric DEFAULT 0, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    +coalesce((v_base->>'customer_service_fee')::numeric,0)
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
$function$;
commit;
