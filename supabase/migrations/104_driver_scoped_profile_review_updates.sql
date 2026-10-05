-- Scoped driver profile editing.
-- Keeps each profile shortcut independent and sends sensitive edits back to review.

create or replace function public.request_my_driver_zone_change(p_zone_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_zone public.service_zones%rowtype;
  v_vehicle_type text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select * into v_zone
  from public.service_zones
  where id=p_zone_id and active=true;

  if v_zone.id is null then
    raise exception 'Zona no disponible';
  end if;

  if not exists(select 1 from public.driver_profiles where id=v_uid) then
    raise exception 'Perfil de conductor no encontrado';
  end if;

  select dv.vehicle_type into v_vehicle_type
  from public.driver_vehicles dv
  where dv.driver_id=v_uid and dv.is_active=true
  order by dv.updated_at desc
  limit 1;

  update public.driver_profiles
  set zone_id=v_zone.id,
      city=coalesce(v_zone.city,v_zone.name),
      country_code=upper(v_zone.country_code),
      approval_status='pending',
      online_status='offline',
      updated_at=now()
  where id=v_uid;

  update public.users
  set last_zone_id=v_zone.id,
      updated_at=now()
  where id=v_uid;

  insert into public.driver_service_preferences(driver_id,zone_id,service_key,enabled)
  select v_uid,v_zone.id,zs.service_key,true
  from public.zone_service_catalog zs
  join public.service_catalog sc on sc.service_key=zs.service_key
  where zs.zone_id=v_zone.id
    and zs.enabled=true
    and zs.driver_visible=true
    and sc.enabled=true
    and sc.driver_visible=true
    and (sc.vehicle_type is null or v_vehicle_type is null or sc.vehicle_type=v_vehicle_type)
  on conflict(driver_id,zone_id,service_key)
  do update set enabled=true,updated_at=now();

  return jsonb_build_object(
    'ok',true,
    'approval_status','pending',
    'zone_id',v_zone.id,
    'country_code',upper(v_zone.country_code),
    'city',coalesce(v_zone.city,v_zone.name)
  );
end;
$function$;

create or replace function public.update_my_driver_profile_photo_for_review(
  p_profile_photo_path text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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
  set profile_photo_path=nullif(trim(coalesce(p_profile_photo_path,'')),''),
      approval_status='pending',
      online_status='offline',
      updated_at=now()
  where id=v_uid;

  if not found then raise exception 'Perfil de conductor no encontrado'; end if;

  return jsonb_build_object(
    'ok',true,
    'approval_status','pending',
    'profile_photo_path',p_profile_photo_path
  );
end;
$function$;

create or replace function public.update_my_driver_vehicle_for_review(
  p_vehicle_type text,
  p_vehicle_brand text,
  p_vehicle_model text,
  p_vehicle_color text,
  p_vehicle_plate text,
  p_vehicle_year integer,
  p_vehicle_photo_paths text[]
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_vehicle_id uuid;
  v_path text;
  v_summary text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if nullif(trim(coalesce(p_vehicle_brand,'')),'') is null
     or nullif(trim(coalesce(p_vehicle_model,'')),'') is null
     or nullif(trim(coalesce(p_vehicle_plate,'')),'') is null then
    raise exception 'Completa marca, modelo y placa';
  end if;
  if coalesce(array_length(p_vehicle_photo_paths,1),0)=0 then
    raise exception 'Sube al menos una foto del vehículo';
  end if;
  foreach v_path in array coalesce(p_vehicle_photo_paths,'{}'::text[]) loop
    if not public.driver_owns_onboarding_object(v_path) then
      raise exception 'Foto de vehículo inválida';
    end if;
  end loop;

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
      v_uid,p_vehicle_type,
      nullif(trim(coalesce(p_vehicle_brand,'')),''),
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

  v_summary=trim(concat_ws(' ',
    nullif(trim(coalesce(p_vehicle_brand,'')),''),
    nullif(trim(coalesce(p_vehicle_model,'')),'')
  ));
  if nullif(trim(coalesce(p_vehicle_plate,'')),'') is not null then
    v_summary=trim(v_summary||' · '||trim(p_vehicle_plate));
  end if;

  update public.driver_profiles
  set vehicle_summary=nullif(v_summary,''),
      approval_status='pending',
      online_status='offline',
      updated_at=now()
  where id=v_uid;

  return jsonb_build_object(
    'ok',true,
    'approval_status','pending',
    'vehicle_id',v_vehicle_id
  );
end;
$function$;

create or replace function public.update_my_driver_documents_for_review(
  p_documents jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_profile public.driver_profiles%rowtype;
  v_doc jsonb;
  v_req record;
  v_path text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select * into v_profile from public.driver_profiles where id=v_uid;
  if v_profile.id is null then raise exception 'Perfil de conductor no encontrado'; end if;

  for v_req in
    select r.id,r.label,r.require_number,r.require_front,r.require_back,r.require_selfie
    from public.driver_document_requirements r
    where r.active=true and r.required=true
      and (r.country_code is null or upper(r.country_code)=upper(coalesce(v_profile.country_code,'')))
      and (r.zone_id is null or r.zone_id=v_profile.zone_id)
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

  for v_doc in
    select value from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb))
  loop
    if not exists(
      select 1
      from public.driver_document_requirements r
      where r.id=nullif(v_doc->>'requirement_id','')::uuid
        and r.active=true
        and (r.country_code is null or upper(r.country_code)=upper(coalesce(v_profile.country_code,'')))
        and (r.zone_id is null or r.zone_id=v_profile.zone_id)
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

  update public.driver_profiles
  set approval_status='pending',
      online_status='offline',
      updated_at=now()
  where id=v_uid;

  return jsonb_build_object('ok',true,'approval_status','pending');
end;
$function$;
