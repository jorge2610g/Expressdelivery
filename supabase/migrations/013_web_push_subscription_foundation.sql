-- Web Push subscription foundation.
-- Applied to production Supabase project zgpijrznvaskgcmauwxx on 2026-09-30.
-- VAPID keys are generated server-side by the Edge Function and stored only in
-- push_server_config. No private push key is committed to this repository.

create extension if not exists pg_net with schema extensions;

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  platform text not null default 'web',
  user_agent text,
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_subscriptions_user_active_idx
  on public.push_subscriptions(user_id, active);

alter table public.push_subscriptions enable row level security;

drop policy if exists push_subscriptions_read_own
  on public.push_subscriptions;
create policy push_subscriptions_read_own
on public.push_subscriptions
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists push_subscriptions_delete_own
  on public.push_subscriptions;
create policy push_subscriptions_delete_own
on public.push_subscriptions
for delete
to authenticated
using (user_id = auth.uid());

create table if not exists public.push_server_config (
  id boolean primary key default true check (id = true),
  vapid_public_key text,
  vapid_private_key text,
  webhook_secret text not null default (
    gen_random_uuid()::text || gen_random_uuid()::text
  ),
  updated_at timestamptz not null default now()
);

alter table public.push_server_config enable row level security;

insert into public.push_server_config(id)
values (true)
on conflict (id) do nothing;

create or replace function public.register_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if nullif(trim(p_endpoint), '') is null
     or nullif(trim(p_p256dh), '') is null
     or nullif(trim(p_auth), '') is null then
    raise exception 'Suscripción push inválida';
  end if;

  insert into public.push_subscriptions (
    user_id, endpoint, p256dh, auth, platform,
    user_agent, active, last_seen_at, updated_at
  ) values (
    v_uid, p_endpoint, p_p256dh, p_auth, 'web',
    p_user_agent, true, now(), now()
  )
  on conflict (endpoint)
  do update set
    user_id = excluded.user_id,
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    platform = excluded.platform,
    user_agent = excluded.user_agent,
    active = true,
    last_seen_at = now(),
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.register_push_subscription(text,text,text,text)
  from public, anon;
grant execute on function public.register_push_subscription(text,text,text,text)
  to authenticated;

create or replace function public.unregister_push_subscription(
  p_endpoint text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  update public.push_subscriptions
  set active = false,
      updated_at = now()
  where endpoint = p_endpoint
    and user_id = auth.uid();
end;
$$;

revoke execute on function public.unregister_push_subscription(text)
  from public, anon;
grant execute on function public.unregister_push_subscription(text)
  to authenticated;
