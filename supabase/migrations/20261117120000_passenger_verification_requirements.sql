-- Verificación de pasajeros con requisitos configurables por el administrador.
-- Estado inicial: foto de perfil solicitada; carnet de identidad y selfie de
-- reconocimiento facial apagados hasta que el administrador los active.
-- Aditiva e idempotente. No modifica RPC ni tablas existentes salvo añadir la
-- columna users.profile_photo_path.

create table if not exists public.passenger_verification_settings (
  id boolean primary key default true check (id),
  profile_photo_required boolean not null default true,
  identity_document_required boolean not null default false,
  face_selfie_required boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.passenger_verification_settings enable row level security;
revoke all on public.passenger_verification_settings from anon, authenticated;

insert into public.passenger_verification_settings (id)
values (true)
on conflict (id) do nothing;

alter table public.users add column if not exists profile_photo_path text;

create table if not exists public.passenger_verification_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  document_type text not null check (
    document_type in ('identity_front', 'identity_back', 'face_selfie')
  ),
  object_path text not null,
  status text not null default 'submitted' check (
    status in ('submitted', 'approved', 'rejected')
  ),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists passenger_verification_documents_user_idx
  on public.passenger_verification_documents (user_id, created_at desc);

alter table public.passenger_verification_documents enable row level security;

drop policy if exists passenger_verification_documents_select on public.passenger_verification_documents;
create policy passenger_verification_documents_select
on public.passenger_verification_documents
for select to authenticated
using (user_id = auth.uid() or public.is_admin());

revoke all on public.passenger_verification_documents from anon, authenticated;
grant select on public.passenger_verification_documents to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'passenger-profile',
  'passenger-profile',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'passenger-verification',
  'passenger-verification',
  false,
  15728640,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Lectura de configuración para la app y el panel. Sin datos personales.
create or replace function public.passenger_verification_capture_enabled()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.passenger_verification_settings s
    where s.id = true
      and (s.identity_document_required or s.face_selfie_required)
  );
$$;

create or replace function public.passenger_verification_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_settings public.passenger_verification_settings%rowtype;
  v_has_photo boolean;
  v_submitted jsonb;
begin
  if v_uid is null then
    raise exception 'No autenticado';
  end if;

  select * into v_settings
  from public.passenger_verification_settings
  where id = true;

  select coalesce(nullif(btrim(u.profile_photo_path), ''), null) is not null
  into v_has_photo
  from public.users u
  where u.id = v_uid;

  select coalesce(jsonb_agg(d.document_type order by d.created_at desc), '[]'::jsonb)
  into v_submitted
  from public.passenger_verification_documents d
  where d.user_id = v_uid;

  return jsonb_build_object(
    'profile_photo_required', v_settings.profile_photo_required,
    'identity_document_required', v_settings.identity_document_required,
    'face_selfie_required', v_settings.face_selfie_required,
    'has_profile_photo', coalesce(v_has_photo, false),
    'submitted_documents', v_submitted
  );
end;
$$;

-- Políticas de Storage. Cada pasajero escribe solo en su carpeta (uid).
drop policy if exists passenger_profile_insert_self on storage.objects;
create policy passenger_profile_insert_self
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'passenger-profile'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists passenger_profile_update_self on storage.objects;
create policy passenger_profile_update_self
on storage.objects
for update to authenticated
using (
  bucket_id = 'passenger-profile'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'passenger-profile'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists passenger_profile_delete_self on storage.objects;
create policy passenger_profile_delete_self
on storage.objects
for delete to authenticated
using (
  bucket_id = 'passenger-profile'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Lectura: el propio pasajero, administradores y conductores que tienen una
-- oferta u opción de ver esa solicitud. Así el conductor ve la foto en el
-- momento de la solicitud y no antes.
drop policy if exists passenger_profile_select_scoped on storage.objects;
create policy passenger_profile_select_scoped
on storage.objects
for select to authenticated
using (
  bucket_id = 'passenger-profile'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
    or exists (
      select 1
      from public.ride_requests rr
      where rr.passenger_id::text = (storage.foldername(name))[1]
        and (
          exists (
            select 1 from public.driver_offers o
            where o.ride_request_id = rr.id and o.driver_id = auth.uid()
          )
          or exists (
            select 1 from public.ride_request_views v
            where v.ride_request_id = rr.id and v.driver_id = auth.uid()
          )
        )
    )
  )
);

drop policy if exists passenger_verification_insert_self on storage.objects;
create policy passenger_verification_insert_self
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'passenger-verification'
  and (storage.foldername(name))[1] = auth.uid()::text
  and public.passenger_verification_capture_enabled()
);

drop policy if exists passenger_verification_select_self_admin on storage.objects;
create policy passenger_verification_select_self_admin
on storage.objects
for select to authenticated
using (
  bucket_id = 'passenger-verification'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

-- Escritura de la foto de perfil: la ruta debe estar en la carpeta del propio
-- pasajero y el objeto debe existir en el bucket.
create or replace function public.passenger_set_profile_photo(p_object_path text)
returns jsonb
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_uid uuid := auth.uid();
  v_path text := btrim(coalesce(p_object_path, ''));
begin
  if v_uid is null then
    raise exception 'No autenticado';
  end if;
  if v_path = '' or split_part(v_path, '/', 1) <> v_uid::text or v_path like '%..%' then
    raise exception 'Ruta de foto inválida';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'passenger-profile' and o.name = v_path
  ) then
    raise exception 'La foto no se encontró';
  end if;

  update public.users
  set profile_photo_path = v_path,
      updated_at = now()
  where id = v_uid;

  return jsonb_build_object('profile_photo_path', v_path);
end;
$$;

-- Envío de carnet o selfie. Solo se acepta el tipo que el administrador activó.
create or replace function public.passenger_submit_verification_document(
  p_document_type text,
  p_object_path text
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_uid uuid := auth.uid();
  v_path text := btrim(coalesce(p_object_path, ''));
  v_settings public.passenger_verification_settings%rowtype;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'No autenticado';
  end if;

  select * into v_settings
  from public.passenger_verification_settings
  where id = true;

  if p_document_type in ('identity_front', 'identity_back') then
    if not v_settings.identity_document_required then
      raise exception 'Documento no solicitado';
    end if;
  elsif p_document_type = 'face_selfie' then
    if not v_settings.face_selfie_required then
      raise exception 'Documento no solicitado';
    end if;
  else
    raise exception 'Tipo de documento inválido';
  end if;

  if v_path = '' or split_part(v_path, '/', 1) <> v_uid::text or v_path like '%..%' then
    raise exception 'Ruta de documento inválida';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'passenger-verification' and o.name = v_path
  ) then
    raise exception 'El documento no se encontró';
  end if;

  insert into public.passenger_verification_documents (user_id, document_type, object_path)
  values (v_uid, p_document_type, v_path)
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'document_type', p_document_type,
    'status', 'submitted'
  );
end;
$$;

-- Configuración del administrador. Mismo control que los perfiles: solo super_admin.
create or replace function public.admin_passenger_verification_settings_update(
  p_profile_photo_required boolean,
  p_identity_document_required boolean,
  p_face_selfie_required boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.passenger_verification_settings%rowtype;
  v_after public.passenger_verification_settings%rowtype;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_profile_photo_required is null
     or p_identity_document_required is null
     or p_face_selfie_required is null then
    raise exception 'Valores requeridos';
  end if;

  select * into v_before
  from public.passenger_verification_settings
  where id = true
  for update;

  update public.passenger_verification_settings
  set profile_photo_required = p_profile_photo_required,
      identity_document_required = p_identity_document_required,
      face_selfie_required = p_face_selfie_required,
      updated_at = now(),
      updated_by = auth.uid()
  where id = true
  returning * into v_after;

  perform public.admin_log_action(
    'passenger_verification_settings_updated',
    'passenger_verification_settings',
    'global',
    jsonb_build_object(
      'before', jsonb_build_object(
        'profile_photo_required', v_before.profile_photo_required,
        'identity_document_required', v_before.identity_document_required,
        'face_selfie_required', v_before.face_selfie_required
      ),
      'after', jsonb_build_object(
        'profile_photo_required', v_after.profile_photo_required,
        'identity_document_required', v_after.identity_document_required,
        'face_selfie_required', v_after.face_selfie_required
      )
    )
  );

  return jsonb_build_object(
    'profile_photo_required', v_after.profile_photo_required,
    'identity_document_required', v_after.identity_document_required,
    'face_selfie_required', v_after.face_selfie_required
  );
end;
$$;

create or replace function public.admin_passenger_verification_settings_get()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_settings public.passenger_verification_settings%rowtype;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  select * into v_settings
  from public.passenger_verification_settings
  where id = true;
  return jsonb_build_object(
    'profile_photo_required', v_settings.profile_photo_required,
    'identity_document_required', v_settings.identity_document_required,
    'face_selfie_required', v_settings.face_selfie_required,
    'updated_at', v_settings.updated_at
  );
end;
$$;

create or replace function public.admin_passenger_verification_documents_list(
  p_user_id uuid default null
)
returns table (
  document_id uuid,
  passenger_id uuid,
  document_type text,
  object_path text,
  status text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  return query
  select d.id, d.user_id, d.document_type, d.object_path, d.status, d.created_at
  from public.passenger_verification_documents d
  where p_user_id is null or d.user_id = p_user_id
  order by d.created_at desc
  limit 500;
end;
$$;

revoke execute on function public.passenger_verification_capture_enabled() from public, anon;
revoke execute on function public.passenger_verification_state() from public, anon;
revoke execute on function public.passenger_set_profile_photo(text) from public, anon;
revoke execute on function public.passenger_submit_verification_document(text, text) from public, anon;
revoke execute on function public.admin_passenger_verification_settings_update(boolean, boolean, boolean) from public, anon;
revoke execute on function public.admin_passenger_verification_settings_get() from public, anon;
revoke execute on function public.admin_passenger_verification_documents_list(uuid) from public, anon;

grant execute on function public.passenger_verification_capture_enabled() to authenticated;
grant execute on function public.passenger_verification_state() to authenticated;
grant execute on function public.passenger_set_profile_photo(text) to authenticated;
grant execute on function public.passenger_submit_verification_document(text, text) to authenticated;
grant execute on function public.admin_passenger_verification_settings_update(boolean, boolean, boolean) to authenticated;
grant execute on function public.admin_passenger_verification_settings_get() to authenticated;
grant execute on function public.admin_passenger_verification_documents_list(uuid) to authenticated;
