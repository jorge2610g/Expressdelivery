begin;

alter table public.marketplace_merchant_applications
  add column if not exists zone_id uuid references public.service_zones(id) on delete set null;

create table if not exists public.marketplace_merchant_requirements (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  label text not null,
  description text,
  required boolean not null default true,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(trim(label)) between 2 and 120),
  unique (channel, zone_id, label)
);

create index if not exists marketplace_merchant_requirements_scope_idx
  on public.marketplace_merchant_requirements(channel,zone_id,active,sort_order);
alter table public.marketplace_merchant_requirements enable row level security;
revoke all on public.marketplace_merchant_requirements from public,anon,authenticated;

create table if not exists public.marketplace_merchant_requirement_submissions (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.marketplace_merchant_applications(id) on delete cascade,
  requirement_id uuid not null references public.marketplace_merchant_requirements(id) on delete restrict,
  object_path text not null,
  submitted_at timestamptz not null default now(),
  unique(application_id,requirement_id)
);
alter table public.marketplace_merchant_requirement_submissions enable row level security;
revoke all on public.marketplace_merchant_requirement_submissions from public,anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('marketplace-merchant-requirements','marketplace-merchant-requirements',false,8388608,
       array['image/jpeg','image/png','image/webp']::text[])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists marketplace_merchant_requirement_upload on storage.objects;
create policy marketplace_merchant_requirement_upload on storage.objects
  for insert to authenticated
  with check (bucket_id='marketplace-merchant-requirements'
    and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists marketplace_merchant_requirement_read on storage.objects;
create policy marketplace_merchant_requirement_read on storage.objects
  for select to authenticated
  using (bucket_id='marketplace-merchant-requirements' and (
    (storage.foldername(name))[1]=(select auth.uid())::text or public.is_admin()
  ));
drop policy if exists marketplace_merchant_requirement_delete on storage.objects;
create policy marketplace_merchant_requirement_delete on storage.objects
  for delete to authenticated
  using (bucket_id='marketplace-merchant-requirements'
    and (storage.foldername(name))[1]=(select auth.uid())::text);

create or replace function public.marketplace_restaurant_zones(p_channel text)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_uid uuid:=auth.uid(); v_runtime jsonb; v_result jsonb;
begin
  if v_uid is null then raise exception 'Inicia sesión para continuar'; end if;
  v_runtime:=public.ensure_current_runtime_access(p_channel);
  if coalesce((v_runtime->>'allowed')::boolean,false) is not true then
    raise exception 'Esta cuenta pertenece a otro entorno';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',z.id,'name',coalesce(nullif(z.city,''),z.name),'country_code',z.country_code,
    'center_latitude',z.center_latitude,'center_longitude',z.center_longitude
  ) order by z.country_code,coalesce(nullif(z.city,''),z.name)),'[]'::jsonb)
  into v_result from public.service_zones z where z.active;
  return v_result;
end $$;
revoke all on function public.marketplace_restaurant_zones(text) from public,anon;
grant execute on function public.marketplace_restaurant_zones(text) to authenticated;

create or replace function public.marketplace_restaurant_requirements(p_zone_id uuid,p_channel text)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_uid uuid:=auth.uid(); v_runtime jsonb; v_result jsonb;
begin
  if v_uid is null then raise exception 'Inicia sesión para continuar'; end if;
  v_runtime:=public.ensure_current_runtime_access(p_channel);
  if coalesce((v_runtime->>'allowed')::boolean,false) is not true then
    raise exception 'Esta cuenta pertenece a otro entorno';
  end if;
  select coalesce(jsonb_agg(to_jsonb(r) order by r.sort_order,r.created_at),'[]'::jsonb)
  into v_result from public.marketplace_merchant_requirements r
  where r.zone_id=p_zone_id and r.channel=p_channel and r.active;
  return v_result;
end $$;
revoke all on function public.marketplace_restaurant_requirements(uuid,text) from public,anon;
grant execute on function public.marketplace_restaurant_requirements(uuid,text) to authenticated;

create or replace function public.marketplace_merchant_application_state(p_channel text)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_uid uuid:=auth.uid(); v_result jsonb;
begin
  if v_uid is null or p_channel not in ('preview','production') then
    raise exception 'No autorizado';
  end if;
  if not exists(select 1 from public.account_runtime_bindings b
    where b.user_id=v_uid and b.environment=p_channel) then
    raise exception 'Esta cuenta pertenece a otro entorno';
  end if;
  select to_jsonb(a)||jsonb_build_object(
    'requirements',coalesce((select jsonb_agg(jsonb_build_object(
      'id',r.id,'label',r.label,'object_path',s.object_path)
      order by r.sort_order,r.label)
      from public.marketplace_merchant_requirement_submissions s
      join public.marketplace_merchant_requirements r on r.id=s.requirement_id
      where s.application_id=a.id),'[]'::jsonb)
  ) into v_result from public.marketplace_merchant_applications a
  where a.user_id=v_uid and a.channel=p_channel
  order by a.created_at desc limit 1;
  return coalesce(v_result,'{}'::jsonb);
end $$;
revoke all on function public.marketplace_merchant_application_state(text) from public,anon;
grant execute on function public.marketplace_merchant_application_state(text) to authenticated;

create or replace function public.admin_marketplace_restaurant_requirements(p_zone_id uuid,p_channel text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb;
begin
  if not public.is_admin() then raise exception 'Solo Admin puede revisar requisitos'; end if;
  if p_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  select coalesce(jsonb_agg(to_jsonb(r) order by r.sort_order,r.created_at),'[]'::jsonb)
    into v_result from public.marketplace_merchant_requirements r
    where r.zone_id=p_zone_id and r.channel=p_channel;
  return v_result;
end $$;
revoke all on function public.admin_marketplace_restaurant_requirements(uuid,text) from public,anon;
grant execute on function public.admin_marketplace_restaurant_requirements(uuid,text) to authenticated;

create or replace function public.admin_marketplace_upsert_restaurant_requirement(
  p_id uuid,p_zone_id uuid,p_channel text,p_label text,p_description text,
  p_required boolean,p_active boolean,p_sort_order integer
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Solo Admin puede editar requisitos'; end if;
  if p_channel not in ('preview','production') or not exists(
    select 1 from public.service_zones where id=p_zone_id and active
  ) then raise exception 'Selecciona una ciudad activa'; end if;
  if length(trim(coalesce(p_label,''))) not between 2 and 120 then
    raise exception 'Escribe el nombre del requisito';
  end if;
  if p_id is null then
    insert into public.marketplace_merchant_requirements(
      channel,zone_id,label,description,required,active,sort_order
    ) values(p_channel,p_zone_id,trim(p_label),nullif(trim(coalesce(p_description,'')),''),
      coalesce(p_required,true),coalesce(p_active,true),coalesce(p_sort_order,100))
    returning id into v_id;
  else
    update public.marketplace_merchant_requirements set
      zone_id=p_zone_id,channel=p_channel,label=trim(p_label),
      description=nullif(trim(coalesce(p_description,'')),''),
      required=coalesce(p_required,true),active=coalesce(p_active,true),
      sort_order=coalesce(p_sort_order,100),updated_at=now()
    where id=p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró el requisito'; end if;
  end if;
  return (select to_jsonb(r) from public.marketplace_merchant_requirements r where r.id=v_id);
end $$;
revoke all on function public.admin_marketplace_upsert_restaurant_requirement(uuid,uuid,text,text,text,boolean,boolean,integer) from public,anon;
grant execute on function public.admin_marketplace_upsert_restaurant_requirement(uuid,uuid,text,text,text,boolean,boolean,integer) to authenticated;

create or replace function public.admin_marketplace_delete_restaurant_requirement(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Solo Admin puede eliminar requisitos'; end if;
  if exists(select 1 from public.marketplace_merchant_requirement_submissions s where s.requirement_id=p_id) then
    raise exception 'Este requisito ya tiene documentos enviados. Desactívalo para conservar el historial.';
  end if;
  delete from public.marketplace_merchant_requirements where id=p_id;
  if not found then raise exception 'No se encontró el requisito'; end if;
end $$;
revoke all on function public.admin_marketplace_delete_restaurant_requirement(uuid) from public,anon;
grant execute on function public.admin_marketplace_delete_restaurant_requirement(uuid) to authenticated;

create or replace function public.marketplace_submit_merchant_application_v2(
  p_channel text,p_email text,p_restaurant_name text,p_logo_url text,
  p_cover_image_url text,p_address text,p_latitude numeric,p_longitude numeric,
  p_zone_id uuid,p_requirement_documents jsonb
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_uid uuid:=auth.uid(); v_auth_email text; v_runtime jsonb; v_id uuid;
  v_item jsonb; v_req uuid; v_path text;
begin
  if v_uid is null then raise exception 'Inicia sesión para solicitar acceso'; end if;
  if p_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  v_runtime:=public.ensure_current_runtime_access(p_channel);
  if coalesce((v_runtime->>'allowed')::boolean,false) is not true then
    raise exception 'Esta cuenta pertenece a otro entorno';
  end if;
  select lower(trim(email)) into v_auth_email from auth.users where id=v_uid;
  if v_auth_email is null or lower(trim(coalesce(p_email,'')))<>v_auth_email then
    raise exception 'El correo debe coincidir con la cuenta autenticada';
  end if;
  if not exists(select 1 from public.service_zones where id=p_zone_id and active) then
    raise exception 'Selecciona una ciudad activa';
  end if;
  if length(trim(coalesce(p_restaurant_name,''))) not between 2 and 120
     or length(trim(coalesce(p_address,''))) not between 4 and 500
     or p_latitude is null or p_latitude not between -90 and 90
     or p_longitude is null or p_longitude not between -180 and 180
     or length(trim(coalesce(p_logo_url,''))) not between 8 and 1000
     or length(trim(coalesce(p_cover_image_url,''))) not between 8 and 1000 then
    raise exception 'Completa nombre, logo, portada y ubicación';
  end if;
  if jsonb_typeof(coalesce(p_requirement_documents,'[]'::jsonb))<>'array' then
    raise exception 'Revisa los documentos solicitados';
  end if;
  if exists(select 1 from public.marketplace_merchant_requirements r
    where r.zone_id=p_zone_id and r.channel=p_channel and r.active and r.required
      and not exists(select 1 from jsonb_array_elements(coalesce(p_requirement_documents,'[]'::jsonb)) d
        where d->>'requirement_id'=r.id::text and coalesce(d->>'object_path','')<>'')) then
    raise exception 'Completa los documentos obligatorios de esta ciudad';
  end if;
  if exists(select 1 from public.marketplace_merchant_users mu where mu.user_id=v_uid and mu.active) then
    raise exception 'Esta cuenta ya administra un restaurante';
  end if;
  select id into v_id from public.marketplace_merchant_applications
    where user_id=v_uid and channel=p_channel and status='pending' for update;
  if v_id is null then
    insert into public.marketplace_merchant_applications(
      user_id,channel,email,restaurant_name,logo_url,cover_image_url,address,
      latitude,longitude,zone_id,status
    ) values(v_uid,p_channel,v_auth_email,trim(p_restaurant_name),trim(p_logo_url),
      trim(p_cover_image_url),trim(p_address),p_latitude,p_longitude,p_zone_id,'pending')
    returning id into v_id;
  else
    update public.marketplace_merchant_applications set email=v_auth_email,
      restaurant_name=trim(p_restaurant_name),logo_url=trim(p_logo_url),
      cover_image_url=trim(p_cover_image_url),address=trim(p_address),
      latitude=p_latitude,longitude=p_longitude,zone_id=p_zone_id,
      review_note=null,updated_at=now() where id=v_id;
  end if;
  delete from public.marketplace_merchant_requirement_submissions where application_id=v_id;
  for v_item in select value from jsonb_array_elements(coalesce(p_requirement_documents,'[]'::jsonb)) loop
    v_req:=nullif(v_item->>'requirement_id','')::uuid;
    v_path:=trim(coalesce(v_item->>'object_path',''));
    if v_req is null or v_path='' or split_part(v_path,'/',1)<>v_uid::text
       or not exists(select 1 from public.marketplace_merchant_requirements r
          where r.id=v_req and r.zone_id=p_zone_id and r.channel=p_channel and r.active) then
      raise exception 'Revisa los documentos cargados';
    end if;
    insert into public.marketplace_merchant_requirement_submissions(application_id,requirement_id,object_path)
    values(v_id,v_req,v_path);
  end loop;
  return jsonb_build_object('id',v_id,'status','pending');
end $$;
revoke all on function public.marketplace_submit_merchant_application_v2(text,text,text,text,text,text,numeric,numeric,uuid,jsonb) from public,anon;
grant execute on function public.marketplace_submit_merchant_application_v2(text,text,text,text,text,text,numeric,numeric,uuid,jsonb) to authenticated;
revoke execute on function public.marketplace_submit_merchant_application(
  text,text,text,text,text,text,numeric,numeric
) from authenticated;

create or replace function public.admin_marketplace_merchant_applications(
  p_channel text,p_zone_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb;
begin
  if not public.is_admin() then raise exception 'Solo Admin puede revisar solicitudes'; end if;
  if p_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object(
    'city',coalesce(nullif(z.city,''),z.name),
    'requirements',coalesce((select jsonb_agg(jsonb_build_object(
       'label',r.label,'object_path',s.object_path,'submitted_at',s.submitted_at
     ) order by r.sort_order,r.label)
     from public.marketplace_merchant_requirement_submissions s
     join public.marketplace_merchant_requirements r on r.id=s.requirement_id
     where s.application_id=a.id),'[]'::jsonb)
   ) order by a.created_at),'[]'::jsonb)
  into v_result from public.marketplace_merchant_applications a
  left join public.service_zones z on z.id=a.zone_id
  where a.channel=p_channel and a.status='pending'
    and (p_zone_id is null or a.zone_id=p_zone_id
      or (a.zone_id is null and public.service_zone_id_for_point(a.latitude,a.longitude)=p_zone_id));
  return v_result;
end $$;
revoke all on function public.admin_marketplace_merchant_applications(text,uuid) from public,anon;
grant execute on function public.admin_marketplace_merchant_applications(text,uuid) to authenticated;

create or replace function public.admin_marketplace_approve_merchant_application(
  p_application_id uuid,p_zone_id uuid
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_app public.marketplace_merchant_applications%rowtype;
  v_merchant uuid; v_zone public.service_zones%rowtype; v_bound text;
begin
  if not public.is_admin() then raise exception 'Solo Admin puede aprobar solicitudes'; end if;
  select * into v_app from public.marketplace_merchant_applications where id=p_application_id for update;
  if not found or v_app.status<>'pending' then raise exception 'Solicitud no disponible'; end if;
  select * into v_zone from public.service_zones where id=coalesce(v_app.zone_id,p_zone_id) and active;
  if not found or (v_app.zone_id is not null and p_zone_id is distinct from v_app.zone_id) then
    raise exception 'La solicitud corresponde a otra ciudad';
  end if;
  select environment into v_bound from public.account_runtime_bindings where user_id=v_app.user_id;
  if v_bound is distinct from v_app.channel then raise exception 'La cuenta no pertenece al entorno de esta solicitud'; end if;
  insert into public.marketplace_merchants(
    zone_id,category_key,name,image_url,cover_image_url,address,latitude,longitude,
    active,preview_visible,production_visible
  ) values(v_zone.id,'restaurants',v_app.restaurant_name,v_app.logo_url,v_app.cover_image_url,
    v_app.address,v_app.latitude,v_app.longitude,true,v_app.channel='preview',v_app.channel='production')
  returning id into v_merchant;
  insert into public.marketplace_merchant_users(merchant_id,user_id,role,active)
    values(v_merchant,v_app.user_id,'owner',true);
  update public.marketplace_merchant_applications set status='approved',merchant_id=v_merchant,
    reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=v_app.id;
  return jsonb_build_object('application_id',v_app.id,'merchant_id',v_merchant);
end $$;
revoke all on function public.admin_marketplace_approve_merchant_application(uuid,uuid) from public,anon;
grant execute on function public.admin_marketplace_approve_merchant_application(uuid,uuid) to authenticated;

commit;
