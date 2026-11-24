-- La lista de solicitudes del restaurante incluye el estado del viaje del repartidor.
create or replace function public.marketplace_merchant_courier_requests(p_merchant_id uuid, p_channel text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  perform public.marketplace_portal_role(p_merchant_id, p_channel);
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', cr.id, 'ride_request_id', cr.ride_request_id, 'created_at', cr.created_at,
      'service_type', cr.service_type, 'customer_name', cr.customer_name,
      'customer_phone', cr.customer_phone, 'destination_address', cr.destination_address,
      'collect_amount', cr.collect_amount, 'delivery_fee', cr.delivery_fee, 'currency', cr.currency,
      'prep_minutes', cr.prep_minutes,
      'status', r.status,
      'trip_status', (select t.status from public.trips t where t.ride_request_id = r.id
                       order by t.created_at desc limit 1),
      'driver_name', (select nullif(trim(u.full_name), '') from public.trips t
                        join public.users u on u.id = t.driver_id
                       where t.ride_request_id = r.id order by t.created_at desc limit 1))
      order by cr.created_at desc), '[]'::jsonb)
    from (select * from public.marketplace_courier_requests
           where merchant_id = p_merchant_id order by created_at desc limit 50) cr
    left join public.ride_requests r on r.id = cr.ride_request_id);
end $$;
