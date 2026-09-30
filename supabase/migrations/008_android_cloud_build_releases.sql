-- Android cloud builder + published mobile releases.
-- Applied to production Supabase on 2026-09-30.

alter table public.build_jobs
  add column if not exists apk_url text,
  add column if not exists aab_url text,
  add column if not exists run_url text,
  add column if not exists error_message text,
  add column if not exists signing_mode text not null default 'test',
  add column if not exists started_at timestamptz;

alter table public.build_jobs drop constraint if exists build_jobs_artifact_type_check;
alter table public.build_jobs
  add constraint build_jobs_artifact_type_check
  check (artifact_type = any (array['apk'::text,'aab'::text,'apk+aab'::text,'ipa'::text,'web'::text]));

alter table public.build_jobs drop constraint if exists build_jobs_status_check;
alter table public.build_jobs
  add constraint build_jobs_status_check
  check (status = any (array['queued'::text,'building'::text,'ready'::text,'failed'::text,'cancelled'::text]));

create table if not exists public.app_releases (
  id uuid primary key default gen_random_uuid(),
  platform text not null check (platform in ('android','ios')),
  version_name text not null,
  build_number integer not null,
  apk_url text,
  aab_url text,
  play_store_url text,
  changelog text,
  mandatory boolean not null default false,
  minimum_build integer,
  status text not null default 'published'
    check (status in ('draft','published','disabled')),
  build_job_id uuid references public.build_jobs(id) on delete set null,
  published_by uuid references auth.users(id) on delete set null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(platform, build_number)
);

alter table public.app_releases enable row level security;

create or replace function public.admin_publish_build(
  p_build_id uuid,
  p_mandatory boolean default false
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_build public.build_jobs%rowtype;
  v_release_id uuid;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select * into v_build
  from public.build_jobs
  where id = p_build_id;

  if not found then
    raise exception 'Build no encontrado';
  end if;

  if v_build.status <> 'ready' then
    raise exception 'El build todavía no está listo';
  end if;

  if v_build.apk_url is null or v_build.aab_url is null then
    raise exception 'Faltan artefactos Android';
  end if;

  insert into public.app_releases(
    platform, version_name, build_number, apk_url, aab_url, changelog,
    mandatory, status, build_job_id, published_by, published_at, updated_at
  )
  values(
    'android', v_build.version_name, v_build.build_number, v_build.apk_url,
    v_build.aab_url, v_build.changelog, coalesce(p_mandatory,false),
    'published', v_build.id, auth.uid(), now(), now()
  )
  on conflict (platform, build_number)
  do update set
    version_name = excluded.version_name,
    apk_url = excluded.apk_url,
    aab_url = excluded.aab_url,
    changelog = excluded.changelog,
    mandatory = excluded.mandatory,
    status = 'published',
    build_job_id = excluded.build_job_id,
    published_by = excluded.published_by,
    published_at = now(),
    updated_at = now()
  returning id into v_release_id;

  update public.app_releases
     set status='disabled', updated_at=now()
   where platform='android'
     and id <> v_release_id
     and status='published'
     and build_number < v_build.build_number;

  return v_release_id;
end;
$$;

create or replace function public.latest_app_release(
  p_platform text default 'android'
)
returns jsonb
language sql
security definer
set search_path=public
stable
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'id', r.id,
        'platform', r.platform,
        'version_name', r.version_name,
        'build_number', r.build_number,
        'apk_url', r.apk_url,
        'aab_url', r.aab_url,
        'play_store_url', r.play_store_url,
        'changelog', r.changelog,
        'mandatory', r.mandatory,
        'minimum_build', r.minimum_build,
        'published_at', r.published_at
      )
      from public.app_releases r
      where r.platform = p_platform
        and r.status='published'
      order by r.build_number desc
      limit 1
    ),
    '{}'::jsonb
  );
$$;

revoke all on function public.admin_publish_build(uuid,boolean) from public, anon;
grant execute on function public.admin_publish_build(uuid,boolean) to authenticated;
grant execute on function public.latest_app_release(text) to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'app-releases',
  'app-releases',
  true,
  262144000,
  array[
    'application/vnd.android.package-archive',
    'application/octet-stream'
  ]
)
on conflict (id) do update
set public = true,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
