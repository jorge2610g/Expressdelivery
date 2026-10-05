-- 101_driver_onboarding_rls_hardening.sql
-- Resolve onboarding-specific advisor warnings and force validated write paths.

create or replace function public.driver_owns_onboarding_object(p_path text)
returns boolean
language sql
stable
security invoker
set search_path to 'public','auth'
as $$
  select auth.uid() is not null
    and nullif(trim(coalesce(p_path,'')),'') is not null
    and split_part(trim(p_path),'/',1)=auth.uid()::text
$$;

revoke execute on function public.driver_owns_onboarding_object(text) from public,anon;
grant execute on function public.driver_owns_onboarding_object(text) to authenticated;

drop policy if exists driver_documents_read_self on public.driver_documents;
create policy driver_documents_read_self
  on public.driver_documents
  for select to authenticated
  using (
    driver_id=(select auth.uid())
    or public.is_admin()
  );

drop policy if exists driver_service_preferences_self
  on public.driver_service_preferences;
drop policy if exists driver_service_preferences_read_self
  on public.driver_service_preferences;
create policy driver_service_preferences_read_self
  on public.driver_service_preferences
  for select to authenticated
  using (driver_id=(select auth.uid()));

revoke insert,update,delete on public.driver_documents from authenticated;
revoke insert,update,delete on public.driver_service_preferences from authenticated;
