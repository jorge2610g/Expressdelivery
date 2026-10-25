-- The scheduled expiry job runs as postgres, the function owner. Keep an
-- explicit service_role grant for trusted backend maintenance while removing
-- direct invocation by app users and anonymous PostgREST callers.
create or replace function public.service_expire_pending_driver_subscription_payments()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  update public.driver_subscription_payments
  set status = 'expired', updated_at = now()
  where status = 'pending'
    and expires_at is not null
    and expires_at <= now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

revoke all on function public.service_expire_pending_driver_subscription_payments()
from public, anon, authenticated, service_role;
grant execute on function public.service_expire_pending_driver_subscription_payments()
to service_role;

