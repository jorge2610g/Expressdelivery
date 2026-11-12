-- Endurecimiento de funciones (advisors de seguridad de Supabase).
--
-- 1) Los disparadores (returns trigger) no se pueden llamar por RPC: PostgreSQL lo rechaza.
--    Se quita el permiso de ejecución a public, anon y authenticated. Los disparadores
--    siguen funcionando: PostgreSQL no comprueba EXECUTE al dispararlos.
-- 2) parcel_kind_capacity y parcel_vehicle_capacity tenían search_path mutable.
--    Se fija search_path = public. La lógica no cambia.

revoke all on function public.clear_floating_offer_optin_on_token_transfer() from public, anon, authenticated;
revoke all on function public.driver_expiration_online_guard() from public, anon, authenticated;
revoke all on function public.driver_generic_document_part_states() from public, anon, authenticated;
revoke all on function public.driver_profile_country_from_zone() from public, anon, authenticated;
revoke all on function public.guard_demo_merchant_membership() from public, anon, authenticated;
revoke all on function public.guard_driver_delivery_claim_permissions() from public, anon, authenticated;
revoke all on function public.guard_driver_offer_no_active_trip() from public, anon, authenticated;
revoke all on function public.guard_marketplace_demo_visibility() from public, anon, authenticated;
revoke all on function public.guard_parcel_kind_required() from public, anon, authenticated;
revoke all on function public.guard_parcel_ride_offer_permission() from public, anon, authenticated;
revoke all on function public.guard_parcel_trip_assignment() from public, anon, authenticated;
revoke all on function public.guard_ride_request_parcel_mode() from public, anon, authenticated;
revoke all on function public.marketplace_prepare_global_qr_order() from public, anon, authenticated;
revoke all on function public.round_delivery_proposed_fare() from public, anon, authenticated;
revoke all on function public.round_driver_offer_fare() from public, anon, authenticated;
revoke all on function public.round_trip_final_fare() from public, anon, authenticated;
revoke all on function public.sync_shared_marketplace_availability() from public, anon, authenticated;
revoke all on function public.sync_shared_marketplace_visibility() from public, anon, authenticated;
revoke all on function public.trg_publish_verified_play_build() from public, anon, authenticated;

alter function public.parcel_kind_capacity(text) set search_path = public;
alter function public.parcel_vehicle_capacity(text) set search_path = public;
