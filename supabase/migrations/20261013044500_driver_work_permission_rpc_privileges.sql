-- Security hardening for independent work-permission RPCs.
-- The caller must be signed in; admin mutations additionally check is_admin().
revoke execute on function public.admin_driver_work_permission_list(uuid,text) from public, anon;
revoke execute on function public.admin_set_driver_work_permission(uuid,text,text,text) from public, anon;
revoke execute on function public.my_driver_work_permissions(text) from public, anon;
revoke execute on function public.request_driver_work_permission(text,text) from public, anon;
revoke execute on function public.driver_work_permission_allowed(uuid,text,text) from public, anon;
revoke execute on function public.driver_delivery_zone_enabled(uuid,text) from public, anon;
grant execute on function public.admin_driver_work_permission_list(uuid,text) to authenticated;
grant execute on function public.admin_set_driver_work_permission(uuid,text,text,text) to authenticated;
grant execute on function public.my_driver_work_permissions(text) to authenticated;
grant execute on function public.request_driver_work_permission(text,text) to authenticated;
grant execute on function public.driver_work_permission_allowed(uuid,text,text) to authenticated;
grant execute on function public.driver_delivery_zone_enabled(uuid,text) to authenticated;