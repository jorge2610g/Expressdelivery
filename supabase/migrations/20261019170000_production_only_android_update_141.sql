-- Express: Production-only update distribution, validated against Google Play.
-- Verification source (read-only): GitHub Actions 39272558550, 2026-10-19:
-- com.express.usuario1, track=production, status=completed, versionCode=141.
-- Official signed AAB SHA256: 505364b1baa29c91cb5616b9d8f9f73173352836eaf31f4559a9f73c45278843
-- No update notice is enabled here: the admin must turn it on explicitly.
-- Applies on top of the previously deployed 20261019150000 baseline.

alter table public.app_release_gate
  add column if not exists production_verified_build_job_id uuid
  references public.build_jobs(id) on delete set null;

-- Synchronize metadata ONLY after the independent Play API check above.
-- Reject drift or incorrect signed job instead of silently trusting build 141.
do $sync$
declare
  v_verified_id uuid := '470dc53d-eeef-4acd-bbf9-b226344c043b'::uuid;
  v_count integer;
begin
  if not exists (
    select 1 from public.build_jobs
    where id=v_verified_id and platform='android'
      and artifact_type='aab' and status='ready'
      and signing_mode='production'
      and version_name='1.6.3' and build_number=141
      and commit_sha='545b03339b69fc8b89f53f9aec43855772e404a5'
      and aab_sha256='505364b1baa29c91cb5616b9d8f9f73173352836eaf31f4559a9f73c45278843'
      and aab_url is not null
  ) then
    raise exception 'No existe el AAB oficial Build 141 verificado para Producción';
  end if;
  update public.app_release_gate
    set production_store_build_number=141,
        next_production_build_number=greatest(
          coalesce(next_production_build_number, 0), 142),
        production_verified_build_job_id=v_verified_id,
        updated_at=now()
    where platform='android' and production_store_build_number in (140,141)
      and (production_verified_build_job_id is null
        or production_verified_build_job_id=v_verified_id);
  get diagnostics v_count=row_count;
  if v_count<>1 then
    raise exception 'El registro de Producción cambió: sincronización cancelada';
  end if;
end;
$sync$;

-- Preserve the existing admin release status contract and include the
-- verified Production build identity so unrelated QA artifacts cannot be chosen.
create or replace function public.admin_single_app_release_status()
returns jsonb language plpgsql stable security definer
set search_path = public
as $func$
declare
  v_gate public.app_release_gate%rowtype;
  v_job public.build_jobs%rowtype;
  v_cert public.android_single_app_candidates%rowtype;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  select * into v_gate from public.app_release_gate
    where platform='android';
  select * into v_job from public.build_jobs
    where platform='android' and artifact_type='single-app-candidate-apk+aab'
    order by created_at desc limit 1;
  if found then
    select * into v_cert from public.android_single_app_candidates
      where candidate_build_id=v_job.id;
  end if;
  return jsonb_build_object(
    'release_mode','single_app','preview_apk_required',false,
    'next_google_play_build',v_gate.next_production_build_number,
    'production_store_build',v_gate.production_store_build_number,
    'production_verified_build_job_id',v_gate.production_verified_build_job_id,
    'candidate',case when v_job.id is null then null else to_jsonb(v_job) end,
    'verification',case when v_cert.candidate_build_id is null
      then null else to_jsonb(v_cert) end,
    'qa_certified',v_cert.qa_verified_at is not null,
    'approved',v_cert.approved_at is not null,
    'promoted',v_cert.promoted_build_id is not null
  );
end;
$func$;

-- The Admin's distribution screen is now Production-only. Retain the same
-- RPC parameter list for compatibility, but reject 'internal' at the server.
create or replace function public.admin_save_android_update_distribution(
  p_build_id uuid,
  p_channel text,
  p_is_current boolean default false,
  p_is_critical boolean default false,
  p_notes text default '',
  p_play_store_url text default null,
  p_confirmed_in_play boolean default false,
  p_confirmed_critical boolean default false
)
returns jsonb language plpgsql security definer
set search_path = public
as $func$
declare
  v_job public.build_jobs%rowtype;
  v_distribution_id uuid;
  v_release_id uuid;
  v_store_build integer;
  v_verified_job_id uuid;
  v_current boolean := coalesce(p_is_current, false);
  v_critical boolean := coalesce(p_is_critical, false);
  v_notes text := trim(coalesce(p_notes, ''));
  v_url text := coalesce(nullif(trim(p_play_store_url), ''),
    'https://play.google.com/store/apps/details?id=com.express.usuario1');
begin
  perform public.admin_assert_environment('production');
  if auth.uid() is null or not public.is_admin() then
    raise exception 'No autorizado para gestionar avisos de Producción';
  end if;
  if p_channel is distinct from 'production' then
    raise exception 'Distribución únicamente para Producción';
  end if;
  if v_critical and not v_current then
    raise exception 'Una actualización crítica exige activar Versión actual';
  end if;
  if length(v_notes)>800 then
    raise exception 'Las notas pueden contener como máximo 800 caracteres';
  end if;
  if v_url !~ '^https://play[.]google[.]com/store/apps/details[?]id=com[.]express[.]usuario1(&[^#[:space:]]*)?$' then
    raise exception 'Utiliza solamente el enlace oficial de Express en Google Play';
  end if;

  select * into v_job from public.build_jobs b
    where b.id=p_build_id for share;
  if not found or v_job.platform is distinct from 'android'
    or v_job.status is distinct from 'ready'
    or v_job.signing_mode is distinct from 'production'
    or v_job.aab_url is null
    or v_job.artifact_type not in (
      'aab','single-app-candidate-apk+aab','candidate-apk+aab','apk+aab'
    ) then
    raise exception 'Se requiere un AAB Android oficial, listo y firmado';
  end if;

  select g.production_store_build_number,
    g.production_verified_build_job_id
  into v_store_build,v_verified_job_id
  from public.app_release_gate g
  where g.platform='android' for share;
  if v_store_build is null or v_verified_job_id is null
    or v_job.build_number<>v_store_build
    or v_job.id<>v_verified_job_id then
    raise exception 'Solo se permite la versión y AAB exactos verificados en Google Play Producción';
  end if;
  if v_current and not coalesce(p_confirmed_in_play,false) then
    raise exception 'Confirma la disponibilidad del Build en Play Producción';
  end if;
  if v_critical and not coalesce(p_confirmed_critical,false) then
    raise exception 'La actualización crítica requiere confirmación adicional';
  end if;

  insert into public.app_update_distributions (
    build_job_id,channel,version_name,build_number,
    is_current,is_critical,notes,play_store_url,changed_by,updated_at
  ) values (
    v_job.id,'production',v_job.version_name,v_job.build_number,
    v_current,v_critical,v_notes,v_url,auth.uid(),now()
  ) on conflict(build_job_id,channel) do update set
    version_name=excluded.version_name,
    build_number=excluded.build_number,
    is_current=excluded.is_current,
    is_critical=excluded.is_critical,
    notes=excluded.notes,
    play_store_url=excluded.play_store_url,
    changed_by=excluded.changed_by,
    updated_at=now()
  returning id into v_distribution_id;

  if v_current then
    -- Existing app update code reads only app_releases; signed AAB-only
    -- publication is valid (Google Play generates installable APKs).
    insert into public.app_releases (
      platform,version_name,build_number,apk_url,aab_url,
      play_store_url,changelog,mandatory,status,
      build_job_id,published_by,published_at,updated_at
    ) values (
      'android',v_job.version_name,v_job.build_number,
      v_job.apk_url,v_job.aab_url,v_url,v_notes,v_critical,
      'published',v_job.id,auth.uid(),now(),now()
    ) on conflict(platform,build_number) do update set
      version_name=excluded.version_name,
      apk_url=excluded.apk_url,
      aab_url=excluded.aab_url,
      play_store_url=excluded.play_store_url,
      changelog=excluded.changelog,
      mandatory=excluded.mandatory,
      status='published',
      build_job_id=excluded.build_job_id,
      published_by=excluded.published_by,
      published_at=now(),
      updated_at=now()
    returning id into v_release_id;
    update public.app_releases
      set status='disabled',updated_at=now()
    where platform='android' and status='published'
      and id<>v_release_id;
  else
    update public.app_releases
      set status='disabled',updated_at=now()
    where platform='android' and build_number=v_job.build_number
      and status='published';
  end if;

  perform public.admin_log_action(
    'update','app_update_distribution',v_distribution_id::text,
    jsonb_build_object(
      'build_job_id',v_job.id,'channel','production',
      'version_name',v_job.version_name,'build_number',v_job.build_number,
      'is_current',v_current,'is_critical',v_critical
    )
  );
  return jsonb_build_object(
    'id',v_distribution_id,'build_job_id',v_job.id,
    'channel','production','version_name',v_job.version_name,
    'build_number',v_job.build_number,
    'is_current',v_current,'is_critical',v_critical,
    'notes',v_notes,'play_store_url',v_url,
    'in_app_notice_active',v_current
  );
end;
$func$;

-- Only a production administrator sees the update-distribution rows.
create or replace function public.admin_android_update_distributions()
returns jsonb language plpgsql security definer
set search_path = public
as $func$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Solo el administrador autorizado puede consultar distribuciones';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(d) order by d.updated_at desc),'[]'::jsonb)
    from public.app_update_distributions d
    where d.channel='production'
  );
end;
$func$;
