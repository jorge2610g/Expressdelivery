-- Release identity hardening.
-- Rules:
-- 1) The current Preview may never regress to an older build when builds finish out of order.
-- 2) Only the current Preview can be approved.
-- 3) Production must match the approved current Preview in SHA + version + build.
-- 4) Direct inserts cannot bypass the same identity gate.

create or replace function public.sync_app_release_gate_from_build()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.platform = 'android'
     and new.artifact_type = 'preview-apk+aab'
     and new.status = 'ready'
     and new.commit_sha is not null then
    insert into public.app_release_gate(
      platform,
      preview_build_id,
      preview_commit_sha,
      preview_version_name,
      preview_build_number,
      preview_ready_at,
      approved_preview_build_id,
      approved_commit_sha,
      approved_by,
      approved_at,
      updated_at
    )
    values(
      'android',
      new.id,
      new.commit_sha,
      new.version_name,
      new.build_number,
      coalesce(new.completed_at, now()),
      null,
      null,
      null,
      null,
      now()
    )
    on conflict (platform) do update set
      preview_build_id = excluded.preview_build_id,
      preview_commit_sha = excluded.preview_commit_sha,
      preview_version_name = excluded.preview_version_name,
      preview_build_number = excluded.preview_build_number,
      preview_ready_at = excluded.preview_ready_at,
      approved_preview_build_id = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
          then public.app_release_gate.approved_preview_build_id
        else null
      end,
      approved_commit_sha = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
          then public.app_release_gate.approved_commit_sha
        else null
      end,
      approved_by = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
          then public.app_release_gate.approved_by
        else null
      end,
      approved_at = case
        when public.app_release_gate.approved_preview_build_id = excluded.preview_build_id
          then public.app_release_gate.approved_at
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

  select *
  into v_build
  from public.build_jobs
  where id = p_build_id;

  if not found then
    raise exception 'Build Preview no encontrado';
  end if;

  if v_build.platform <> 'android'
     or v_build.artifact_type <> 'preview-apk+aab'
     or v_build.status <> 'ready'
     or v_build.commit_sha is null then
    raise exception 'Solo puedes aprobar una Preview Android terminada y con SHA registrado';
  end if;

  select *
  into v_gate
  from public.app_release_gate
  where platform = 'android';

  if not found
     or v_gate.preview_build_id is distinct from v_build.id
     or v_gate.preview_commit_sha is distinct from v_build.commit_sha
     or v_gate.preview_version_name is distinct from v_build.version_name
     or v_gate.preview_build_number is distinct from v_build.build_number then
    raise exception
      'Solo puedes aprobar la Preview vigente. El build seleccionado ya fue reemplazado por una versión más nueva';
  end if;

  update public.app_release_gate
  set approved_preview_build_id = v_build.id,
      approved_commit_sha = v_build.commit_sha,
      approved_by = auth.uid(),
      approved_at = now(),
      updated_at = now()
  where platform = 'android';

  perform public.admin_log_action(
    'approve',
    'preview_build',
    v_build.id::text,
    jsonb_build_object(
      'commit_sha',v_build.commit_sha,
      'version_name',v_build.version_name,
      'build_number',v_build.build_number,
      'current_preview_only',true
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
    select *
    into v_gate
    from public.app_release_gate
    where platform='android';

    if not found
       or v_gate.approved_preview_build_id is null
       or v_gate.approved_preview_build_id is distinct from v_gate.preview_build_id
       or v_gate.approved_commit_sha is distinct from v_gate.preview_commit_sha
       or v_gate.approved_commit_sha is null then
      raise exception 'Primero debes compilar y aprobar la Preview vigente antes de crear Producción';
    end if;

    if trim(p_version_name) is distinct from v_gate.preview_version_name then
      raise exception
        'Producción debe usar exactamente la misma versión de la Preview aprobada (%).',
        v_gate.preview_version_name;
    end if;

    if p_build_number is distinct from v_gate.preview_build_number then
      raise exception
        'Producción debe usar exactamente el mismo build de la Preview aprobada (%).',
        v_gate.preview_build_number;
    end if;

    if v_commit_sha is not null and v_commit_sha <> v_gate.approved_commit_sha then
      raise exception 'Producción debe usar exactamente el SHA aprobado en Preview';
    end if;

    v_commit_sha := v_gate.approved_commit_sha;
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

  select *
  into v_gate
  from public.app_release_gate
  where platform='android';

  if not found
     or v_gate.approved_preview_build_id is null
     or v_gate.approved_preview_build_id is distinct from v_gate.preview_build_id
     or v_gate.approved_commit_sha is distinct from v_gate.preview_commit_sha
     or v_gate.approved_commit_sha is null then
    raise exception 'Producción bloqueada: no existe una Preview vigente aprobada';
  end if;

  if new.version_name is distinct from v_gate.preview_version_name
     or new.build_number is distinct from v_gate.preview_build_number
     or new.commit_sha is distinct from v_gate.approved_commit_sha then
    raise exception
      'Producción bloqueada: debe ser copia exacta de Preview (versión %, build %, SHA %)',
      v_gate.preview_version_name,
      v_gate.preview_build_number,
      v_gate.approved_commit_sha;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_enforce_android_production_build_identity
on public.build_jobs;

create trigger trg_enforce_android_production_build_identity
before insert or update of platform,artifact_type,version_name,build_number,commit_sha
on public.build_jobs
for each row
execute function public.enforce_android_production_build_identity();

revoke all on function public.enforce_android_production_build_identity()
from public,anon,authenticated;
