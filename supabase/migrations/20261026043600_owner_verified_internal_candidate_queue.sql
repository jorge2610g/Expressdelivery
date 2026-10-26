-- Queue the next official Android candidate from an owner-authenticated
-- GitHub Actions request. The Edge Function verifies GitHub OIDC before it
-- calls this service-role-only RPC; regular users and authenticated clients
-- cannot enqueue builds through this route.

create or replace function public.queue_android_internal_candidate_v1(
  p_created_by uuid,
  p_version_name text,
  p_build_number integer,
  p_source_sha text,
  p_changelog text default null
)
returns public.build_jobs
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_gate public.app_release_gate%rowtype;
  v_existing public.build_jobs%rowtype;
  v_job public.build_jobs%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Solo el worker Android puede crear una candidata interna directa';
  end if;
  if p_created_by is null or not exists (
    select 1
    from public.admin_users a
    join public.users u on u.id = a.user_id
    where a.user_id = p_created_by
      and a.access_role = 'super_admin'
      and a.active = true
      and a.allow_production = true
      and u.account_status = 'active'
  ) then
    raise exception 'El solicitante no es un superadministrador activo autorizado';
  end if;
  if coalesce(trim(p_version_name), '') !~ '^[0-9]+[.][0-9]+[.][0-9]+$'
     or coalesce(p_build_number, 0) <= 0
     or coalesce(trim(p_source_sha), '') !~ '^[0-9a-f]{40}$' then
    raise exception 'La versión, el código o la fuente solicitada no es válida';
  end if;

  select * into v_gate
  from public.app_release_gate
  where platform = 'android'
  for update;
  if not found
     or v_gate.production_store_build_number is null
     or v_gate.next_production_build_number < v_gate.production_store_build_number + 1
     or p_build_number is distinct from v_gate.next_production_build_number then
    raise exception 'Build interno bloqueado: el código no es el siguiente reservado';
  end if;

  select * into v_existing
  from public.build_jobs j
  where j.platform = 'android'
    and j.artifact_type = 'single-app-candidate-apk+aab'
    and j.build_number = p_build_number
    and j.status in ('queued', 'building', 'ready')
  order by j.created_at desc
  limit 1
  for update;
  if found then
    if v_existing.version_name = trim(p_version_name)
       and v_existing.commit_sha = lower(trim(p_source_sha))
       and v_existing.created_by = p_created_by then
      return v_existing;
    end if;
    raise exception 'Ya existe una candidata activa con este código de Play';
  end if;

  insert into public.build_jobs(
    platform, artifact_type, version_name, build_number, created_by,
    commit_sha, changelog, status
  ) values (
    'android', 'single-app-candidate-apk+aab', trim(p_version_name),
    p_build_number, p_created_by, lower(trim(p_source_sha)),
    coalesce(p_changelog, 'Express Android · candidata interna autorizada por el propietario.'),
    'queued'
  ) returning * into v_job;

  insert into public.android_single_app_candidates(candidate_build_id)
  values (v_job.id);

  return v_job;
end;
$$;

revoke all on function public.queue_android_internal_candidate_v1(uuid, text, integer, text, text)
  from public, anon, authenticated;
grant execute on function public.queue_android_internal_candidate_v1(uuid, text, integer, text, text)
  to service_role;
