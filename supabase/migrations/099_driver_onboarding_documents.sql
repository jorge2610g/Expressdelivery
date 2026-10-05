-- 099_driver_onboarding_documents.sql
-- Multi-step driver onboarding, zone-scoped services and configurable documents.

alter table public.driver_profiles
  add column if not exists country_code text,
  add column if not exists profile_photo_path text,
  add column if not exists onboarding_completed_at timestamptz;

alter table public.driver_vehicles
  add column if not exists photo_paths text[] not null default '{}'::text[];

create table if not exists public.driver_document_requirements (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  label text not null,
  description text,
  country_code text,
  zone_id uuid references public.service_zones(id) on delete cascade,
  required boolean not null default true,
  require_number boolean not null default false,
  require_front boolean not null default true,
  require_back boolean not null default false,
  require_selfie boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists driver_document_requirements_scope_code_uidx
  on public.driver_document_requirements(
    lower(code),
    coalesce(country_code,''),
    coalesce(zone_id,'00000000-0000-0000-0000-000000000000'::uuid)
  );

alter table public.driver_documents
  add column if not exists requirement_id uuid references public.driver_document_requirements(id) on delete set null,
  add column if not exists front_object_path text,
  add column if not exists back_object_path text,
  add column if not exists selfie_object_path text,
  add column if not exists verification_method text not null default 'manual',
  add column if not exists verification_score numeric,
  add column if not exists reviewed_by uuid,
  add column if not exists reviewed_at timestamptz,
  add column if not exists rejection_reason text;

create unique index if not exists driver_documents_driver_requirement_uidx
  on public.driver_documents(driver_id,requirement_id)
  where requirement_id is not null;

create table if not exists public.driver_service_preferences (
  driver_id uuid not null references public.driver_profiles(id) on delete cascade,
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  service_key text not null references public.service_catalog(service_key) on delete cascade,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(driver_id,zone_id,service_key)
);

alter table public.driver_document_requirements enable row level security;
alter table public.driver_documents enable row level security;
alter table public.driver_service_preferences enable row level security;

drop policy if exists driver_document_requirements_read_authenticated
  on public.driver_document_requirements;
create policy driver_document_requirements_read_authenticated
  on public.driver_document_requirements
  for select to authenticated
  using (true);

drop policy if exists driver_documents_read_self on public.driver_documents;
create policy driver_documents_read_self
  on public.driver_documents
  for select to authenticated
  using (driver_id=auth.uid() or public.is_admin());

drop policy if exists driver_documents_insert_self on public.driver_documents;
create policy driver_documents_insert_self
  on public.driver_documents
  for insert to authenticated
  with check (driver_id=auth.uid());

drop policy if exists driver_documents_update_self on public.driver_documents;
create policy driver_documents_update_self
  on public.driver_documents
  for update to authenticated
  using (driver_id=auth.uid())
  with check (driver_id=auth.uid());

drop policy if exists driver_documents_delete_self on public.driver_documents;
create policy driver_documents_delete_self
  on public.driver_documents
  for delete to authenticated
  using (driver_id=auth.uid());

drop policy if exists driver_service_preferences_self
  on public.driver_service_preferences;
create policy driver_service_preferences_self
  on public.driver_service_preferences
  for all to authenticated
  using (driver_id=auth.uid())
  with check (driver_id=auth.uid());

insert into public.driver_document_requirements(
  code,label,description,country_code,required,require_number,
  require_front,require_back,require_selfie,active,sort_order
)
values
  ('identity_card','Carné de identidad','Documento de identidad vigente.','BO',true,true,true,true,true,true,10),
  ('driver_license','Licencia de conducir','Licencia de conducir vigente.','BO',true,true,true,true,false,true,20),
  ('identity_card','Cédula de identidad','Documento de identidad vigente.','CL',true,true,true,true,true,true,10),
  ('driver_license','Licencia de conducir','Licencia de conducir vigente.','CL',true,true,true,true,false,true,20)
on conflict do nothing;

insert into storage.buckets(
  id,name,public,file_size_limit,allowed_mime_types
)
values(
  'driver-onboarding',
  'driver-onboarding',
  false,
  15728640,
  array['image/jpeg','image/png','image/webp','application/pdf']::text[]
)
on conflict(id) do update
set public=false,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists driver_onboarding_insert_self on storage.objects;
create policy driver_onboarding_insert_self
on storage.objects
for insert to authenticated
with check (
  bucket_id='driver-onboarding'
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists driver_onboarding_read_self_admin on storage.objects;
create policy driver_onboarding_read_self_admin
on storage.objects
for select to authenticated
using (
  bucket_id='driver-onboarding'
  and (
    (storage.foldername(name))[1]=auth.uid()::text
    or public.is_admin()
  )
);

drop policy if exists driver_onboarding_update_self on storage.objects;
create policy driver_onboarding_update_self
on storage.objects
for update to authenticated
using (
  bucket_id='driver-onboarding'
  and (storage.foldername(name))[1]=auth.uid()::text
)
with check (
  bucket_id='driver-onboarding'
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists driver_onboarding_delete_self on storage.objects;
create policy driver_onboarding_delete_self
on storage.objects
for delete to authenticated
using (
  bucket_id='driver-onboarding'
  and (storage.foldername(name))[1]=auth.uid()::text
);

create or replace function public.driver_onboarding_catalog(
  p_country_code text default null,
  p_zone_id uuid default null,
  p_lat numeric default null,
  p_lng numeric default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_country text := upper(nullif(trim(coalesce(p_country_code,'')),''));
  v_zone uuid := p_zone_id;
  v_zone_row public.service_zones%rowtype;
begin
  if auth.uid() is null then raise exception 'Autenticación requerida'; end if;

  if v_zone is null and p_lat is not null and p_lng is not null then
    select z.* into v_zone_row
    from public.service_zones z
    where z.active=true
      and z.center_latitude is not null
      and z.center_longitude is not null
      and (
        v_country is null
        or upper(coalesce(z.country_code,''))=v_country
      )
      and (
        6371 * 2 * asin(
          sqrt(
            power(sin(radians((z.center_latitude::numeric-p_lat)/2)),2)
            + cos(radians(p_lat))
              * cos(radians(z.center_latitude::numeric))
              * power(sin(radians((z.center_longitude::numeric-p_lng)/2)),2)
          )
        )
      ) <= z.radius_km
    order by (
      6371 * 2 * asin(
        sqrt(
          power(sin(radians((z.center_latitude::numeric-p_lat)/2)),2)
          + cos(radians(p_lat))
            * cos(radians(z.center_latitude::numeric))
            * power(sin(radians((z.center_longitude::numeric-p_lng)/2)),2)
        )
      )
    )
    limit 1;
    v_zone := v_zone_row.id;
  end if;

  if v_zone is not null and v_zone_row.id is null then
    select z.* into v_zone_row
    from public.service_zones z
    where z.id=v_zone and z.active=true;
  end if;

  if v_zone_row.id is not null then
    v_country := upper(coalesce(v_zone_row.country_code,v_country));
  end if;

  return jsonb_build_object(
    'countries',
      (
        select coalesce(jsonb_agg(x order by x->>'name'),'[]'::jsonb)
        from (
          select distinct jsonb_build_object(
            'code',upper(coalesce(z.country_code,'')),
            'name',z.country
          ) x
          from public.service_zones z
          where z.active=true and nullif(trim(coalesce(z.country_code,'')),'') is not null
        ) q
      ),
    'zones',
      (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id',z.id,'zone_key',z.zone_key,'name',z.name,'city',z.city,
            'country',z.country,'country_code',z.country_code,
            'center_latitude',z.center_latitude,'center_longitude',z.center_longitude,
            'radius_km',z.radius_km
          )
          order by z.city,z.name
        ),'[]'::jsonb)
        from public.service_zones z
        where z.active=true
          and (
            v_country is null
            or upper(coalesce(z.country_code,''))=v_country
          )
      ),
    'suggested_zone_id',v_zone,
    'selected_zone',
      case when v_zone_row.id is null then null else
        jsonb_build_object(
          'id',v_zone_row.id,'zone_key',v_zone_row.zone_key,
          'name',v_zone_row.name,'city',v_zone_row.city,
          'country',v_zone_row.country,'country_code',v_zone_row.country_code
        )
      end,
    'services',
      (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'service_key',c.service_key,'name',c.name,
            'description',c.description,'icon_key',c.icon_key,
            'vehicle_type',c.vehicle_type,'sort_order',zc.sort_order
          )
          order by zc.sort_order,c.name
        ),'[]'::jsonb)
        from public.zone_service_catalog zc
        join public.service_catalog c on c.service_key=zc.service_key
        where v_zone is not null
          and zc.zone_id=v_zone
          and zc.enabled=true
          and zc.driver_visible=true
          and c.enabled=true
          and c.driver_visible=true
      ),
    'document_requirements',
      (
        select coalesce(jsonb_agg(to_jsonb(r) order by r.sort_order,r.label),'[]'::jsonb)
        from public.driver_document_requirements r
        where r.active=true
          and (r.country_code is null or upper(r.country_code)=v_country)
          and (r.zone_id is null or r.zone_id=v_zone)
      ),
    'verification_settings',
      (select to_jsonb(s) from public.identity_verification_settings s where s.id=true)
  );
end;
$$;

create or replace function public.my_driver_onboarding_state()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Autenticación requerida'; end if;
  return jsonb_build_object(
    'profile',(select to_jsonb(d) from public.driver_profiles d where d.id=v_uid),
    'vehicle',(
      select to_jsonb(v) from public.driver_vehicles v
      where v.driver_id=v_uid
      order by v.is_active desc,v.updated_at desc
      limit 1
    ),
    'services',(
      select coalesce(jsonb_agg(to_jsonb(s) order by s.service_key),'[]'::jsonb)
      from public.driver_service_preferences s
      where s.driver_id=v_uid and s.enabled=true
    ),
    'documents',(
      select coalesce(jsonb_agg(to_jsonb(d) order by d.updated_at desc),'[]'::jsonb)
      from public.driver_documents d
      where d.driver_id=v_uid
    )
  );
end;
$$;

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
  v_provider text := 'manual';
begin
  if v_uid is null then raise exception 'Autenticación requerida'; end if;

  select * into v_zone
  from public.service_zones
  where id=p_zone_id and active=true;
  if v_zone.id is null then raise exception 'Ciudad no disponible'; end if;

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
    select r.id,r.label,r.require_number,r.require_front,r.require_back,r.require_selfie
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
        and (not v_req.require_front or nullif(trim(coalesce(d->>'front_object_path','')),'') is not null)
        and (not v_req.require_back or nullif(trim(coalesce(d->>'back_object_path','')),'') is not null)
        and (not v_req.require_selfie or nullif(trim(coalesce(d->>'selfie_object_path','')),'') is not null)
    ) then
      raise exception 'Falta completar el documento requerido: %',v_req.label;
    end if;
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

create or replace function public.admin_driver_document_requirement_list()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(
      to_jsonb(r) || jsonb_build_object(
        'zone_name',z.name,'zone_key',z.zone_key,
        'zone_country_code',z.country_code,'zone_country',z.country
      )
      order by r.country_code nulls first,z.name nulls first,r.sort_order,r.label
    ),'[]'::jsonb)
    from public.driver_document_requirements r
    left join public.service_zones z on z.id=r.zone_id
  );
end;
$$;

create or replace function public.admin_upsert_driver_document_requirement(
  p_id uuid,
  p_code text,
  p_label text,
  p_description text,
  p_country_code text,
  p_zone_id uuid,
  p_required boolean,
  p_require_number boolean,
  p_require_front boolean,
  p_require_back boolean,
  p_require_selfie boolean,
  p_active boolean,
  p_sort_order integer
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if nullif(trim(coalesce(p_code,'')),'') is null then raise exception 'Código requerido'; end if;
  if nullif(trim(coalesce(p_label,'')),'') is null then raise exception 'Nombre requerido'; end if;

  if p_id is null then
    insert into public.driver_document_requirements(
      code,label,description,country_code,zone_id,required,require_number,
      require_front,require_back,require_selfie,active,sort_order
    )
    values(
      lower(regexp_replace(trim(p_code),'[^a-zA-Z0-9_]+','_','g')),
      trim(p_label),nullif(trim(coalesce(p_description,'')),''),
      upper(nullif(trim(coalesce(p_country_code,'')),'')),p_zone_id,
      coalesce(p_required,true),coalesce(p_require_number,false),
      coalesce(p_require_front,true),coalesce(p_require_back,false),
      coalesce(p_require_selfie,false),coalesce(p_active,true),
      coalesce(p_sort_order,100)
    )
    returning id into v_id;
  else
    update public.driver_document_requirements
    set code=lower(regexp_replace(trim(p_code),'[^a-zA-Z0-9_]+','_','g')),
        label=trim(p_label),
        description=nullif(trim(coalesce(p_description,'')),''),
        country_code=upper(nullif(trim(coalesce(p_country_code,'')),'')),
        zone_id=p_zone_id,
        required=coalesce(p_required,true),
        require_number=coalesce(p_require_number,false),
        require_front=coalesce(p_require_front,true),
        require_back=coalesce(p_require_back,false),
        require_selfie=coalesce(p_require_selfie,false),
        active=coalesce(p_active,true),
        sort_order=coalesce(p_sort_order,100),
        updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Requisito no encontrado'; end if;
  perform public.admin_log_action(
    'upsert','driver_document_requirements',v_id::text,
    jsonb_build_object('code',p_code,'label',p_label,'zone_id',p_zone_id,'country_code',p_country_code)
  );
  return v_id;
end;
$$;

create or replace function public.admin_delete_driver_document_requirement(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  delete from public.driver_document_requirements where id=p_id;
  if not found then return false; end if;
  perform public.admin_log_action('delete','driver_document_requirements',p_id::text,'{}'::jsonb);
  return true;
end;
$$;

revoke execute on function public.driver_onboarding_catalog(text,uuid,numeric,numeric) from public,anon;
revoke execute on function public.my_driver_onboarding_state() from public,anon;
revoke execute on function public.submit_driver_onboarding(uuid,text,text[],text,text,text,text,text,integer,text,text[],jsonb) from public,anon;
revoke execute on function public.admin_driver_document_requirement_list() from public,anon;
revoke execute on function public.admin_upsert_driver_document_requirement(uuid,text,text,text,text,uuid,boolean,boolean,boolean,boolean,boolean,boolean,integer) from public,anon;
revoke execute on function public.admin_delete_driver_document_requirement(uuid) from public,anon;

grant execute on function public.driver_onboarding_catalog(text,uuid,numeric,numeric) to authenticated;
grant execute on function public.my_driver_onboarding_state() to authenticated;
grant execute on function public.submit_driver_onboarding(uuid,text,text[],text,text,text,text,text,integer,text,text[],jsonb) to authenticated;
grant execute on function public.admin_driver_document_requirement_list() to authenticated;
grant execute on function public.admin_upsert_driver_document_requirement(uuid,text,text,text,text,uuid,boolean,boolean,boolean,boolean,boolean,boolean,integer) to authenticated;
grant execute on function public.admin_delete_driver_document_requirement(uuid) to authenticated;
