-- Didit identity autofill. Only approved production sessions may replace
-- manual identity uploads. Driver license and all other document checks remain.
-- This migration does not alter historical rows or remove storage objects.

create or replace function public.submit_driver_onboarding(
  p_zone_id uuid,
  p_license_number text,
  p_service_keys text[],
  p_vehicle_type text,
  p_vehicle_brand text,
  p_vehicle_model text,
  p_vehicle_color text,
  p_vehicle_plate text,
  p_vehicle_year integer,
  p_profile_photo_path text,
  p_vehicle_photo_paths text[],
  p_documents jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_zone public.service_zones%rowtype;
  v_vehicle_id uuid;
  v_doc jsonb;
  v_req record;
  v_service text;
  v_path text;
  v_provider text := 'manual';
  v_didit_enabled boolean := false;
  v_didit_status text;
  v_didit_result jsonb;
  v_didit_number text;
  v_didit_expiration timestamptz;
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

  -- Didit is authoritative only after an approved PRODUCTION decision.
  -- Preview/sandbox verifications must never qualify a production driver.
  select coalesce(s.didit_enabled,false) into v_didit_enabled
  from public.identity_verification_country_settings s
  where s.country_code=upper(coalesce(v_zone.country_code,''));
  v_didit_enabled := coalesce(v_didit_enabled,false);

  if v_didit_enabled then
    select iv.status,iv.result into v_didit_status,v_didit_result
    from public.identity_verifications iv
    where iv.user_id=v_uid and iv.provider='didit'
      and iv.subject_role='driver'
      and iv.provider_environment='production'
      and upper(coalesce(iv.country_code,''))=upper(coalesce(v_zone.country_code,''))
    order by iv.created_at desc,iv.id desc limit 1;

    if v_didit_status is distinct from 'verified' then
      raise exception 'Tu verificación de identidad todavía no fue aprobada por Didit';
    end if;

    v_didit_number := coalesce(
      nullif(trim(v_didit_result #>> '{identity,document_number}'),''),
      nullif(trim(v_didit_result #>> '{identity,personal_number}'),'')
    );
    if v_didit_number is null then
      raise exception 'Didit no devolvió el número del documento. Contacta a soporte';
    end if;
    if coalesce(
      nullif(trim(v_didit_result #>> '{identity,full_name}'),''),
      nullif(trim(concat_ws(' ',
        v_didit_result #>> '{identity,first_name}',
        v_didit_result #>> '{identity,last_name}'
      )),'')
    ) is null then
      raise exception 'Didit no devolvió tu nombre. Contacta a soporte';
    end if;

    -- The provider might return no expiration or an invalid date. Never
    -- invent one; leave it NULL for manual review.
    begin
      if (v_didit_result #>> '{identity,expiration_date}')
           ~ '^\\d{4}-\\d{2}-\\d{2}
    from public.driver_document_requirements r
    where r.active=true and r.required=true
      and (r.country_code is null or upper(r.country_code)=upper(coalesce(v_zone.country_code,'')))
      and (r.zone_id is null or r.zone_id=v_zone.id)
  loop
    -- Identity images and selfie are already validated by Didit.
    if v_didit_enabled and lower(coalesce(v_req.code,'')) in (
      'identity_card','national_id','id_card','identity','carnet','cedula','cédula'
    ) then continue; end if;
    if not exists(
      select 1
      from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb)) d
      where d->>'requirement_id'=v_req.id::text
        and (not v_req.require_number or nullif(trim(coalesce(d->>'document_number','')),'') is not null)
        and (not v_req.require_front or public.driver_owns_onboarding_object(d->>'front_object_path'))
        and (not v_req.require_back or public.driver_owns_onboarding_object(d->>'back_object_path'))
        and (not v_req.require_selfie or public.driver_owns_onboarding_object(d->>'selfie_object_path'))
    ) then
      raise exception 'Falta completar el documento requerido: %',v_req.label;
    end if;
  end loop;

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
      status='pending',
      verification_method='manual',
      verification_score=null,
      reviewed_by=null,
      reviewed_at=null,
      rejection_reason=null,
      updated_at=now();
  end loop;

  -- Register the official identity document without requiring duplicate
  -- uploads. No address, marital status, birthplace or video is stored.
  if v_didit_enabled then
    for v_req in
      select r.id,r.code from public.driver_document_requirements r
      where r.active=true and r.required=true
        and (r.country_code is null or upper(r.country_code)=upper(coalesce(v_zone.country_code,'')))
        and (r.zone_id is null or r.zone_id=v_zone.id)
        and lower(coalesce(r.code,'')) in (
          'identity_card','national_id','id_card','identity','carnet','cedula','cédula'
        )
    loop
      insert into public.driver_documents(
        driver_id,requirement_id,document_type,document_number,
        expires_at,status,verification_method,updated_at
      )
      values (
        v_uid,v_req.id,v_req.code,v_didit_number,
        v_didit_expiration,'pending','didit',now()
      )
      on conflict(driver_id,requirement_id)
      where requirement_id is not null
      do update set
        document_number=excluded.document_number,
        expires_at=excluded.expires_at,
        status='pending',verification_method='didit',updated_at=now();
    end loop;
  end if;

  select provider into v_provider
  from public.identity_verification_settings where id=true;

  insert into public.identity_verifications(
    user_id,subject_role,document_type,status,provider,result
  )
  values(
    v_uid,'driver','driver_onboarding','pending',coalesce(v_provider,'manual'),
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
$$; then
        v_didit_expiration :=
          (v_didit_result #>> '{identity,expiration_date}')::date::timestamptz;
      end if;
    exception when datetime_field_overflow or invalid_datetime_format then
      v_didit_expiration := null;
    end;
  end if;

  for v_req in
    select r.id,r.code,r.label,r.require_number,r.require_front,r.require_back,r.require_selfie
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
    ) then
      raise exception 'Falta completar el documento requerido: %',v_req.label;
    end if;
  end loop;

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
      status='pending',
      verification_method='manual',
      verification_score=null,
      reviewed_by=null,
      reviewed_at=null,
      rejection_reason=null,
      updated_at=now();
  end loop;

  select provider into v_provider
  from public.identity_verification_settings where id=true;

  insert into public.identity_verifications(
    user_id,subject_role,document_type,status,provider,result
  )
  values(
    v_uid,'driver','driver_onboarding','pending',coalesce(v_provider,'manual'),
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
$$;
