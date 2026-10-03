-- Restrict zone/payment RPCs that require authenticated callers.

revoke all on function public.admin_set_zone_payment_provider(uuid,text,boolean)
  from public, anon;
grant execute on function public.admin_set_zone_payment_provider(uuid,text,boolean)
  to authenticated;

revoke all on function public.app_zone_context(numeric,numeric,text)
  from public, anon;
grant execute on function public.app_zone_context(numeric,numeric,text)
  to authenticated;
