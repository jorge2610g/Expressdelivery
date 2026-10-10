-- ROLLBACK manual de 20261010140000_driver_auto_approval_on_verified_documents.sql
-- Restaura las dos RPC de revisión y elimina el helper. No revierte aprobaciones ya hechas.
do $rb$
declare r record;
begin
  for r in select definition from public.admin_function_backup_20261010 where signature like 'E4:%' loop
    execute r.definition;
  end loop;
end
$rb$;
drop function if exists public.driver_auto_approve_if_complete(uuid);
