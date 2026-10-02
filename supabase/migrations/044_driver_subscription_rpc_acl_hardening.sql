
revoke execute on function public.admin_driver_subscriptions(text) from anon;
revoke execute on function public.admin_set_driver_subscription(uuid,bigint,timestamptz,text) from anon;
revoke execute on function public.admin_set_driver_subscription_settings(boolean,boolean,boolean,text) from anon;

grant execute on function public.admin_driver_subscriptions(text) to authenticated;
grant execute on function public.admin_set_driver_subscription(uuid,bigint,timestamptz,text) to authenticated;
grant execute on function public.admin_set_driver_subscription_settings(boolean,boolean,boolean,text) to authenticated;
