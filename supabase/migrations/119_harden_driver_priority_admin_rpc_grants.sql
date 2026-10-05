-- Restrict driver-priority admin RPCs to authenticated sessions.
-- Each RPC still performs its own is_admin() authorization check.

revoke all on function public.admin_driver_priority_state_v2(text)
from public, anon;
grant execute on function public.admin_driver_priority_state_v2(text)
to authenticated;

revoke all on function public.admin_update_driver_priority_settings_v2(
  text,boolean,boolean,numeric,numeric,numeric,numeric,numeric,numeric,
  integer,integer,integer
) from public, anon;
grant execute on function public.admin_update_driver_priority_settings_v2(
  text,boolean,boolean,numeric,numeric,numeric,numeric,numeric,numeric,
  integer,integer,integer
) to authenticated;
