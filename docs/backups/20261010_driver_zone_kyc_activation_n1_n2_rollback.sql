-- ROLLBACK manual de 20261010143000_driver_zone_kyc_activation_followup.sql.
-- Ejecutar solo con aprobación explícita y verificar la definición restaurada.
do $rollback$
declare r record;
begin
  for r in
    select definition
    from public.admin_function_backup_20261010
    where signature like 'DZK-N1N2:%'
  loop
    execute r.definition;
  end loop;
end
$rollback$;

revoke execute on function public.admin_driver_activate(uuid, uuid, text) from public, anon;
grant execute on function public.admin_driver_activate(uuid, uuid, text) to authenticated;
