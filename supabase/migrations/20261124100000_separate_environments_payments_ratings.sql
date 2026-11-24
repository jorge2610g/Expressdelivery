-- Complemento de la separación restaurante / pasajero: pagos y resumen de calificaciones.
-- El pago en efectivo de un envío de restaurante no aparece en los Pagos del pasajero de esa cuenta
-- (el conductor que lo cobró lo sigue viendo), y la calificación que un conductor deja a la
-- cuenta del restaurante no cuenta en su promedio de pasajero.
create or replace function public.is_merchant_courier_trip(p_trip_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce((select r.merchant_courier from public.trips t
                     join public.ride_requests r on r.id = t.ride_request_id
                    where t.id = p_trip_id), false);
$$;
revoke all on function public.is_merchant_courier_trip(uuid) from public, anon;
grant execute on function public.is_merchant_courier_trip(uuid) to authenticated;

do $m$
declare
  v_def text; v_new text; v_name text;
begin
  for v_name in select unnest(array['my_country_payments', 'my_country_payments_v2']) loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = v_name;
    v_new := replace(v_def, '(p.payer_id=v_uid or p.payee_id=v_uid)',
      '(p.payee_id=v_uid or (p.payer_id=v_uid and not public.is_merchant_courier_trip(p.trip_id)))');
    if v_new = v_def then raise exception 'No se pudo parchear %', v_name; end if;
    execute v_new;
  end loop;

  select pg_get_functiondef(p.oid) into v_def from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'my_rating_summary_for';
  v_new := replace(v_def, E'    where to_user_id = v_uid\n      and rated_role = v_role',
    E'    where to_user_id = v_uid\n      and rated_role = v_role\n      and not public.is_merchant_courier_trip(trip_id)');
  if v_new = v_def then raise exception 'No se pudo parchear my_rating_summary_for'; end if;
  execute v_new;
end $m$;

drop policy if exists payments_read_participants on public.payment_transactions;
create policy payments_read_participants on public.payment_transactions for select using (
  (payee_id = (select auth.uid()))
  or (payer_id = (select auth.uid()) and not public.is_merchant_courier_trip(trip_id)));
