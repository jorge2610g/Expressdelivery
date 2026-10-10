-- ROLLBACK manual de 20261010130655_driver_zone_kyc_activation.sql.
-- No revierte activaciones ni notificaciones ya realizadas.
do $rollback$
declare r record;
begin
  for r in
    select definition from public.admin_function_backup_20261010
    where signature like 'DZK:%'
  loop
    execute r.definition;
  end loop;
end
$rollback$;

drop function if exists public.admin_driver_activate(uuid, uuid, text);
