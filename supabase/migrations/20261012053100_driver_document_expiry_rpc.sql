-- RPC updates; execute after 20261012053000 expiry helpers.
CREATE OR REPLACE FUNCTION public.submit_driver_onboarding(p_zone_id uuid, p_license_number text, p_service_keys text[], p_vehicle_type text, p_vehicle_brand text, p_vehicle_model text, p_vehicle_color text, p_vehicle_plate text, p_vehicle_year integer, p_profile_photo_path text, p_vehicle_photo_paths text[], p_documents jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_zone public.service_zones%rowtype;
  v_vehicle_id uuid;
  v_doc jsonb;
  v_req record;
  v_service text;
  v_path text;
begin
  if v_uid is null then raise exception 'Autenticación requerida'; end if;

  select * into v_zone
  from public.service_zones
  where id=p_zone_id and active=true;
  if v_zone.id is null then raise exception 'Ciudad no disponible'; end if;

  if not public.driver_owns_onboarding_object(p_profile_photo_path) then
    raise exception 'Foto de perfil inválida';
  end if;

  foreach v_path in array coalesce(p_vehicle_photo_paths,'{}'::text[]) loop
    if not public.driver_owns_onboarding_object(v_path) then
      raise exception 'Foto de vehículo inválida';
    end if;
  end loop;

  if coalesce(array_length(p_vehicle_photo_paths,1),0)=0 then
    raise exception 'Sube al menos una foto del vehículo';
  end if;

  if coalesce(array_length(p_service_keys,1),0)=0 then
    raise exception 'Selecciona al menos un servicio';
  end if;

  foreach v_service in array p_service_keys loop
    if not exists(
      select 1
      from public.zone_service_catalog zc
      join public.service_catalog c on c.service_key=zc.service_key
      where zc.zone_id=v_zone.id
        and zc.service_key=v_service
        and zc.enabled=true and zc.driver_visible=true
        and c.enabled=true and c.driver_visible=true
        and (c.vehicle_type is null or c.vehicle_type=p_vehicle_type)
    ) then
      raise exception 'El servicio % no está habilitado para esta ciudad/vehículo',v_service;
    end if;
  end loop;

  for v_req in
    select r.id,r.code,r.label,r.require_number,r.require_front,r.require_back,r.require_selfie,r.expiration_required
    from public.driver_document_requirements r
    where r.active=true and r.required=true
      and (r.country_code is null or upper(r.country_code)=upper(coalesce(v_zone.country_code,'')))
      and (r.zone_id is null or r.zone_id=v_zone.id)
  loop
    if not exists(
      select 1
      from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb)) d
      where d->>'requirement_id'=v_req.id::text
        and (not v_req.require_number or nullif(trim(coalesce(d->>'document_number','')),'') is not null)
        and (not v_req.require_front or public.driver_owns_onboarding_object(d->>'front_object_path'))
        and (not v_req.require_back or public.driver_owns_onboarding_object(d->>'back_object_path'))
        and (not v_req.require_selfie or public.driver_owns_onboarding_object(d->>'selfie_object_path'))
        and (not v_req.expiration_required
          or nullif(d->>'expires_at','') is not null)
    ) then
      raise exception 'Falta completar el documento requerido: %',v_req.label;
    end if;
  end loop;

  -- Expiration dates are verified by the server; old approved files retain
  -- their previously accepted date until a new photo is reviewed.
  -- Reject document rows outside the selected country/city requirement set
  -- and reject object paths outside the caller's private folder.
  for v_doc in
    select value from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb))
  loop
    if not exists(
      select 1
      from public.driver_document_requirements r
      where r.id=nullif(v_doc->>'requirement_id','')::uuid
        and r.active=true
        and (r.country_code is null or upper(r.country_code)=upper(coalesce(v_zone.country_code,'')))
        and (r.zone_id is null or r.zone_id=v_zone.id)
    ) then
      raise exception 'Documento no permitido para esta ciudad';
    end if;

    foreach v_path in array array[
      nullif(trim(coalesce(v_doc->>'front_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'back_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'selfie_object_path','')),'')
    ] loop
      if v_path is not null and not public.driver_owns_onboarding_object(v_path) then
        raise exception 'Archivo de documento inválido';
      end if;
    end loop;
  end loop;

  insert into public.driver_profiles(
    id,approval_status,online_status,license_number,vehicle_summary,
    city,zone_id,country_code,profile_photo_path,onboarding_completed_at
  )
  values(
    v_uid,'pending','offline',nullif(trim(coalesce(p_license_number,'')),''),
    trim(coalesce(p_vehicle_brand,''))||' '||trim(coalesce(p_vehicle_model,''))||
      case when nullif(trim(coalesce(p_vehicle_plate,'')),'') is null then '' else ' · '||trim(p_vehicle_plate) end,
    coalesce(v_zone.city,v_zone.name),v_zone.id,upper(v_zone.country_code),
    nullif(trim(coalesce(p_profile_photo_path,'')),''),
    now()
  )
  on conflict(id) do update set
    approval_status='pending',
    online_status='offline',
    license_number=excluded.license_number,
    vehicle_summary=excluded.vehicle_summary,
    city=excluded.city,
    zone_id=excluded.zone_id,
    country_code=excluded.country_code,
    profile_photo_path=excluded.profile_photo_path,
    onboarding_completed_at=now(),
    updated_at=now();

  select id into v_vehicle_id
  from public.driver_vehicles
  where driver_id=v_uid
  order by is_active desc,updated_at desc
  limit 1;

  update public.driver_vehicles
  set is_active=false,updated_at=now()
  where driver_id=v_uid
    and (v_vehicle_id is null or id<>v_vehicle_id);

  if v_vehicle_id is null then
    insert into public.driver_vehicles(
      driver_id,vehicle_type,brand,model,color,plate,year,is_active,photo_paths
    )
    values(
      v_uid,p_vehicle_type,nullif(trim(coalesce(p_vehicle_brand,'')),''),
      nullif(trim(coalesce(p_vehicle_model,'')),''),
      nullif(trim(coalesce(p_vehicle_color,'')),''),
      nullif(trim(coalesce(p_vehicle_plate,'')),''),
      p_vehicle_year,true,coalesce(p_vehicle_photo_paths,'{}'::text[])
    )
    returning id into v_vehicle_id;
  else
    update public.driver_vehicles
    set vehicle_type=p_vehicle_type,
        brand=nullif(trim(coalesce(p_vehicle_brand,'')),''),
        model=nullif(trim(coalesce(p_vehicle_model,'')),''),
        color=nullif(trim(coalesce(p_vehicle_color,'')),''),
        plate=nullif(trim(coalesce(p_vehicle_plate,'')),''),
        year=p_vehicle_year,
        is_active=true,
        photo_paths=coalesce(p_vehicle_photo_paths,'{}'::text[]),
        updated_at=now()
    where id=v_vehicle_id and driver_id=v_uid;
  end if;

  delete from public.driver_service_preferences
  where driver_id=v_uid;

  foreach v_service in array p_service_keys loop
    insert into public.driver_service_preferences(driver_id,zone_id,service_key,enabled)
    values(v_uid,v_zone.id,v_service,true)
    on conflict(driver_id,zone_id,service_key)
    do update set enabled=true,updated_at=now();
  end loop;

  for v_doc in
    select value from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb))
  loop
    if nullif(v_doc->>'expires_at','') is not null and
      ((v_doc->>'expires_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       or (v_doc->>'expires_at')::date < (now() at time zone
        case upper(coalesce(v_zone.country_code,''))
         when 'CL' then 'America/Santiago'
         when 'BO' then 'America/La_Paz'
         when 'PE' then 'America/Lima' else 'UTC' end)::date) then
      raise exception 'La fecha de vencimiento no es válida';
    end if;
    insert into public.driver_documents(
      driver_id,requirement_id,document_type,document_number,
      front_object_path,back_object_path,selfie_object_path,
      expires_at,status,verification_method,updated_at
    )
    values(
      v_uid,
      nullif(v_doc->>'requirement_id','')::uuid,
      coalesce(nullif(v_doc->>'document_type',''),'document'),
      nullif(trim(coalesce(v_doc->>'document_number','')),''),
      nullif(trim(coalesce(v_doc->>'front_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'back_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'selfie_object_path','')),''),
      case when nullif(v_doc->>'expires_at','') is null then null else
        public.driver_doc_expiration_end((v_doc->>'expires_at')::date,
          v_zone.country_code) end,
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
      expires_at=coalesce(excluded.expires_at,public.driver_documents.expires_at),
      status='pending',
      verification_method='manual',
      verification_score=null,
      reviewed_by=null,
      reviewed_at=null,
      rejection_reason=null,
      updated_at=now();
  end loop;

  insert into public.identity_verifications(
    user_id,subject_role,document_type,status,provider,result
  )
  values(
    v_uid,'driver','driver_onboarding','pending','express_manual',
    jsonb_build_object(
      'zone_id',v_zone.id,'zone_key',v_zone.zone_key,
      'country_code',v_zone.country_code,'city',coalesce(v_zone.city,v_zone.name),
      'service_keys',to_jsonb(p_service_keys),
      'vehicle_id',v_vehicle_id
    )
  );

  return jsonb_build_object(
    'ok',true,'approval_status','pending','zone_id',v_zone.id,
    'city',coalesce(v_zone.city,v_zone.name),'vehicle_id',v_vehicle_id
  );
end;
$function$


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
    select r.id,r.label,r.require_number,r.require_front,r.require_back,r.require_selfie,r.expiration_required
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
        and (not v_req.expiration_required
             or nullif(trim(coalesce(d->>'expires_at','')),'') is not null)
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

    select r.* into v_req from public.driver_document_requirements r
    where r.id=(v_doc->>'requirement_id')::uuid;
    if v_req.expiration_required
       and nullif(trim(coalesce(v_doc->>'expires_at','')),'') is null
       and not exists(
         select 1 from public.driver_documents previous
         where previous.driver_id=v_uid
           and previous.requirement_id=v_req.id
           and previous.created_at < v_req.expiration_required_since
           and previous.status='verified'
           and previous.expires_at is null
       ) then
      raise exception 'Indica la fecha de vencimiento de %',v_req.label;
    end if;
    if nullif(trim(coalesce(v_doc->>'expires_at','')),'') is not null then
      if (v_doc->>'expires_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
          or (v_doc->>'expires_at')::date < (now() at time zone
            case upper(coalesce(v_profile.country_code,''))
             when 'CL' then 'America/Santiago'
             when 'BO' then 'America/La_Paz'
             when 'PE' then 'America/Lima'
             else 'UTC' end)::date then
        raise exception 'El documento % ya venció',v_req.label;
      end if;
      if exists(
        select 1 from public.driver_documents previous
        where previous.driver_id=v_uid and previous.requirement_id=v_req.id
          and previous.status='verified'
          and previous.expires_at is distinct from
            public.driver_doc_expiration_end(
              (v_doc->>'expires_at')::date,v_profile.country_code)
          and previous.front_object_path is not distinct from
              nullif(v_doc->>'front_object_path','')
          and previous.back_object_path is not distinct from
              nullif(v_doc->>'back_object_path','')
          and previous.selfie_object_path is not distinct from
              nullif(v_doc->>'selfie_object_path','')
      ) then
        raise exception 'Renueva la fotografía de % para cambiar su vencimiento',v_req.label;
      end if;
    end if;

    v_submitted:=true;

    insert into public.driver_documents(
      driver_id,requirement_id,document_type,document_number,
      front_object_path,back_object_path,selfie_object_path,
      expires_at,status,verification_method,updated_at
    )
    values(
      v_uid,
      nullif(v_doc->>'requirement_id','')::uuid,
      coalesce(nullif(v_doc->>'document_type',''),'document'),
      nullif(trim(coalesce(v_doc->>'document_number','')),''),
      nullif(trim(coalesce(v_doc->>'front_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'back_object_path','')),''),
      nullif(trim(coalesce(v_doc->>'selfie_object_path','')),''),
      case when nullif(v_doc->>'expires_at','') is null then null else
        public.driver_doc_expiration_end((v_doc->>'expires_at')::date,
          v_profile.country_code) end,
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
      expires_at=coalesce(excluded.expires_at,public.driver_documents.expires_at),
      status=case
        when public.driver_documents.document_number
               is not distinct from excluded.document_number
         and public.driver_documents.front_object_path
               is not distinct from excluded.front_object_path
         and public.driver_documents.back_object_path
               is not distinct from excluded.back_object_path
         and public.driver_documents.selfie_object_path
               is not distinct from excluded.selfie_object_path
         and public.driver_documents.expires_at
               is not distinct from coalesce(excluded.expires_at,public.driver_documents.expires_at)
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
         and public.driver_documents.expires_at
               is not distinct from coalesce(excluded.expires_at,public.driver_documents.expires_at)
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
         and public.driver_documents.expires_at
               is not distinct from coalesce(excluded.expires_at,public.driver_documents.expires_at)
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
         and public.driver_documents.expires_at
               is not distinct from coalesce(excluded.expires_at,public.driver_documents.expires_at)
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
         and public.driver_documents.expires_at
               is not distinct from coalesce(excluded.expires_at,public.driver_documents.expires_at)
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
         and public.driver_documents.expires_at
               is not distinct from coalesce(excluded.expires_at,public.driver_documents.expires_at)
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

