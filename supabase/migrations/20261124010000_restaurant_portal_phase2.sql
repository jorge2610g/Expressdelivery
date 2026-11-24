-- Portal de restaurantes, fases 2 y 3: perfil editable, horarios, categorías,
-- reportes y reseñas. Todas las funciones validan que quien llama sea personal activo
-- del restaurante y que su cuenta pertenezca al canal pedido (igual que las existentes).

create or replace function public.marketplace_portal_role(p_merchant_id uuid, p_channel text)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare v_role text;
begin
  if p_channel not in ('preview','production') then
    raise exception 'No autorizado';
  end if;
  select mu.role into v_role
  from public.marketplace_merchant_users mu
  join public.account_runtime_bindings b
    on b.user_id = mu.user_id and b.environment = p_channel
  join public.marketplace_merchants m on m.id = mu.merchant_id and m.active
  where mu.merchant_id = p_merchant_id and mu.user_id = auth.uid() and mu.active;
  if v_role is null then raise exception 'No autorizado'; end if;
  return v_role;
end $$;
revoke all on function public.marketplace_portal_role(uuid, text) from public, anon;
grant execute on function public.marketplace_portal_role(uuid, text) to authenticated;

-- Reseñas de clientes sobre pedidos entregados (una por pedido).
create table if not exists public.marketplace_order_reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.marketplace_orders(id) on delete cascade,
  merchant_id uuid not null references public.marketplace_merchants(id) on delete cascade,
  customer_id uuid not null,
  channel text not null check (channel in ('preview','production')),
  rating integer not null check (rating between 1 and 5),
  comment text check (comment is null or length(comment) <= 600),
  created_at timestamptz not null default now()
);
create index if not exists marketplace_order_reviews_merchant_idx
  on public.marketplace_order_reviews(merchant_id, created_at desc);
alter table public.marketplace_order_reviews enable row level security;
drop policy if exists marketplace_order_reviews_read_own on public.marketplace_order_reviews;
create policy marketplace_order_reviews_read_own on public.marketplace_order_reviews
  for select to authenticated using (customer_id = (select auth.uid()));

create or replace function public.marketplace_submit_order_review(
  p_order_id uuid, p_rating integer, p_comment text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare o public.marketplace_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  select * into o from public.marketplace_orders where id = p_order_id;
  if o.id is null or o.customer_id <> auth.uid() then
    raise exception 'Pedido no encontrado';
  end if;
  if o.status <> 'delivered' then
    raise exception 'Solo puedes calificar pedidos entregados';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Calificación no válida';
  end if;
  insert into public.marketplace_order_reviews(order_id, merchant_id, customer_id, channel, rating, comment)
  values (o.id, o.merchant_id, o.customer_id, o.channel, p_rating,
          nullif(left(trim(coalesce(p_comment, '')), 600), ''))
  on conflict (order_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.marketplace_submit_order_review(uuid, integer, text) from public, anon;
grant execute on function public.marketplace_submit_order_review(uuid, integer, text) to authenticated;

create or replace function public.marketplace_merchant_reviews(p_merchant_id uuid, p_channel text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  perform public.marketplace_portal_role(p_merchant_id, p_channel);
  return jsonb_build_object(
    'summary', (select jsonb_build_object(
        'count', count(*), 'average', coalesce(round(avg(rating)::numeric, 1), 0))
      from public.marketplace_order_reviews r
      where r.merchant_id = p_merchant_id and r.channel = p_channel),
    'reviews', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', r.id, 'rating', r.rating, 'comment', r.comment,
        'created_at', r.created_at, 'order_id', r.order_id) order by r.created_at desc), '[]'::jsonb)
      from (select * from public.marketplace_order_reviews
             where merchant_id = p_merchant_id and channel = p_channel
             order by created_at desc limit 200) r)
  );
end $$;
revoke all on function public.marketplace_merchant_reviews(uuid, text) from public, anon;
grant execute on function public.marketplace_merchant_reviews(uuid, text) to authenticated;

-- Perfil completo del restaurante para el portal.
create or replace function public.marketplace_merchant_profile(p_merchant_id uuid, p_channel text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare v_role text;
begin
  v_role := public.marketplace_portal_role(p_merchant_id, p_channel);
  return (select jsonb_build_object(
      'role', v_role,
      'id', m.id, 'name', m.name, 'description', m.description,
      'image_url', m.image_url, 'cover_image_url', m.cover_image_url,
      'address', m.address, 'category_key', m.category_key,
      'minimum_order', m.minimum_order, 'delivery_fee', m.delivery_fee,
      'eta_min_minutes', m.eta_min_minutes, 'eta_max_minutes', m.eta_max_minutes,
      'transfer_instructions', m.transfer_instructions,
      'business_hours', m.business_hours, 'open_override', m.open_override,
      'currency', z.currency_code, 'timezone', z.timezone,
      'rating', coalesce((select round(avg(r.rating)::numeric, 1)
                            from public.marketplace_order_reviews r
                           where r.merchant_id = m.id and r.channel = p_channel), m.rating),
      'review_count', (select count(*) from public.marketplace_order_reviews r
                        where r.merchant_id = m.id and r.channel = p_channel))
    from public.marketplace_merchants m
    left join public.service_zones z on z.id = m.zone_id
    where m.id = p_merchant_id);
end $$;
revoke all on function public.marketplace_merchant_profile(uuid, text) from public, anon;
grant execute on function public.marketplace_merchant_profile(uuid, text) to authenticated;

create or replace function public.marketplace_merchant_update_profile(
  p_merchant_id uuid, p_channel text,
  p_description text, p_image_url text, p_cover_image_url text, p_address text,
  p_minimum_order numeric, p_eta_min integer, p_eta_max integer,
  p_transfer_instructions text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_role text;
begin
  v_role := public.marketplace_portal_role(p_merchant_id, p_channel);
  if v_role not in ('owner', 'manager') then
    raise exception 'No tienes permisos para editar el perfil';
  end if;
  if p_minimum_order is not null and (p_minimum_order < 0 or p_minimum_order > 100000) then
    raise exception 'Pedido mínimo no válido';
  end if;
  if p_eta_min is not null and p_eta_max is not null
     and (p_eta_min < 1 or p_eta_max > 240 or p_eta_min > p_eta_max) then
    raise exception 'Tiempo estimado no válido';
  end if;
  if length(coalesce(p_description, '')) > 600 or length(coalesce(p_address, '')) > 300
     or length(coalesce(p_transfer_instructions, '')) > 800 then
    raise exception 'Algún texto es demasiado largo';
  end if;
  update public.marketplace_merchants m set
    description = nullif(trim(coalesce(p_description, '')), ''),
    image_url = nullif(trim(coalesce(p_image_url, '')), ''),
    cover_image_url = nullif(trim(coalesce(p_cover_image_url, '')), ''),
    address = nullif(trim(coalesce(p_address, '')), ''),
    minimum_order = coalesce(p_minimum_order, m.minimum_order),
    eta_min_minutes = coalesce(p_eta_min, m.eta_min_minutes),
    eta_max_minutes = coalesce(p_eta_max, m.eta_max_minutes),
    transfer_instructions = nullif(trim(coalesce(p_transfer_instructions, '')), ''),
    updated_at = now()
  where m.id = p_merchant_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.marketplace_merchant_update_profile(uuid, text, text, text, text, text, numeric, integer, integer, text) from public, anon;
grant execute on function public.marketplace_merchant_update_profile(uuid, text, text, text, text, text, numeric, integer, integer, text) to authenticated;

-- Horarios: {"mon":[{"from":"09:00","to":"22:00"}], ..., "sun":[]}; día ausente o vacío = cerrado.
create or replace function public.marketplace_merchant_update_hours(
  p_merchant_id uuid, p_channel text, p_hours jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_role text; v_day text; v_range jsonb; v_clean jsonb := '{}'::jsonb; v_list jsonb;
begin
  v_role := public.marketplace_portal_role(p_merchant_id, p_channel);
  if v_role not in ('owner', 'manager') then
    raise exception 'No tienes permisos para editar los horarios';
  end if;
  if p_hours is null or jsonb_typeof(p_hours) <> 'object' then
    raise exception 'Horario no válido';
  end if;
  foreach v_day in array array['mon','tue','wed','thu','fri','sat','sun'] loop
    v_list := coalesce(p_hours -> v_day, '[]'::jsonb);
    if jsonb_typeof(v_list) <> 'array' or jsonb_array_length(v_list) > 4 then
      raise exception 'Horario no válido';
    end if;
    for v_range in select * from jsonb_array_elements(v_list) loop
      if coalesce(v_range ->> 'from', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
         or coalesce(v_range ->> 'to', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'Hora no válida (usa HH:MM)';
      end if;
    end loop;
    v_clean := v_clean || jsonb_build_object(v_day, v_list);
  end loop;
  update public.marketplace_merchants set business_hours = v_clean, updated_at = now()
   where id = p_merchant_id;
  return jsonb_build_object('ok', true, 'business_hours', v_clean);
end $$;
revoke all on function public.marketplace_merchant_update_hours(uuid, text, jsonb) from public, anon;
grant execute on function public.marketplace_merchant_update_hours(uuid, text, jsonb) to authenticated;

-- Categorías: lista completa con cantidad de productos, orden y activación.
create or replace function public.marketplace_merchant_categories_all(p_merchant_id uuid, p_channel text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  perform public.marketplace_portal_role(p_merchant_id, p_channel);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name, 'active', c.active, 'sort_order', c.sort_order,
      'product_count', (select count(*) from public.marketplace_products p
                         where p.category_id = c.id)) order by c.sort_order, c.name), '[]'::jsonb)
    from public.marketplace_merchant_product_categories c
    where c.merchant_id = p_merchant_id);
end $$;
revoke all on function public.marketplace_merchant_categories_all(uuid, text) from public, anon;
grant execute on function public.marketplace_merchant_categories_all(uuid, text) to authenticated;

create or replace function public.marketplace_merchant_set_categories_order(
  p_merchant_id uuid, p_channel text, p_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_role text; i integer;
begin
  v_role := public.marketplace_portal_role(p_merchant_id, p_channel);
  if v_role not in ('owner', 'manager') then
    raise exception 'No tienes permisos para categorías';
  end if;
  for i in 1 .. coalesce(array_length(p_ids, 1), 0) loop
    update public.marketplace_merchant_product_categories
       set sort_order = i, updated_at = now()
     where id = p_ids[i] and merchant_id = p_merchant_id;
  end loop;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.marketplace_merchant_set_categories_order(uuid, text, uuid[]) from public, anon;
grant execute on function public.marketplace_merchant_set_categories_order(uuid, text, uuid[]) to authenticated;

create or replace function public.marketplace_merchant_set_category_active(
  p_merchant_id uuid, p_channel text, p_category_id uuid, p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_role text;
begin
  v_role := public.marketplace_portal_role(p_merchant_id, p_channel);
  if v_role not in ('owner', 'manager') then
    raise exception 'No tienes permisos para categorías';
  end if;
  update public.marketplace_merchant_product_categories
     set active = coalesce(p_active, true), updated_at = now()
   where id = p_category_id and merchant_id = p_merchant_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.marketplace_merchant_set_category_active(uuid, text, uuid, boolean) from public, anon;
grant execute on function public.marketplace_merchant_set_category_active(uuid, text, uuid, boolean) to authenticated;

-- Reportes del periodo (fechas en la zona horaria del restaurante).
create or replace function public.marketplace_merchant_report(
  p_merchant_id uuid, p_channel text, p_from date, p_to date, p_group text default 'day')
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare v_tz text; v_from timestamptz; v_to timestamptz; v_unit text;
begin
  perform public.marketplace_portal_role(p_merchant_id, p_channel);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    raise exception 'Periodo no válido';
  end if;
  v_unit := case when p_group in ('day', 'week', 'month') then p_group else 'day' end;
  select coalesce(z.timezone, 'America/La_Paz') into v_tz
    from public.marketplace_merchants m left join public.service_zones z on z.id = m.zone_id
   where m.id = p_merchant_id;
  v_tz := coalesce(v_tz, 'America/La_Paz');
  v_from := (p_from::timestamp) at time zone v_tz;
  v_to := ((p_to + 1)::timestamp) at time zone v_tz;
  return (
    with o as (
      select * from public.marketplace_orders
       where merchant_id = p_merchant_id and channel = p_channel
         and created_at >= v_from and created_at < v_to),
    d as (select * from o where status = 'delivered')
    select jsonb_build_object(
      'totals', jsonb_build_object(
        'orders', (select count(*) from o),
        'completed', (select count(*) from d),
        'cancelled', (select count(*) from o where status = 'cancelled'),
        'sales', (select coalesce(sum(merchant_products_amount), 0) from d),
        'tips', (select coalesce(sum(tip_amount), 0) from d),
        'items', (select coalesce(sum(i.quantity), 0) from public.marketplace_order_items i
                   where i.order_id in (select id from d)),
        'average_ticket', (select coalesce(round(avg(merchant_products_amount), 2), 0) from d),
        'completion_rate', (select case when count(*) = 0 then 0
                              else round(100.0 * count(*) filter (where status = 'delivered') / count(*), 1) end from o)),
      'series', (select coalesce(jsonb_agg(jsonb_build_object(
          'period', s.period, 'orders', s.orders, 'sales', s.sales) order by s.period), '[]'::jsonb)
        from (select to_char(date_trunc(v_unit, created_at at time zone v_tz), 'YYYY-MM-DD') as period,
                     count(*) as orders,
                     coalesce(sum(merchant_products_amount) filter (where status = 'delivered'), 0) as sales
                from o group by 1) s),
      'top_products', (select coalesce(jsonb_agg(jsonb_build_object(
          'name', t.name, 'quantity', t.quantity, 'total', t.total) order by t.quantity desc), '[]'::jsonb)
        from (select i.product_name as name, sum(i.quantity) as quantity, sum(i.line_total) as total
                from public.marketplace_order_items i
               where i.order_id in (select id from d)
               group by i.product_name order by sum(i.quantity) desc limit 10) t),
      'by_hour', (select coalesce(jsonb_agg(jsonb_build_object(
          'hour', h.hour, 'orders', h.orders) order by h.hour), '[]'::jsonb)
        from (select extract(hour from created_at at time zone v_tz)::int as hour, count(*) as orders
                from o group by 1) h),
      'orders', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', x.id, 'created_at', x.created_at, 'status', x.status,
          'total_amount', x.total_amount, 'products_amount', x.merchant_products_amount,
          'payment_method', x.payment_method) order by x.created_at desc), '[]'::jsonb)
        from (select * from o order by created_at desc limit 500) x)
    ));
end $$;
revoke all on function public.marketplace_merchant_report(uuid, text, date, date, text) from public, anon;
grant execute on function public.marketplace_merchant_report(uuid, text, date, date, text) to authenticated;
