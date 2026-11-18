-- Corrección: el disparador de selfie de Bolivia ya no reemplaza la foto de
-- perfil de un conductor que ya la tiene. Solo copia la selfie cuando el
-- conductor no tiene foto de perfil. Reemplaza la función; no toca datos.
-- Motivo: la versión anterior sobrescribía la foto de perfil de conductores
-- existentes cada vez que se guardaba la selfie de un expediente manual.

CREATE OR REPLACE FUNCTION public.driver_kyc_bolivia_face_profile_mirror()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare v_country text; v_code text;
begin
  select upper(coalesce(p.country_code,'')), lower(coalesce(r.code,''))
  into v_country, v_code
  from public.driver_profiles p
  join public.driver_document_requirements r on r.id = new.requirement_id
  where p.id = new.driver_id;

  if new.verification_method = 'manual'
     and v_code in ('identity_card','national_id','id_card',
                    'identity','carnet','cedula','cédula')
     and nullif(trim(coalesce(new.selfie_object_path,'')),'') is not null then
    update public.driver_profiles
    set profile_photo_path = new.selfie_object_path,
        updated_at = now()
    where id = new.driver_id
      and profile_photo_path is distinct from new.selfie_object_path
      and nullif(trim(coalesce(profile_photo_path,'')),'') is null;
  end if;
  return new;
end;
$function$;

alter table public.driver_documents enable trigger trg_driver_kyc_bolivia_face_profile_mirror;
