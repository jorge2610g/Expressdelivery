-- Revierte el bloqueo aplicado a conductores cuya foto de perfil se reemplazó por
-- la selfie del expediente. Su aprobación vuelve a la última decisión registrada
-- en la bitácora (set_driver_approval); quienes no tienen registro quedan en
-- pendiente. Se quita la marca de re-subida. No se cambia la foto de perfil.
-- El disparador de registro de ventas se desactiva solo durante la operación:
-- esos conductores ya estaban aprobados y su registro existe.

alter table public.driver_profiles disable trigger sales_on_driver_approved;

with affected as (
  select id from public.driver_profiles where profile_photo_path like '%/documents/%'
),
last_approval as (
  select distinct on (a.entity_id) a.entity_id::uuid as driver_id, a.details->>'status' as status
  from public.admin_audit_log a
  where a.action = 'set_driver_approval'
    and a.entity_id in (select id::text from affected)
  order by a.entity_id, a.created_at desc
)
update public.driver_profiles dp
set approval_status = la.status,
    updated_at = now()
from last_approval la
where dp.id = la.driver_id
  and la.status in ('approved', 'rejected')
  and dp.approval_status is distinct from la.status;

update public.driver_profiles dp
set approval_status = 'pending',
    updated_at = now()
where dp.profile_photo_path like '%/documents/%'
  and dp.approval_status = 'rejected'
  and not exists (
    select 1 from public.admin_audit_log a
    where a.action = 'set_driver_approval' and a.entity_id = dp.id::text
  );

update public.driver_profiles
set profile_photo_reupload_required = false,
    updated_at = now()
where profile_photo_reupload_required;

alter table public.driver_profiles enable trigger sales_on_driver_approved;
