-- 102_didit_sandbox_identity_integration.sql
-- Prepare Didit Sandbox identity verification for Express Preview.

alter table public.identity_verification_settings
  add column if not exists didit_enabled boolean not null default false,
  add column if not exists didit_environment text not null default 'sandbox',
  add column if not exists didit_workflow_cl text,
  add column if not exists didit_workflow_bo text;

alter table public.identity_verification_settings
  drop constraint if exists identity_verification_settings_didit_environment_check;

alter table public.identity_verification_settings
  add constraint identity_verification_settings_didit_environment_check
  check (didit_environment in ('sandbox','production'));

alter table public.identity_verifications
  add column if not exists provider_session_id text,
  add column if not exists provider_environment text,
  add column if not exists country_code text,
  add column if not exists workflow_id text,
  add column if not exists verification_url text,
  add column if not exists provider_status text,
  add column if not exists completed_at timestamptz;

create unique index if not exists identity_verifications_provider_session_uidx
  on public.identity_verifications(provider, provider_session_id)
  where provider_session_id is not null;

create index if not exists identity_verifications_user_provider_created_idx
  on public.identity_verifications(user_id, provider, created_at desc);

drop policy if exists identity_verifications_read_self_admin
  on public.identity_verifications;

create policy identity_verifications_read_self_admin
  on public.identity_verifications
  for select to authenticated
  using (
    user_id=(select auth.uid())
    or public.is_admin()
  );

revoke insert,update,delete on public.identity_verifications from authenticated;

create or replace function public.my_identity_verification_status()
returns jsonb
language sql
stable
security invoker
set search_path to 'public','auth'
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'id',iv.id,
        'provider',iv.provider,
        'status',iv.status,
        'provider_status',iv.provider_status,
        'provider_environment',iv.provider_environment,
        'country_code',iv.country_code,
        'provider_session_id',iv.provider_session_id,
        'verification_url',iv.verification_url,
        'document_score',iv.document_score,
        'face_match_score',iv.face_match_score,
        'liveness_score',iv.liveness_score,
        'result',iv.result,
        'created_at',iv.created_at,
        'updated_at',iv.updated_at,
        'completed_at',iv.completed_at
      )
      from public.identity_verifications iv
      where iv.user_id=(select auth.uid())
      order by iv.created_at desc
      limit 1
    ),
    '{}'::jsonb
  )
$$;

revoke execute on function public.my_identity_verification_status() from public,anon;
grant execute on function public.my_identity_verification_status() to authenticated;

update public.identity_verification_settings
set provider='didit',
    document_enabled=true,
    face_enabled=true,
    face_match_enabled=true,
    liveness_enabled=true,
    didit_enabled=true,
    didit_environment='sandbox',
    updated_at=now()
where id=true;
