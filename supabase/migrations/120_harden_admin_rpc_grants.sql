-- Restrict administrative SECURITY DEFINER RPCs to authenticated sessions.
-- Each function still performs an explicit is_admin() authorization check.

revoke all on function public.admin_audit_list_v2(text,integer) from public,anon;
grant execute on function public.admin_audit_list_v2(text,integer) to authenticated;

revoke all on function public.admin_environment_config_get(text,text,text) from public,anon;
grant execute on function public.admin_environment_config_get(text,text,text) to authenticated;

revoke all on function public.admin_environment_config_list(text,text) from public,anon;
grant execute on function public.admin_environment_config_list(text,text) to authenticated;

revoke all on function public.admin_environment_config_upsert(text,text,text,jsonb) from public,anon;
grant execute on function public.admin_environment_config_upsert(text,text,text,jsonb) to authenticated;

revoke all on function public.admin_notification_campaign_list_v2(text,timestamptz,timestamptz,integer) from public,anon;
grant execute on function public.admin_notification_campaign_list_v2(text,timestamptz,timestamptz,integer) to authenticated;

revoke all on function public.admin_push_audience_estimate_v2(text,text,uuid,uuid) from public,anon;
grant execute on function public.admin_push_audience_estimate_v2(text,text,uuid,uuid) to authenticated;

revoke all on function public.admin_report_summary_v2(text,timestamptz,timestamptz) from public,anon;
grant execute on function public.admin_report_summary_v2(text,timestamptz,timestamptz) to authenticated;

revoke all on function public.admin_send_announcement_v4(text,text,text,text,uuid,uuid) from public,anon;
grant execute on function public.admin_send_announcement_v4(text,text,text,text,uuid,uuid) to authenticated;

revoke all on function public.admin_support_messages_v2(text,uuid) from public,anon;
grant execute on function public.admin_support_messages_v2(text,uuid) to authenticated;

revoke all on function public.admin_support_reply_v2(text,uuid,text) from public,anon;
grant execute on function public.admin_support_reply_v2(text,uuid,text) to authenticated;

revoke all on function public.admin_support_threads_v2(text) from public,anon;
grant execute on function public.admin_support_threads_v2(text) to authenticated;
