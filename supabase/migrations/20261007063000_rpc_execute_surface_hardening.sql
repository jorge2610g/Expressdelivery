-- Reduce the exposed SECURITY DEFINER RPC surface.
-- Admin RPCs require an authenticated session; seed helpers are service-role only;
-- trigger functions are never meant to be called directly through PostgREST.

do $$
declare
  r record;
begin
  for r in
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
      and p.proname like 'admin_%'
  loop
    execute format(
      'revoke all on function public.%I(%s) from public, anon',
      r.proname,r.args
    );
    execute format(
      'grant execute on function public.%I(%s) to authenticated',
      r.proname,r.args
    );
  end loop;

  for r in
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
      and p.proname like 'seed_%'
  loop
    execute format(
      'revoke all on function public.%I(%s) from public, anon, authenticated',
      r.proname,r.args
    );
    execute format(
      'grant execute on function public.%I(%s) to service_role',
      r.proname,r.args
    );
  end loop;

  for r in
    select p.proname,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prorettype='trigger'::regtype
  loop
    execute format(
      'revoke all on function public.%I(%s) from public, anon, authenticated',
      r.proname,r.args
    );
  end loop;
end;
$$;

revoke all on function public.can_read_driver_profile(uuid,uuid)
from public,anon;
grant execute on function public.can_read_driver_profile(uuid,uuid)
to authenticated;

revoke all on function public.guard_driver_profile_location_integrity()
from public,anon,authenticated;
