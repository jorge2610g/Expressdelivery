-- Harden runtime isolation helper functions after migration 089.

alter function public.normalize_runtime_channel(text)
  set search_path = public;

revoke all on function public.is_active_audit_user(uuid)
  from public, anon;
grant execute on function public.is_active_audit_user(uuid)
  to authenticated;

revoke all on function public.guard_request_runtime_channel()
  from public, anon;

revoke all on function public.sync_trip_runtime_channel()
  from public, anon;

revoke all on function public.sync_delivery_runtime_channel()
  from public, anon;

revoke all on function public.guard_driver_offer_runtime_channel()
  from public, anon;

revoke all on function public.notification_runtime_channel()
  from public, anon;
