-- Login security for Supabase Free plan.
-- Stores only SHA-256 hashes of normalized emails. No raw email/password is persisted.
-- The app enforces a 3-attempt lock before password authentication and clears it
-- after a successful login or password-recovery session.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.auth_login_guard (
  email_hash text primary key,
  failed_attempts smallint not null default 0,
  locked_at timestamptz,
  last_failed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint auth_login_guard_hash_format
    check (email_hash ~ '^[0-9a-f]{64}$'),
  constraint auth_login_guard_failed_attempts_range
    check (failed_attempts between 0 and 3)
);

comment on table public.auth_login_guard is
  'Server-side login failure state keyed by SHA-256 of normalized email.';

alter table public.auth_login_guard enable row level security;

revoke all on table public.auth_login_guard from anon, authenticated, public;
grant select, insert, update, delete on table public.auth_login_guard to service_role;

create or replace function public.auth_login_guard_state(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_failed smallint := 0;
  v_locked_at timestamptz;
begin
  if p_email is null or position('@' in p_email) = 0 then
    return jsonb_build_object(
      'locked', false,
      'failed_attempts', 0,
      'remaining_attempts', 3
    );
  end if;

  v_hash := encode(
    extensions.digest(lower(trim(p_email)), 'sha256'),
    'hex'
  );

  select failed_attempts, locked_at
    into v_failed, v_locked_at
  from public.auth_login_guard
  where email_hash = v_hash;

  v_failed := coalesce(v_failed, 0);

  return jsonb_build_object(
    'locked', v_locked_at is not null,
    'failed_attempts', v_failed,
    'remaining_attempts', greatest(0, 3 - v_failed)
  );
end;
$$;

revoke execute on function public.auth_login_guard_state(text) from public;
grant execute on function public.auth_login_guard_state(text) to anon, authenticated;

create or replace function public.auth_login_guard_record_failure(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_failed smallint;
  v_locked_at timestamptz;
begin
  if p_email is null or position('@' in p_email) = 0 then
    raise exception 'invalid email';
  end if;

  v_hash := encode(
    extensions.digest(lower(trim(p_email)), 'sha256'),
    'hex'
  );

  insert into public.auth_login_guard (
    email_hash,
    failed_attempts,
    locked_at,
    last_failed_at,
    updated_at
  )
  values (
    v_hash,
    1,
    null,
    now(),
    now()
  )
  on conflict (email_hash) do update
  set failed_attempts = least(public.auth_login_guard.failed_attempts + 1, 3),
      locked_at = case
        when public.auth_login_guard.failed_attempts + 1 >= 3
          then coalesce(public.auth_login_guard.locked_at, now())
        else public.auth_login_guard.locked_at
      end,
      last_failed_at = now(),
      updated_at = now()
  returning failed_attempts, locked_at
    into v_failed, v_locked_at;

  return jsonb_build_object(
    'locked', v_locked_at is not null,
    'failed_attempts', v_failed,
    'remaining_attempts', greatest(0, 3 - v_failed)
  );
end;
$$;

revoke execute on function public.auth_login_guard_record_failure(text) from public;
grant execute on function public.auth_login_guard_record_failure(text) to anon;

create or replace function public.auth_login_guard_clear_current()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_email text;
  v_hash text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select email into v_email
  from auth.users
  where id = v_user_id;

  if v_email is null then
    return;
  end if;

  v_hash := encode(
    extensions.digest(lower(trim(v_email)), 'sha256'),
    'hex'
  );

  delete from public.auth_login_guard
  where email_hash = v_hash;
end;
$$;

revoke execute on function public.auth_login_guard_clear_current() from public, anon;
grant execute on function public.auth_login_guard_clear_current() to authenticated;
