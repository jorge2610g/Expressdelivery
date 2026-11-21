-- Foto del conductor en las ofertas: el pasajero no la veía antes de elegir.
--
-- La política de lectura de storage comprobaba driver_profiles dentro de un
-- EXISTS. Esa subconsulta se ejecuta con los permisos del pasajero y la RLS de
-- driver_profiles solo deja ver la fila con un viaje activo, no con una oferta
-- pendiente. Resultado: la descarga se negaba y la tarjeta quedaba con un
-- círculo de color. Se mueve la comprobación a una función SECURITY DEFINER
-- (igual que driver_can_view_passenger_profile_photo). La regla de quién puede
-- ver la foto no cambia: sigue siendo can_view_driver_profile_photo.

create or replace function public.driver_portrait_object_viewable(
  p_bucket text,
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'storage'
as $$
  select p_bucket = 'driver-onboarding'
    and exists (
      select 1
      from public.driver_profiles dp
      where dp.profile_photo_path = p_name
        and public.can_view_driver_profile_photo(dp.id, p_name)
    );
$$;

revoke all on function public.driver_portrait_object_viewable(text, text) from public, anon;
grant execute on function public.driver_portrait_object_viewable(text, text) to authenticated;

drop policy if exists driver_onboarding_read_authorized_driver_portrait on storage.objects;
create policy driver_onboarding_read_authorized_driver_portrait
  on storage.objects for select to authenticated
  using (
    bucket_id = 'driver-onboarding'
    and public.driver_portrait_object_viewable(bucket_id, name)
  );
