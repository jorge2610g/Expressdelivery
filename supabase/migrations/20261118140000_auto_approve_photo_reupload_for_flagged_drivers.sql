-- Los conductores marcados para volver a cargar su foto ya estaban aprobados con
-- su foto anterior. Al subir una foto nueva (ruta fuera de expediente) quedan
-- aprobados sin revisión manual uno por uno, y se limpia la marca. El resto de
-- conductores sigue el flujo de revisión de siempre (pendiente y fuera de línea).
-- Ponerse en línea sigue siendo decisión del conductor.

create or replace function public.update_my_driver_profile_photo_for_review(p_profile_photo_path text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_reupload boolean := false;
  v_approval text := 'pending';
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if not public.driver_owns_onboarding_object(p_profile_photo_path) then
    raise exception 'Foto de perfil inválida';
  end if;

  select coalesce(dp.profile_photo_reupload_required, false)
  into v_reupload
  from public.driver_profiles dp
  where dp.id = v_uid;

  if v_reupload and p_profile_photo_path not like '%/documents/%' then
    v_approval := 'approved';
  end if;

  update public.driver_profiles
  set profile_photo_path = nullif(trim(coalesce(p_profile_photo_path,'')),''),
      approval_status = v_approval,
      online_status = 'offline',
      profile_photo_reupload_required = case when v_approval = 'approved' then false else profile_photo_reupload_required end,
      updated_at = now()
  where id = v_uid;

  if not found then
    raise exception 'Perfil de conductor no encontrado';
  end if;

  return jsonb_build_object(
    'ok', true,
    'approval_status', v_approval,
    'profile_photo_path', p_profile_photo_path
  );
end;
$function$;
