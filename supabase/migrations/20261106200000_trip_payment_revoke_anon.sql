-- Cierra la ejecución de las funciones de cobro con QR para el rol anónimo.
-- Las tres ya comprueban auth.uid(); esto aplica el mínimo privilegio del proyecto.
-- Aplicada en producción el 2026-11-06 con nombre trip_payment_revoke_anon.
begin;

revoke execute on function public.request_trip_payment(uuid) from public, anon;
revoke execute on function public.passenger_can_view_payment_qr(text) from public, anon;
revoke execute on function public.passenger_trip_driver_payment_qr(uuid) from public, anon;

grant execute on function public.request_trip_payment(uuid) to authenticated;
grant execute on function public.passenger_can_view_payment_qr(text) to authenticated;
grant execute on function public.passenger_trip_driver_payment_qr(uuid) to authenticated;

commit;
