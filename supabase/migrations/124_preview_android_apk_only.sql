-- Preview Android releases are APK-only. Production remains APK + AAB.

alter table public.build_jobs
  drop constraint if exists build_jobs_artifact_type_check;

alter table public.build_jobs
  add constraint build_jobs_artifact_type_check
  check (
    artifact_type = any (
      array[
        'apk'::text,
        'aab'::text,
        'apk+aab'::text,
        'preview-apk'::text,
        'preview-apk+aab'::text,
        'ipa'::text,
        'web'::text
      ]
    )
  );

create or replace function public.sync_app_release_gate_from_build()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.platform = 'android'
     and new.artifact_type in ('preview-apk','preview-apk+aab')
     and new.status = 'ready'
     and new.commit_sha is not null then
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
     or v_build.artifact_type not in ('preview-apk','preview-apk+aab')
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
     or v_gate.preview_version_name is distinct from v_build.version_name
     or v_gate.preview_build_number is distinct from v_build.build_number
     or v_gate.preview_commit_sha is null then
    raise exception
      'Solo puedes aprobar la Preview vigente. El build seleccionado ya fue reemplazado por una versión más nueva';
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
      'current_preview_only',true,
      'shorebird_patch',v_gate.preview_commit_sha is distinct from v_build.commit_sha
    )
  );

  return public.admin_release_gate_status('android');
end;
$function$;
