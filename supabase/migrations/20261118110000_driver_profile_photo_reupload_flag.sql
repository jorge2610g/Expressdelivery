-- Conductores cuya foto de perfil se reemplazó por una selfie del expediente
-- deben volver a cargar su foto. Marca aditiva: columna, función de lectura y
-- limpieza automática cuando el conductor sube una foto nueva.
-- No cambia la foto de perfil existente ni el flujo de revisión.

alter table public.driver_profiles
  add column if not exists profile_photo_reupload_required boolean not null default false;

-- Quienes tienen como foto de perfil la selfie de un expediente deben volver a cargarla.
update public.driver_profiles
set profile_photo_reupload_required = true
where profile_photo_path like '%/documents/%'
  and profile_photo_reupload_required = false;

-- Al subir una foto de perfil nueva (ruta que no es de expediente), se limpia la marca.
create or replace function public.driver_profile_photo_reupload_clear()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.profile_photo_path is distinct from old.profile_photo_path
     and nullif(trim(coalesce(new.profile_photo_path,'')),'') is not null
     and new.profile_photo_path not like '%/documents/%' then
    new.profile_photo_reupload_required := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_driver_profile_photo_reupload_clear on public.driver_profiles;
create trigger trg_driver_profile_photo_reupload_clear
before update of profile_photo_path on public.driver_profiles
for each row execute function public.driver_profile_photo_reupload_clear();

create or replace function public.my_driver_profile_photo_reupload_required()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select dp.profile_photo_reupload_required from public.driver_profiles dp where dp.id = auth.uid()),
    false
  );
$$;

revoke execute on function public.my_driver_profile_photo_reupload_required() from public, anon;
grant execute on function public.my_driver_profile_photo_reupload_required() to authenticated;
