-- Harden administrative SECURITY DEFINER RPCs.
-- Admin endpoints must never be callable before authentication.
-- The functions themselves still enforce is_admin(); this migration also
-- removes anonymous/PUBLIC EXECUTE and keeps authenticated/backend access.

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname like 'admin\\_%' escape '\\'
  loop
    execute format('revoke execute on function %s from public, anon', r.signature);
    execute format('grant execute on function %s to authenticated, service_role', r.signature);
  end loop;
end;
$$;
