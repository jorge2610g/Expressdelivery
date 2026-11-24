-- Las solicitudes de repartidor creadas por un restaurante usan la cuenta del restaurante como
-- passenger_id. Sin este filtro, la app de pasajero de esa misma cuenta las mostraba como un viaje
-- propio ("Buscando conductor… / Cancelar viaje"). El portal del restaurante las lee y cancela por
-- RPC (SECURITY DEFINER), y los conductores siguen viéndolas por sus propias políticas.
create or replace function public.is_ride_request_passenger(p_ride_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.ride_requests r
    where r.id = p_ride_id and r.passenger_id = p_user_id and not r.merchant_courier);
$$;

create or replace function public.is_merchant_courier_ride(p_ride_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce((select r.merchant_courier from public.ride_requests r where r.id = p_ride_id), false);
$$;
revoke all on function public.is_merchant_courier_ride(uuid) from public, anon;
grant execute on function public.is_merchant_courier_ride(uuid) to authenticated;

drop policy if exists rides_read_available_for_drivers on public.ride_requests;
create policy rides_read_available_for_drivers on public.ride_requests for select using (
  ((passenger_id = (select auth.uid())) and not merchant_courier)
  or ((status = any (array['searching'::text, 'offers_received'::text]))
      and is_approved_online_driver((select auth.uid()))
      and same_operational_scope(passenger_id, (select auth.uid())))
  or exists (select 1 from public.trips t
              where t.ride_request_id = ride_requests.id and t.driver_id = (select auth.uid())));

drop policy if exists trips_read_participants on public.trips;
create policy trips_read_participants on public.trips for select using (
  (((select auth.uid()) = passenger_id)
    and not public.is_merchant_courier_ride(trips.ride_request_id))
  or ((select auth.uid()) = driver_id));
