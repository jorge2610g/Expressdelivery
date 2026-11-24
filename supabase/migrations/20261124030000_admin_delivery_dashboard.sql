-- Resumen de Restaurantes y Delivery para el panel de administración: pedidos de restaurantes,
-- envíos (app y solicitados por restaurantes), envíos directos y liquidaciones, por periodo.
create or replace function public.admin_delivery_dashboard(
  p_zone_id uuid, p_channel text, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare v_context jsonb; v_tz text; v_from timestamptz; v_to timestamptz; v_currency text;
begin
  if auth.uid() is null or not public.is_admin()
     or p_channel not in ('preview', 'production')
     or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso al resumen de Delivery no autorizado';
  end if;
  v_context := public.admin_access_context();
  if v_context ->> 'zone_id' is not null and (v_context ->> 'zone_id')::uuid <> p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  if p_zone_id is null or p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    raise exception 'Periodo no válido';
  end if;
  select coalesce(z.timezone, 'America/La_Paz'), z.currency_code into v_tz, v_currency
    from public.service_zones z where z.id = p_zone_id;
  v_tz := coalesce(v_tz, 'America/La_Paz');
  v_from := (p_from::timestamp) at time zone v_tz;
  v_to := ((p_to + 1)::timestamp) at time zone v_tz;
  return (
    with o as (
      select * from public.marketplace_orders
       where zone_id = p_zone_id and channel = p_channel
         and created_at >= v_from and created_at < v_to),
    od as (select * from o where status = 'delivered'),
    s as (
      select * from public.ride_requests
       where zone_id = p_zone_id and channel = p_channel and service_mode = 'parcel'
         and created_at >= v_from and created_at < v_to),
    d as (
      select * from public.delivery_requests
       where channel = p_channel
         and public.service_zone_id_for_point(pickup_latitude, pickup_longitude) = p_zone_id
         and created_at >= v_from and created_at < v_to),
    c as (
      select * from public.marketplace_weekly_cuts
       where zone_id = p_zone_id and channel = p_channel)
    select jsonb_build_object(
      'currency', v_currency,
      'orders', jsonb_build_object(
        'total', (select count(*) from o),
        'delivered', (select count(*) from od),
        'cancelled', (select count(*) from o where status = 'cancelled'),
        'active', (select count(*) from o where status not in ('delivered', 'cancelled')),
        'sales', (select coalesce(sum(merchant_products_amount), 0) from od),
        'delivery_fees', (select coalesce(sum(customer_delivery_fee), 0) from od),
        'average_ticket', (select coalesce(round(avg(merchant_products_amount), 2), 0) from od),
        'series', (select coalesce(jsonb_agg(jsonb_build_object(
            'day', x.day, 'orders', x.orders, 'sales', x.sales) order by x.day), '[]'::jsonb)
          from (select to_char(created_at at time zone v_tz, 'YYYY-MM-DD') as day,
                       count(*) as orders,
                       coalesce(sum(merchant_products_amount) filter (where status = 'delivered'), 0) as sales
                  from o group by 1) x),
        'top_merchants', (select coalesce(jsonb_agg(jsonb_build_object(
            'name', t.name, 'orders', t.orders, 'sales', t.sales) order by t.orders desc), '[]'::jsonb)
          from (select m.name as name, count(*) as orders,
                       coalesce(sum(o.merchant_products_amount) filter (where o.status = 'delivered'), 0) as sales
                  from o join public.marketplace_merchants m on m.id = o.merchant_id
                 group by m.name order by count(*) desc limit 8) t)),
      'shipments', jsonb_build_object(
        'total', (select count(*) from s),
        'with_driver', (select count(*) from s where status = 'driver_selected'),
        'cancelled', (select count(*) from s where status = 'cancelled'),
        'searching', (select count(*) from s where status in ('searching', 'offers_received')),
        'from_restaurants', (select count(*) from s where merchant_courier),
        'fares', (select coalesce(sum(proposed_fare), 0) from s where status = 'driver_selected'),
        'series', (select coalesce(jsonb_agg(jsonb_build_object(
            'day', x.day, 'shipments', x.shipments) order by x.day), '[]'::jsonb)
          from (select to_char(created_at at time zone v_tz, 'YYYY-MM-DD') as day, count(*) as shipments
                  from s group by 1) x)),
      'direct', jsonb_build_object(
        'total', (select count(*) from d),
        'delivered', (select count(*) from d where status = 'delivered'),
        'cancelled', (select count(*) from d where status = 'cancelled'),
        'active', (select count(*) from d where status not in ('delivered', 'cancelled'))),
      'settlements', jsonb_build_object(
        'by_status', (select coalesce(jsonb_agg(jsonb_build_object(
            'status', x.status, 'count', x.n, 'amount', x.amount)), '[]'::jsonb)
          from (select status, count(*) as n, coalesce(sum(amount), 0) as amount
                  from c group by status) x))
    ));
end $$;
revoke all on function public.admin_delivery_dashboard(uuid, text, date, date) from public, anon;
grant execute on function public.admin_delivery_dashboard(uuid, text, date, date) to authenticated;
