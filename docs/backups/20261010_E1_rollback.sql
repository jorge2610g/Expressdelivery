-- ROLLBACK de 20261010120000_admin_production_write_guard.sql
-- NO es una migración automática: ejecutar manualmente solo si E1 debe revertirse.
-- Restaura definiciones y permisos EXECUTE originales desde
-- public.admin_function_backup_20261010 y el default de allow_production.

do $rb$
declare r record;
begin
  for r in select signature, definition, acl from public.admin_function_backup_20261010 loop
    execute r.definition;  -- CREATE OR REPLACE con el cuerpo original
    if coalesce(r.acl,'') like '%authenticated=X%' then
      execute format('grant execute on function %s to authenticated', r.signature);
    end if;
    if coalesce(r.acl,'') like '%anon=X%' then
      execute format('grant execute on function %s to anon', r.signature);
    end if;
    if r.acl is null or r.acl like '%{=X%' or r.acl like '%,=X%' then
      execute format('grant execute on function %s to public', r.signature);
    end if;
  end loop;
end
$rb$;

alter table public.admin_users alter column allow_production set default true;
