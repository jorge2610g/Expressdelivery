-- Stop the client-controlled, email-only login lockout. Anyone with the public
-- app key could previously set another person's email to a permanent lock.
-- Keep the read RPC as an unlocked compatibility response for older clients;
-- new clients authenticate directly through Supabase Auth.
create or replace function public.auth_login_guard_state(p_email text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select jsonb_build_object(
    'locked', false,
    'failed_attempts', 0,
    'remaining_attempts', 3
  );
$function$;

revoke all on function public.auth_login_guard_state(text)
from public, anon, authenticated;
grant execute on function public.auth_login_guard_state(text)
to anon, authenticated;

-- Older app versions may still call this after an invalid password. Denying
-- this write is safe: they receive the ordinary login error, while no caller
-- can lock a different user by supplying an email address.
revoke all on function public.auth_login_guard_record_failure(text)
from public, anon, authenticated, service_role;

