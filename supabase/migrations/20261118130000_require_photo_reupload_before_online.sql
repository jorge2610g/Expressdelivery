-- Los conductores marcados para volver a cargar su foto de perfil quedan como
-- rechazados y fuera de línea. No pueden ponerse en línea (el guard de cobertura
-- exige approval_status = 'approved') hasta que suban una foto nueva, esa foto
-- pase por revisión y el administrador la apruebe. No borra datos.

update public.driver_profiles
set approval_status = 'rejected',
    online_status = 'offline',
    updated_at = now()
where profile_photo_reupload_required = true
  and approval_status <> 'rejected';
