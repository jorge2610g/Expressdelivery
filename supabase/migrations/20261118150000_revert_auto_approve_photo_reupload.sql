-- Se revierte la aprobación automática de la foto de perfil marcada. Cada foto
-- nueva vuelve a pasar por revisión del administrador (pendiente y fuera de
-- línea), igual que antes. La marca de reupload sigue limpiándose por trigger
-- cuando cambia la ruta de la foto.

create or replace function public.update_my_driver_profile_photo_for_review(p_profile_photo_path text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if not public.driver_owns_onboarding_object(p_profile_photo_path) then
    raise exception 'Foto de perfil inválida';
  end if;

  update public.driver_profiles
  set profile_photo_path = nullif(trim(coalesce(p_profile_photo_path,'')),''),
      approval_status = 'pending',
      online_status = 'offline',
      updated_at = now()
  where id = v_uid;

  if not found then
    raise exception 'Perfil de conductor no encontrado';
  end if;

  return jsonb_build_object(
    'ok', true,
    'approval_status', 'pending',
    'profile_photo_path', p_profile_photo_path
  );
end;
$function$;
