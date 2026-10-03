-- Keep subscription state readable through its authenticated RPC without
-- exposing service_zones directly to client roles.

alter function public.my_driver_subscription_state() security definer;

revoke execute on function public.my_driver_subscription_state()
  from public, anon;

grant execute on function public.my_driver_subscription_state()
  to authenticated, service_role;
