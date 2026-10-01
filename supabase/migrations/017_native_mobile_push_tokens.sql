-- Native Android push token registry for Express.
-- Web Push remains in push_subscriptions; Android FCM uses this table.

create table if not exists public.native_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android'
    check (platform in ('android','ios')),
  device_label text,
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists native_push_tokens_user_active_idx
  on public.native_push_tokens(user_id, active);

alter table public.native_push_tokens enable row level security;

drop policy if exists native_push_tokens_select_own
  on public.native_push_tokens;
create policy native_push_tokens_select_own
  on public.native_push_tokens
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists native_push_tokens_delete_own
  on public.native_push_tokens;
create policy native_push_tokens_delete_own
  on public.native_push_tokens
  for delete
  to authenticated
  using (user_id = auth.uid());

create or replace function public.register_native_push_token(
  p_token text,
  p_platform text default 'android',
  p_device_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_platform text := lower(coalesce(nullif(trim(p_platform), ''), 'android'));
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if p_token is null or length(trim(p_token)) < 20 then
    raise exception 'Token push inválido';
  end if;

  if v_platform not in ('android','ios') then
    raise exception 'Plataforma push inválida';
  end if;

  insert into public.native_push_tokens(
    user_id,
    token,
    platform,
    device_label,
    active,
    last_seen_at,
    updated_at
  )
  values(
    v_uid,
    trim(p_token),
    v_platform,
    nullif(trim(coalesce(p_device_label, '')), ''),
    true,
    now(),
    now()
  )
  on conflict (token)
  do update set
    user_id = excluded.user_id,
    platform = excluded.platform,
    device_label = coalesce(excluded.device_label, public.native_push_tokens.device_label),
    active = true,
    last_seen_at = now(),
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.unregister_native_push_token(
  p_token text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return false;
  end if;

  update public.native_push_tokens
     set active = false,
         updated_at = now()
   where user_id = v_uid
     and token = trim(p_token);

  return found;
end;
$$;

revoke all on function public.register_native_push_token(text,text,text)
  from public, anon;
revoke all on function public.unregister_native_push_token(text)
  from public, anon;

grant execute on function public.register_native_push_token(text,text,text)
  to authenticated;
grant execute on function public.unregister_native_push_token(text)
  to authenticated;
