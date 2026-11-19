-- Corrección urgente: la política de lectura de fotos de pasajero consultaba
-- public.ride_request_views directamente. El rol authenticated no tiene SELECT
-- sobre esa tabla, y Postgres evaluaba la consulta al leer CUALQUIER objeto de
-- Storage (también driver-onboarding), así que el panel daba 403.
-- Ahora la comprobación vive en una función SECURITY DEFINER y la política solo
-- la llama para el bucket passenger-profile. No se conceden permisos nuevos.

create or replace function public.driver_can_view_passenger_profile_photo(
  p_bucket text,
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = public, storage
as $$
  select p_bucket = 'passenger-profile'
    and (
      (storage.foldername(p_name))[1] = auth.uid()::text
      or public.is_admin()
      or exists (
        select 1
        from public.ride_requests rr
        where rr.passenger_id::text = (storage.foldername(p_name))[1]
          and (
            exists (
              select 1 from public.driver_offers o
              where o.ride_request_id = rr.id and o.driver_id = auth.uid()
            )
            or exists (
              select 1 from public.ride_request_views v
              where v.ride_request_id = rr.id and v.driver_id = auth.uid()
            )
          )
      )
    );
$$;

revoke execute on function public.driver_can_view_passenger_profile_photo(text, text) from public, anon;
grant execute on function public.driver_can_view_passenger_profile_photo(text, text) to authenticated;

drop policy if exists passenger_profile_select_scoped on storage.objects;
create policy passenger_profile_select_scoped
on storage.objects
for select to authenticated
using (
  bucket_id = 'passenger-profile'
  and public.driver_can_view_passenger_profile_photo(bucket_id, name)
);
