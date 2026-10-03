-- Preview approval gate: production Android builds must compile the exact
-- commit that was tested and approved in Express Preview.

create table if not exists public.app_release_gate (
  platform text primary key check (platform in ('android','ios','web')),
  preview_build_id uuid references public.build_jobs(id) on delete set null,
  preview_commit_sha text,
  preview_version_name text,
  preview_build_number integer,
  preview_ready_at timestamptz,
  approved_preview_build_id uuid references public.build_jobs(id) on delete set null,
  approved_commit_sha text,
  approved_by uuid references public.users(id) on delete set null,
  approved_at timestamptz,
  production_build_id uuid references public.build_jobs(id) on delete set null,
  production_commit_sha text,
  production_ready_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.app_release_gate enable row level security;

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
      updated_at = now();
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

drop trigger if exists trg_sync_app_release_gate_from_build on public.build_jobs;
create trigger trg_sync_app_release_gate_from_build
after insert or update of status, commit_sha, completed_at on public.build_jobs
for each row
execute function public.sync_app_release_gate_from_build();

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
      'production_build_id',null,
      'production_commit_sha',null,
      'production_ready_at',null,
      'preview_approved',false
    );
  end if;

  return to_jsonb(v_row) || jsonb_build_object(
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
    v_build.id,
    v_build.commit_sha,
    v_build.version_name,
    v_build.build_number,
    coalesce(v_build.completed_at, now()),
    v_build.id,
    v_build.commit_sha,
    auth.uid(),
    now(),
    now()
  )
  on conflict (platform) do update set
    preview_build_id = excluded.preview_build_id,
    preview_commit_sha = excluded.preview_commit_sha,
    preview_version_name = excluded.preview_version_name,
    preview_build_number = excluded.preview_build_number,
    preview_ready_at = excluded.preview_ready_at,
    approved_preview_build_id = excluded.approved_preview_build_id,
    approved_commit_sha = excluded.approved_commit_sha,
    approved_by = excluded.approved_by,
    approved_at = excluded.approved_at,
    updated_at = now();

  perform public.admin_log_action(
    'approve',
    'preview_build',
    v_build.id::text,
    jsonb_build_object(
      'commit_sha',v_build.commit_sha,
      'version_name',v_build.version_name,
      'build_number',v_build.build_number
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
  v_approved_sha text;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_platform = 'android' and p_artifact_type = 'apk+aab' then
    select approved_commit_sha
    into v_approved_sha
    from public.app_release_gate
    where platform='android'
      and approved_preview_build_id = preview_build_id
      and approved_commit_sha = preview_commit_sha
      and approved_commit_sha is not null;

    if v_approved_sha is null then
      raise exception 'Primero debes compilar y aprobar una Preview antes de crear Producción';
    end if;

    if v_commit_sha is not null and v_commit_sha <> v_approved_sha then
      raise exception 'Producción debe usar exactamente el SHA aprobado en Preview';
    end if;

    v_commit_sha := v_approved_sha;
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

revoke all on function public.admin_release_gate_status(text) from public, anon;
revoke all on function public.admin_approve_preview_build(uuid) from public, anon;
revoke all on function public.admin_create_build_job(text,text,text,integer,text,text) from public, anon;
grant execute on function public.admin_release_gate_status(text) to authenticated;
grant execute on function public.admin_approve_preview_build(uuid) to authenticated;
grant execute on function public.admin_create_build_job(text,text,text,integer,text,text) to authenticated;
