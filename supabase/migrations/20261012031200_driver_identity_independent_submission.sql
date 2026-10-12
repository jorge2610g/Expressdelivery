-- Express · envío aislado de identidad, preservando seguridad y validación de otros documentos.
CREATE OR REPLACE FUNCTION public.update_my_driver_documents_for_review(p_documents jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_profile public.driver_profiles%rowtype;
  v_doc jsonb;
  v_req record;
  v_path text;
  v_submitted boolean:=false;
  v_identity_only boolean:=false;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select * into v_profile
  from public.driver_profiles
  where id=v_uid;

  if v_profile.id is null then
    raise exception 'Perfil de conductor no encontrado';
  end if;

  -- A standalone identity capture need not wait for licence or insurance.
  -- All other submissions retain the complete required-document validation.
  select count(*)=1 and coalesce(bool_and(
    lower(coalesce(r.code,'')) in
      ('identity_card','national_id','id_card','identity','carnet','cedula','cédula')
    ),false)
    into v_identity_only
  from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb)) d
  left join public.driver_document_requirements r
    on r.id=nullif(d->>'requirement_id','')::uuid;

  if v_identity_only then
    if not exists (
      select 1
      from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb)) d
      join public.driver_document_requirements r
        on r.id=nullif(d->>'requirement_id','')::uuid
      where r.active=true
        and (r.country_code is null or upper(r.country_code)=upper(coalesce(v_profile.country_code,'')))
        and (r.zone_id is null or r.zone_id=v_profile.zone_id)
        and (not r.require_number or nullif(trim(coalesce(d->>'document_number','')),'') is not null)
        and (not r.require_front or public.driver_owns_onboarding_object(d->>'front_object_path'))
        and (not r.require_back or public.driver_owns_onboarding_object(d->>'back_object_path'))
        and (not r.require_selfie or public.driver_owns_onboarding_object(d->>'selfie_object_path'))
    ) then
      raise exception 'Completa el documento de identidad de tu zona';
    end if;
  end if;

  if not v_identity_only then
  -- Every required additional document may be satisfied either by an already
  -- verified stored document OR by the specific correction included now.
  for v_req in
    select r.id,r.label,r.require_number,r.require_front,r.require_back,r.require_selfie
    from public.driver_document_requirements r
    where r.active=true
      and r.required=true
      and (r.country_code is null
           or upper(r.country_code)=upper(coalesce(v_profile.country_code,'')))
      and (r.zone_id is null or r.zone_id=v_profile.zone_id)
      and lower(coalesce(r.code,'')) not in
        ('identity_card','national_id','id_card','carnet','cedula','cédula')
      and lower(coalesce(r.code,'')) not like '%identity%'
  loop
    if not exists(
      select 1
      from public.driver_documents existing
      where existing.driver_id=v_uid
        and existing.requirement_id=v_req.id
        and existing.status='verified'
        and (not v_req.require_number
             or nullif(trim(coalesce(existing.document_number,'')),'') is not null)
        and (not v_req.require_front
             or nullif(trim(coalesce(existing.front_object_path,'')),'') is not null)
        and (not v_req.require_back
             or nullif(trim(coalesce(existing.back_object_path,'')),'') is not null)
        and (not v_req.require_selfie
             or nullif(trim(coalesce(existing.selfie_object_path,'')),'') is not null)
    )
    and not exists(
      select 1
      from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb)) d
      where d->>'requirement_id'=v_req.id::text
        and (not v_req.require_number
             or nullif(trim(coalesce(d->>'document_number','')),'') is not null)
        and (not v_req.require_front
             or public.driver_owns_onboarding_object(d->>'front_object_path'))
        and (not v_req.require_back
             or public.driver_owns_onboarding_object(d->>'back_object_path'))
        and (not v_req.require_selfie
             or public.driver_owns_onboarding_object(d->>'selfie_object_path'))
    ) then
      raise exception 'Falta completar el documento requerido: %',v_req.label;
    end if;
  end loop;
  end if; -- other documents require the full set

  for v_doc in
    select value
    from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb))
  loop
    if not exists(
      select 1
      from public.driver_document_requirements r
      where r.id=nullif(v_doc->>'requirement_id','')::uuid
        and r.active=true
        and (r.country_code is null
             or upper(r.country_code)=upper(coalesce(v_profile.country_code,'')))
        and (r.zone_id is null or r.zone_id=v_profile.zone_id)
    ) then
      raise exception 'Documento no permitido para esta ciudad';
    end if;

    foreach v_path in array array[
      nullif(trim(coalesce(v_doc->>'front_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'back_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'selfie_object_path','')),'')
    ] loop
      if v_path is not null
         and not public.driver_owns_onboarding_object(v_path) then
        raise exception 'Archivo de documento inválido';
      end if;
    end loop;

    v_submitted:=true;

    insert into public.driver_documents(
      driver_id,requirement_id,document_type,document_number,
      front_object_path,back_object_path,selfie_object_path,
      status,verification_method,updated_at
    )
    values(
      v_uid,
      nullif(v_doc->>'requirement_id','')::uuid,
      coalesce(nullif(v_doc->>'document_type',''),'document'),
      nullif(trim(coalesce(v_doc->>'document_number','')),''),
      nullif(trim(coalesce(v_doc->>'front_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'back_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'selfie_object_path','')),''),
      'pending','manual',now()
    )
    on conflict(driver_id,requirement_id)
    where requirement_id is not null
    do update set
      document_type=excluded.document_type,
      document_number=excluded.document_number,
      front_object_path=excluded.front_object_path,
      back_object_path=excluded.back_object_path,
      selfie_object_path=excluded.selfie_object_path,
      status=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.status
        else 'pending'
      end,
      verification_method='manual',
      verification_score=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.verification_score
        else null
      end,
      reviewed_by=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.reviewed_by
        else null
      end,
      reviewed_at=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.reviewed_at
        else null
      end,
      rejection_reason=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.rejection_reason
        else null
      end,
      updated_at=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
          then public.driver_documents.updated_at
        else now()
      end;
  end loop;

  if v_submitted then
    update public.driver_profiles
    set approval_status='pending',
        online_status='offline',
        updated_at=now()
    where id=v_uid;
  end if;

  return jsonb_build_object(
    'ok',true,
    'approval_status',(select approval_status from public.driver_profiles where id=v_uid),
    'submitted',v_submitted
  );
end;
$function$

