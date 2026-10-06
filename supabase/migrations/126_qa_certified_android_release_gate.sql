-- QA-certified Android promotion gate.
-- Only the published Shorebird Preview is authoritative.
-- Production requires the exact Preview SHA/build to pass mandatory QA before approval.

alter table public.app_release_gate
  add column if not exists qa_preview_build_id uuid references public.build_jobs(id) on delete set null,
  add column if not exists qa_commit_sha text,
  add column if not exists qa_workflow_run_id text,
  add column if not exists qa_passed_at timestamptz;

create or replace function public.sync_app_release_gate_from_build()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_authoritative_preview boolean := false;
begin
  v_authoritative_preview :=
    new.platform = 'android'
    and new.artifact_type in ('preview-apk','preview-apk+aab')
    and new.status = 'ready'
    and new.commit_sha is not null
    and coalesce(new.apk_url, '') like
      'https://github.com/jorge2610g/Expressdelivery/releases/download/preview-shorebird-v%/app-release.apk';

  if v_authoritative_preview then
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
          then public.app_release_gate.approved_preview_build_id
        else null
      end,
      approved_commit_sha = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.approved_commit_sha = excluded.preview_commit_sha
          then public.app_release_gate.approved_commit_sha
        else null
      end,
      approved_by = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.approved_commit_sha = excluded.preview_commit_sha
          then public.app_release_gate.approved_by
        else null
      end,
      approved_at = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.approved_commit_sha = excluded.preview_commit_sha
          then public.app_release_gate.approved_at
        else null
      end,
      qa_preview_build_id = case
        when public.app_release_gate.qa_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.qa_commit_sha = excluded.preview_commit_sha
          then public.app_release_gate.qa_preview_build_id
        else null
      end,
      qa_commit_sha = case
        when public.app_release_gate.qa_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.qa_commit_sha = excluded.preview_commit_sha
          then public.app_release_gate.qa_commit_sha
        else null
      end,
      qa_workflow_run_id = case
        when public.app_release_gate.qa_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.qa_commit_sha = excluded.preview_commit_sha
          then public.app_release_gate.qa_workflow_run_id
        else null
      end,
      qa_passed_at = case
        when public.app_release_gate.qa_preview_build_id = excluded.preview_build_id
         and public.app_release_gate.qa_commit_sha = excluded.preview_commit_sha
          then public.app_release_gate.qa_passed_at
        else null
      end,
      updated_at = now()
    where public.app_release_gate.preview_build_number is null
       or excluded.preview_build_number >= public.app_release_gate.preview_build_number;
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
      updated_at
    )
    values(
      'android',
      new.id,
      new.commit_sha,
      coalesce(new.completed_at, now()),
      now()
    )
    on conflict (platform) do update set
      production_build_id = excluded.production_build_id,
      production_commit_sha = excluded.production_commit_sha,
      production_ready_at = excluded.production_ready_at,
      updated_at = now();
  end if;

  return new;
end;
$function$;

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
      'production_build_id',null,
      'production_commit_sha',null,
      'production_ready_at',null,
      'preview_qa_certified',false,
      'preview_approved',false
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
      and v_row.approved_commit_sha = v_row.preview_commit_sha
  );
end;
$function$;

create or replace function public.admin_approve_preview_build(
  p_build_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_build public.build_jobs%rowtype;
  v_gate public.app_release_gate%rowtype;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select * into v_build
  from public.build_jobs
  where id = p_build_id;

  if not found then
    raise exception 'Build Preview no encontrado';
  end if;

  if v_build.platform <> 'android'
     or v_build.artifact_type not in ('preview-apk','preview-apk+aab')
     or v_build.status <> 'ready'
     or v_build.commit_sha is null then
    raise exception 'Solo puedes aprobar una Preview Android terminada y con SHA registrado';
  end if;

  select * into v_gate
  from public.app_release_gate
  where platform = 'android';

  if not found
     or v_gate.preview_build_id is distinct from v_build.id
     or v_gate.preview_version_name is distinct from v_build.version_name
     or v_gate.preview_build_number is distinct from v_build.build_number
     or v_gate.preview_commit_sha is null then
    raise exception 'Solo puedes aprobar la Preview Shorebird vigente';
  end if;

  if v_gate.qa_preview_build_id is distinct from v_build.id
     or v_gate.qa_commit_sha is distinct from v_gate.preview_commit_sha
     or v_gate.qa_passed_at is null then
    raise exception 'Preview bloqueada: QA obligatorio todavía no certificó este build/SHA';
  end if;

  update public.app_release_gate
  set approved_preview_build_id = v_build.id,
      approved_commit_sha = v_gate.preview_commit_sha,
      approved_by = auth.uid(),
      approved_at = now(),
      updated_at = now()
  where platform = 'android';

  perform public.admin_log_action(
    'approve',
    'preview_build',
    v_build.id::text,
    jsonb_build_object(
      'base_commit_sha',v_build.commit_sha,
      'approved_commit_sha',v_gate.preview_commit_sha,
      'version_name',v_build.version_name,
      'build_number',v_build.build_number,
      'qa_workflow_run_id',v_gate.qa_workflow_run_id,
      'qa_passed_at',v_gate.qa_passed_at
    )
  );

  return public.admin_release_gate_status('android');
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

  if p_platform = 'android' and p_artifact_type = 'apk+aab' then
    select * into v_gate
    from public.app_release_gate
    where platform='android';

    if not found
       or v_gate.qa_preview_build_id is null
       or v_gate.qa_preview_build_id is distinct from v_gate.preview_build_id
       or v_gate.qa_commit_sha is distinct from v_gate.preview_commit_sha
       or v_gate.qa_passed_at is null then
      raise exception 'Primero debe pasar QA obligatorio la Preview Shorebird vigente';
    end if;

    if v_gate.approved_preview_build_id is null
       or v_gate.approved_preview_build_id is distinct from v_gate.preview_build_id
       or v_gate.approved_commit_sha is distinct from v_gate.preview_commit_sha
       or v_gate.approved_commit_sha is null then
      raise exception 'Primero debes aprobar la Preview vigente después de QA';
    end if;

    if trim(p_version_name) is distinct from v_gate.preview_version_name then
      raise exception 'Producción debe usar exactamente la versión de Preview aprobada (%)', v_gate.preview_version_name;
    end if;
    if p_build_number is distinct from v_gate.preview_build_number then
      raise exception 'Producción debe usar exactamente el build de Preview aprobada (%)', v_gate.preview_build_number;
    end if;
    if v_commit_sha is not null and v_commit_sha <> v_gate.approved_commit_sha then
      raise exception 'Producción debe usar exactamente el SHA aprobado y certificado por QA';
    end if;
    v_commit_sha := v_gate.approved_commit_sha;
  end if;

  insert into public.build_jobs(
    platform,artifact_type,version_name,build_number,changelog,commit_sha,created_by
  )
  values(
    p_platform,p_artifact_type,trim(p_version_name),p_build_number,p_changelog,v_commit_sha,auth.uid()
  )
  returning id into v_id;

  perform public.admin_log_action(
    'create','build_job',v_id::text,
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

create or replace function public.enforce_android_production_build_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_gate public.app_release_gate%rowtype;
begin
  if new.platform <> 'android' or new.artifact_type <> 'apk+aab' then
    return new;
  end if;

  select * into v_gate
  from public.app_release_gate
  where platform='android';

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

  if new.version_name is distinct from v_gate.preview_version_name
     or new.build_number is distinct from v_gate.preview_build_number
     or new.commit_sha is distinct from v_gate.approved_commit_sha then
    raise exception
      'Producción bloqueada: debe ser copia exacta de Preview QA (versión %, build %, SHA %)',
      v_gate.preview_version_name,
      v_gate.preview_build_number,
      v_gate.approved_commit_sha;
  end if;

  return new;
end;
$function$;

-- Existing approvals predate the hard QA certificate and are intentionally
-- invalidated. A new Production build now requires a fresh QA pass.
update public.app_release_gate
set approved_preview_build_id = null,
    approved_commit_sha = null,
    approved_by = null,
    approved_at = null,
    qa_preview_build_id = null,
    qa_commit_sha = null,
    qa_workflow_run_id = null,
    qa_passed_at = null,
    updated_at = now()
where platform = 'android';

revoke all on function public.enforce_android_production_build_identity()
from public,anon,authenticated;
