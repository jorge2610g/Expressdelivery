-- ROLLBACK manual de 20261010160000_admin_production_read_guard.sql
do $rb$
declare r record; v_sig text;
begin
  for r in select signature, definition, acl from public.admin_function_backup_20261010 where signature like 'E1b:%' loop
    v_sig := substr(r.signature, 5);
    execute r.definition;
    if coalesce(r.acl,'') like '%authenticated=X%' then execute format('grant execute on function %s to authenticated', v_sig); end if;
    if coalesce(r.acl,'') like '%anon=X%' then execute format('grant execute on function %s to anon', v_sig); end if;
    if r.acl is null or r.acl like '%{=X%' or r.acl like '%,=X%' then execute format('grant execute on function %s to public', v_sig); end if;
  end loop;
end
$rb$;
