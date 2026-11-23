-- Arreglo: la política de lectura de archivos para operadores llamaba funciones
-- sin permiso de ejecución para el rol que lee, y bloqueaba TODA la lectura del
-- bucket driver-onboarding. Ahora la comprobación vive en una función segura.
create or replace function public.admin_operator_can_read_driver_file(p_name text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select case
    when split_part(coalesce(p_name,''), '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then coalesce(public.admin_can('drivers.view_documents', public.admin_zone_of_user(split_part(p_name, '/', 1)::uuid)), false)
    else false
  end;
$$;
revoke all on function public.admin_operator_can_read_driver_file(text) from public, anon;
grant execute on function public.admin_operator_can_read_driver_file(text) to authenticated;

drop policy if exists driver_onboarding_read_operator_permission on storage.objects;
create policy driver_onboarding_read_operator_permission on storage.objects
  for select to authenticated
  using (
    bucket_id = 'driver-onboarding'
    and public.admin_operator_can_read_driver_file(name)
  );
