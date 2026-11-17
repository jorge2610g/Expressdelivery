-- La foto de perfil del pasajero se pide una vez por día (hora de La Paz), al
-- pedir un viaje. Aditiva: añade la fecha de la última foto y reemplaza las
-- funciones de estado y de guardado de foto. No toca el carnet ni la selfie.

alter table public.users add column if not exists profile_photo_taken_at timestamptz;

create or replace function public.passenger_set_profile_photo(p_object_path text)
returns jsonb
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_uid uuid := auth.uid();
  v_path text := btrim(coalesce(p_object_path, ''));
  v_now timestamptz := now();
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
      profile_photo_taken_at = v_now,
      updated_at = v_now
  where id = v_uid;

  return jsonb_build_object(
    'profile_photo_path', v_path,
    'profile_photo_taken_at', v_now
  );
end;
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
  v_taken_at timestamptz;
  v_day_start timestamptz;
  v_submitted jsonb;
begin
  if v_uid is null then
    raise exception 'No autenticado';
  end if;

  select * into v_settings
  from public.passenger_verification_settings
  where id = true;

  select u.profile_photo_taken_at into v_taken_at
  from public.users u
  where u.id = v_uid;

  -- Inicio del día actual en La Paz (UTC−4, sin horario de verano).
  v_day_start := date_trunc('day', now() at time zone 'America/La_Paz') at time zone 'America/La_Paz';

  select coalesce(jsonb_agg(d.document_type order by d.created_at desc), '[]'::jsonb)
  into v_submitted
  from public.passenger_verification_documents d
  where d.user_id = v_uid;

  return jsonb_build_object(
    'profile_photo_required', v_settings.profile_photo_required,
    'identity_document_required', v_settings.identity_document_required,
    'face_selfie_required', v_settings.face_selfie_required,
    'profile_photo_taken_today', coalesce(v_taken_at >= v_day_start, false),
    'has_profile_photo', v_taken_at is not null,
    'submitted_documents', v_submitted
  );
end;
$$;

revoke execute on function public.passenger_set_profile_photo(text) from public, anon;
revoke execute on function public.passenger_verification_state() from public, anon;
grant execute on function public.passenger_set_profile_photo(text) to authenticated;
grant execute on function public.passenger_verification_state() to authenticated;
