-- Independent Preview and Production counters + prebuilt Production candidates.
-- Owner-confirmed Play Store baseline on 2026-10-06: production versionCode 131.
-- Preview build numbers remain independent (e.g. 163, 164, ...).

alter table public.build_jobs
  drop constraint if exists build_jobs_artifact_type_check;

alter table public.build_jobs
  add constraint build_jobs_artifact_type_check
  check (
    artifact_type = any (
      array[
        'apk','aab','apk+aab',
        'preview-apk','preview-apk+aab',
        'candidate-apk+aab',
        'ipa','web'
      ]::text[]
    )
  );

alter table public.build_jobs
  add column if not exists apk_sha256 text,
  add column if not exists aab_sha256 text;

alter table public.app_release_gate
  add column if not exists production_store_build_number integer,
  add column if not exists next_production_build_number integer,
  add column if not exists production_candidate_build_id uuid
    references public.build_jobs(id) on delete set null,
  add column if not exists production_candidate_commit_sha text,
  add column if not exists production_candidate_version_name text,
  add column if not exists production_candidate_build_number integer,
  add column if not exists production_candidate_ready_at timestamptz,
  add column if not exists production_candidate_promoted_at timestamptz;

update public.app_release_gate
set production_store_build_number = coalesce(production_store_build_number, 131),
    next_production_build_number = coalesce(next_production_build_number, 132),
    updated_at = now()
where platform = 'android';

create or replace function public.sync_app_release_gate_from_build()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_authoritative_preview boolean := false;
  v_candidate public.build_jobs%rowtype;
begin
  v_authoritative_preview :=
    new.platform = 'android'
    and new.artifact_type in ('preview-apk','preview-apk+aab')
    and new.status = 'ready'
    and new.commit_sha is not null
    and coalesce(new.apk_url, '') like
      'https://github.com/jorge2610g/Expressdelivery/releases/download/preview-shorebird-v%/app-release.apk';

  if v_authoritative_preview then
    select *
    into v_candidate
    from public.build_jobs
    where platform = 'android'
      and artifact_type = 'candidate-apk+aab'
      and status = 'ready'
      and commit_sha = new.commit_sha
      and version_name = new.version_name
    order by created_at desc
    limit 1;

    insert into public.app_release_gate(
      platform,
      preview_build_id,
      preview_base_commit_sha,
      preview_commit_sha,
      preview_version_name,
      preview_build_number,
      preview_ready_at,
      preview_patch_workflow_run_id,
      preview_patch_at,
      approved_preview_build_id,
      approved_commit_sha,
      approved_by,
      approved_at,
      qa_preview_build_id,
      qa_commit_sha,
      qa_workflow_run_id,
      qa_passed_at,
      production_candidate_build_id,
      production_candidate_commit_sha,
      production_candidate_version_name,
      production_candidate_build_number,
      production_candidate_ready_at,
      production_candidate_promoted_at,
      updated_at
    )
    values(
      'android',
      new.id,
      new.commit_sha,
      new.commit_sha,
      new.version_name,
      new.build_number,
      coalesce(new.completed_at, now()),
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      v_candidate.id,
      v_candidate.commit_sha,
      v_candidate.version_name,
      v_candidate.build_number,
      v_candidate.completed_at,
      null,
      now()
    )
    on conflict (platform) do update set
      preview_build_id = excluded.preview_build_id,
      preview_base_commit_sha = excluded.preview_base_commit_sha,
      preview_commit_sha = excluded.preview_commit_sha,
      preview_version_name = excluded.preview_version_name,
      preview_build_number = excluded.preview_build_number,
      preview_ready_at = excluded.preview_ready_at,
      preview_patch_workflow_run_id = null,
      preview_patch_at = null,
      approved_preview_build_id = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.approved_commit_sha = excluded.preview_commit_sha
        then public.app_release_gate.approved_preview_build_id else null end,
      approved_commit_sha = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.approved_commit_sha = excluded.preview_commit_sha
        then public.app_release_gate.approved_commit_sha else null end,
      approved_by = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.approved_commit_sha = excluded.preview_commit_sha
        then public.app_release_gate.approved_by else null end,
      approved_at = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.approved_commit_sha = excluded.preview_commit_sha
        then public.app_release_gate.approved_at else null end,
      qa_preview_build_id = case
        when public.app_release_gate.qa_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.qa_commit_sha = excluded.preview_commit_sha
        then public.app_release_gate.qa_preview_build_id else null end,
      qa_commit_sha = case
        when public.app_release_gate.qa_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.qa_commit_sha = excluded.preview_commit_sha
        then public.app_release_gate.qa_commit_sha else null end,
      qa_workflow_run_id = case
        when public.app_release_gate.qa_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.qa_commit_sha = excluded.preview_commit_sha
        then public.app_release_gate.qa_workflow_run_id else null end,
      qa_passed_at = case
        when public.app_release_gate.qa_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.qa_commit_sha = excluded.preview_commit_sha
        then public.app_release_gate.qa_passed_at else null end,
      production_candidate_build_id = case
        when excluded.production_candidate_build_id is not null
          then excluded.production_candidate_build_id
        when public.app_release_gate.production_candidate_commit_sha = excluded.preview_commit_sha
         and public.app_release_gate.production_candidate_version_name = excluded.preview_version_name
          then public.app_release_gate.production_candidate_build_id
        else null
      end,
      production_candidate_commit_sha = case
        when excluded.production_candidate_build_id is not null
          then excluded.production_candidate_commit_sha
        when public.app_release_gate.production_candidate_commit_sha = excluded.preview_commit_sha
         and public.app_release_gate.production_candidate_version_name = excluded.preview_version_name
          then public.app_release_gate.production_candidate_commit_sha
        else null
      end,
      production_candidate_version_name = case
        when excluded.production_candidate_build_id is not null
          then excluded.production_candidate_version_name
        when public.app_release_gate.production_candidate_commit_sha = excluded.preview_commit_sha
         and public.app_release_gate.production_candidate_version_name = excluded.preview_version_name
          then public.app_release_gate.production_candidate_version_name
        else null
      end,
      production_candidate_build_number = case
        when excluded.production_candidate_build_id is not null
          then excluded.production_candidate_build_number
        when public.app_release_gate.production_candidate_commit_sha = excluded.preview_commit_sha
         and public.app_release_gate.production_candidate_version_name = excluded.preview_version_name
          then public.app_release_gate.production_candidate_build_number
        else null
      end,
      production_candidate_ready_at = case
        when excluded.production_candidate_build_id is not null
          then excluded.production_candidate_ready_at
        when public.app_release_gate.production_candidate_commit_sha = excluded.preview_commit_sha
         and public.app_release_gate.production_candidate_version_name = excluded.preview_version_name
          then public.app_release_gate.production_candidate_ready_at
        else null
      end,
      production_candidate_promoted_at = case
        when public.app_release_gate.production_candidate_commit_sha = excluded.preview_commit_sha
         and public.app_release_gate.production_candidate_version_name = excluded.preview_version_name
          then public.app_release_gate.production_candidate_promoted_at
        else null
      end,
      updated_at = now()
    where public.app_release_gate.preview_build_number is null
       or excluded.preview_build_number >= public.app_release_gate.preview_build_number;
  end if;

  if new.platform = 'android'
     and new.artifact_type = 'candidate-apk+aab'
     and new.status = 'ready'
     and new.commit_sha is not null then
    update public.app_release_gate
    set production_candidate_build_id = new.id,
        production_candidate_commit_sha = new.commit_sha,
        production_candidate_version_name = new.version_name,
        production_candidate_build_number = new.build_number,
        production_candidate_ready_at = coalesce(new.completed_at, now()),
        production_candidate_promoted_at = null,
        updated_at = now()
    where platform = 'android'
      and preview_commit_sha = new.commit_sha
      and preview_version_name = new.version_name;
  end if;

  if new.platform = 'android'
     and new.artifact_type = 'apk+aab'
     and new.status = 'ready'
     and new.commit_sha is not null then
    insert into public.app_release_gate(
      platform,
      production_build_id,
      production_commit_sha,
      production_ready_at,
      production_candidate_promoted_at,
      next_production_build_number,
      updated_at
    )
    values(
      'android',
      new.id,
      new.commit_sha,
      coalesce(new.completed_at, now()),
      now(),
      new.build_number + 1,
      now()
    )
    on conflict (platform) do update set
      production_build_id = excluded.production_build_id,
      production_commit_sha = excluded.production_commit_sha,
      production_ready_at = excluded.production_ready_at,
      production_candidate_promoted_at = excluded.production_candidate_promoted_at,
      next_production_build_number = greatest(
        coalesce(public.app_release_gate.next_production_build_number, 1),
        excluded.next_production_build_number
      ),
      updated_at = now();
  end if;

  return new;
end;
$function$;

create or replace function public.enforce_android_production_build_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_gate public.app_release_gate%rowtype;
begin
  if new.platform <> 'android'
     or new.artifact_type <> 'apk+aab' then
    return new;
  end if;

  select * into v_gate
  from public.app_release_gate
  where platform = 'android';

  if not found
     or v_gate.qa_preview_build_id is null
     or v_gate.qa_preview_build_id is distinct from v_gate.preview_build_id
     or v_gate.qa_commit_sha is distinct from v_gate.preview_commit_sha
     or v_gate.qa_passed_at is null then
    raise exception 'Producción bloqueada: la Preview vigente no tiene QA certificado';
  end if;

  if v_gate.approved_preview_build_id is null
     or v_gate.approved_preview_build_id is distinct from v_gate.preview_build_id
     or v_gate.approved_commit_sha is distinct from v_gate.preview_commit_sha
     or v_gate.approved_commit_sha is null then
    raise exception 'Producción bloqueada: la Preview QA vigente no está aprobada';
  end if;

  if v_gate.production_candidate_build_id is null
     or v_gate.production_candidate_commit_sha is distinct from v_gate.preview_commit_sha
     or v_gate.production_candidate_version_name is distinct from v_gate.preview_version_name
     or v_gate.production_candidate_build_number is null then
    raise exception 'Producción bloqueada: no existe candidato APK+AAB del mismo SHA';
  end if;

  if new.version_name is distinct from v_gate.production_candidate_version_name
     or new.build_number is distinct from v_gate.production_candidate_build_number
     or new.commit_sha is distinct from v_gate.approved_commit_sha then
    raise exception
      'Producción bloqueada: debe promover el candidato exacto (versión %, producción build %, SHA %)',
      v_gate.production_candidate_version_name,
      v_gate.production_candidate_build_number,
      v_gate.approved_commit_sha;
  end if;

  return new;
end;
$function$;

create or replace function public.admin_create_build_job(
  p_platform text,
  p_artifact_type text,
  p_version_name text,
  p_build_number integer,
  p_changelog text,
  p_commit_sha text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_id uuid;
  v_commit_sha text := nullif(trim(coalesce(p_commit_sha,'')),'');
  v_gate public.app_release_gate%rowtype;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_platform = 'android'
     and p_artifact_type = 'candidate-apk+aab' then
    select * into v_gate
    from public.app_release_gate
    where platform = 'android';

    if not found
       or v_gate.preview_commit_sha is null
       or v_gate.preview_version_name is null then
      raise exception 'Primero debe existir una Preview Shorebird vigente';
    end if;

    if trim(p_version_name) is distinct from v_gate.preview_version_name then
      raise exception 'El candidato Producción debe usar la misma versión de producto que Preview (%)',
        v_gate.preview_version_name;
    end if;

    if p_build_number is distinct from v_gate.next_production_build_number then
      raise exception 'El siguiente build de Producción reservado es %',
        v_gate.next_production_build_number;
    end if;

    if v_commit_sha is not null
       and v_commit_sha <> v_gate.preview_commit_sha then
      raise exception 'El candidato Producción debe usar exactamente el SHA de Preview';
    end if;

    v_commit_sha := v_gate.preview_commit_sha;
  end if;

  if p_platform = 'android'
     and p_artifact_type = 'apk+aab' then
    raise exception
      'Producción ya no se recompila después de Preview. Usa admin_promote_production_candidate().';
  end if;

  insert into public.build_jobs(
    platform,
    artifact_type,
    version_name,
    build_number,
    changelog,
    commit_sha,
    created_by
  )
  values(
    p_platform,
    p_artifact_type,
    trim(p_version_name),
    p_build_number,
    p_changelog,
    v_commit_sha,
    auth.uid()
  )
  returning id into v_id;

  perform public.admin_log_action(
    'create',
    'build_job',
    v_id::text,
    jsonb_build_object(
      'platform',p_platform,
      'artifact_type',p_artifact_type,
      'version_name',p_version_name,
      'build_number',p_build_number,
      'commit_sha',v_commit_sha
    )
  );

  return v_id;
end;
$function$;

create or replace function public.admin_promote_production_candidate(
  p_candidate_build_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_candidate public.build_jobs%rowtype;
  v_gate public.app_release_gate%rowtype;
  v_production_id uuid;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select *
  into v_candidate
  from public.build_jobs
  where id = p_candidate_build_id;

  if not found
     or v_candidate.platform <> 'android'
     or v_candidate.artifact_type <> 'candidate-apk+aab'
     or v_candidate.status <> 'ready'
     or v_candidate.commit_sha is null
     or v_candidate.apk_url is null
     or v_candidate.aab_url is null then
    raise exception 'Candidato Producción inválido o incompleto';
  end if;

  select *
  into v_gate
  from public.app_release_gate
  where platform = 'android';

  if not found
     or v_gate.preview_build_id is null
     or v_gate.qa_preview_build_id is distinct from v_gate.preview_build_id
     or v_gate.qa_commit_sha is distinct from v_gate.preview_commit_sha
     or v_gate.qa_passed_at is null then
    raise exception 'La Preview vigente aún no tiene QA certificado';
  end if;

  if v_gate.approved_preview_build_id is distinct from v_gate.preview_build_id
     or v_gate.approved_commit_sha is distinct from v_gate.preview_commit_sha
     or v_gate.approved_commit_sha is null then
    raise exception 'La Preview vigente aún no está aprobada';
  end if;

  if v_gate.production_candidate_build_id is distinct from v_candidate.id
     or v_candidate.commit_sha is distinct from v_gate.approved_commit_sha
     or v_candidate.version_name is distinct from v_gate.preview_version_name
     or v_candidate.build_number is distinct from v_gate.production_candidate_build_number then
    raise exception 'El candidato no corresponde al Preview aprobado';
  end if;

  insert into public.build_jobs(
    platform,
    artifact_type,
    version_name,
    build_number,
    status,
    changelog,
    commit_sha,
    workflow_run_id,
    artifact_url,
    created_by,
    created_at,
    updated_at,
    completed_at,
    apk_url,
    aab_url,
    run_url,
    error_message,
    signing_mode,
    started_at,
    apk_sha256,
    aab_sha256
  )
  values(
    'android',
    'apk+aab',
    v_candidate.version_name,
    v_candidate.build_number,
    'ready',
    'Promoción sin recompilar del candidato Producción validado por Preview/QA.',
    v_candidate.commit_sha,
    v_candidate.workflow_run_id,
    v_candidate.artifact_url,
    auth.uid(),
    now(),
    now(),
    now(),
    v_candidate.apk_url,
    v_candidate.aab_url,
    v_candidate.run_url,
    null,
    v_candidate.signing_mode,
    v_candidate.started_at,
    v_candidate.apk_sha256,
    v_candidate.aab_sha256
  )
  returning id into v_production_id;

  update public.app_release_gate
  set production_candidate_promoted_at = now(),
      updated_at = now()
  where platform = 'android';

  perform public.admin_log_action(
    'promote',
    'production_candidate',
    p_candidate_build_id::text,
    jsonb_build_object(
      'production_build_id', v_production_id,
      'version_name', v_candidate.version_name,
      'production_build_number', v_candidate.build_number,
      'preview_build_number', v_gate.preview_build_number,
      'commit_sha', v_candidate.commit_sha
    )
  );

  return public.admin_release_gate_status('android');
end;
$function$;

grant execute on function public.admin_promote_production_candidate(uuid)
to authenticated;

create or replace function public.admin_release_gate_status(
  p_platform text default 'android'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_row public.app_release_gate%rowtype;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select *
  into v_row
  from public.app_release_gate
  where platform = p_platform;

  if not found then
    return jsonb_build_object(
      'platform',p_platform,
      'preview_build_id',null,
      'preview_commit_sha',null,
      'preview_version_name',null,
      'preview_build_number',null,
      'preview_ready_at',null,
      'approved_preview_build_id',null,
      'approved_commit_sha',null,
      'approved_at',null,
      'qa_preview_build_id',null,
      'qa_commit_sha',null,
      'qa_workflow_run_id',null,
      'qa_passed_at',null,
      'production_store_build_number',null,
      'next_production_build_number',null,
      'production_candidate_build_id',null,
      'production_candidate_commit_sha',null,
      'production_candidate_version_name',null,
      'production_candidate_build_number',null,
      'production_candidate_ready_at',null,
      'production_candidate_promoted_at',null,
      'production_build_id',null,
      'production_commit_sha',null,
      'production_ready_at',null,
      'preview_qa_certified',false,
      'preview_approved',false,
      'production_candidate_ready',false
    );
  end if;

  return to_jsonb(v_row) || jsonb_build_object(
    'preview_qa_certified',
      v_row.qa_preview_build_id is not null
      and v_row.qa_preview_build_id = v_row.preview_build_id
      and v_row.qa_commit_sha = v_row.preview_commit_sha
      and v_row.qa_passed_at is not null,
    'preview_approved',
      v_row.approved_preview_build_id is not null
      and v_row.approved_preview_build_id = v_row.preview_build_id
      and v_row.approved_commit_sha = v_row.preview_commit_sha,
    'production_candidate_ready',
      v_row.production_candidate_build_id is not null
      and v_row.production_candidate_commit_sha = v_row.preview_commit_sha
      and v_row.production_candidate_version_name = v_row.preview_version_name
      and v_row.production_candidate_build_number is not null
      and v_row.production_candidate_ready_at is not null
  );
end;
$function$;

revoke all on function public.enforce_android_production_build_identity()
from public, anon, authenticated;
