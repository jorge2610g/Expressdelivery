-- Tarifas independientes por restaurante:
--  - pedidos del menú (clientes por la app): tarifa de envío de Express por zona (como hasta ahora)
--    o tarifa fija propia del restaurante;
--  - «Solicitar repartidor»: tarifa de Express por distancia o tarifa fija propia.
alter table public.marketplace_merchants
  add column if not exists menu_fee_pricing text not null default 'zone'
    check (menu_fee_pricing in ('zone', 'flat')),
  add column if not exists menu_flat_fee numeric
    check (menu_flat_fee is null or menu_flat_fee >= 0);

do $patch$
declare d text; patched text;
begin
  d := pg_get_functiondef('public.marketplace_compute_quote'::regproc);
  if position('menu_fee_pricing' in d) > 0 then return; end if;
  patched := regexp_replace(
    d,
    '(v_customer_fee:=greatest\(\s*v_cfg\.customer_min_fee,\s*v_cfg\.customer_base_fee\s*\+\s*greatest\(coalesce\(p_distance_km,0\),0\)\*v_cfg\.customer_per_km\s*\);)',
    E'\\1\n  -- Tarifa propia del restaurante (la define el administrador).\n  if v_merchant.menu_fee_pricing = ''flat'' and v_merchant.menu_flat_fee is not null then\n    v_customer_fee := v_merchant.menu_flat_fee;\n  end if;');
  if patched = d then raise exception 'No se pudo aplicar la tarifa propia del restaurante'; end if;
  execute patched;
end $patch$;

create or replace function public.admin_marketplace_set_service_settings(
  p_merchant_id uuid, p_mode text,
  p_courier_pricing text, p_courier_flat_fare numeric,
  p_menu_pricing text, p_menu_flat_fee numeric)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_row public.marketplace_merchants%rowtype;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_mode not in ('menu', 'courier', 'both') then raise exception 'Modo no válido'; end if;
  if p_courier_pricing not in ('zone', 'flat') or p_menu_pricing not in ('zone', 'flat') then
    raise exception 'Tipo de tarifa no válido';
  end if;
  if p_courier_pricing = 'flat' and coalesce(p_courier_flat_fare, 0) <= 0 then
    raise exception 'Escribe la tarifa fija de Solicitar repartidor';
  end if;
  if p_menu_pricing = 'flat' and (p_menu_flat_fee is null or p_menu_flat_fee < 0) then
    raise exception 'Escribe la tarifa fija de envío de los pedidos del menú';
  end if;
  update public.marketplace_merchants set
      courier_mode = p_mode,
      courier_pricing = p_courier_pricing,
      courier_flat_fare = case when p_courier_pricing = 'flat' then p_courier_flat_fare end,
      menu_fee_pricing = p_menu_pricing,
      menu_flat_fee = case when p_menu_pricing = 'flat' then p_menu_flat_fee end,
      -- El costo de envío que ven los clientes en la lista sigue a la tarifa propia.
      delivery_fee = case when p_menu_pricing = 'flat' then p_menu_flat_fee else delivery_fee end,
      production_visible = case when p_mode = 'courier' then false else production_visible end,
      preview_visible = case when p_mode = 'courier' then false else preview_visible end,
      updated_at = now()
   where id = p_merchant_id
   returning * into v_row;
  if v_row.id is null then raise exception 'Comercio no encontrado'; end if;
  return jsonb_build_object('ok', true, 'courier_mode', v_row.courier_mode,
    'courier_pricing', v_row.courier_pricing, 'courier_flat_fare', v_row.courier_flat_fare,
    'menu_fee_pricing', v_row.menu_fee_pricing, 'menu_flat_fee', v_row.menu_flat_fee);
end $$;
revoke all on function public.admin_marketplace_set_service_settings(uuid, text, text, numeric, text, numeric) from public, anon;
grant execute on function public.admin_marketplace_set_service_settings(uuid, text, text, numeric, text, numeric) to authenticated;
