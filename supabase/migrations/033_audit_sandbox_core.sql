-- Sandbox lógico de auditoría dentro del entorno productivo.
-- Aísla cuentas QA/auditoría sin requerir otro backend ni otra APK.

create schema if not exists app_private;

create table if not exists public.audit_test_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint audit_test_groups_slug_check
    check (slug ~ '^[a-z0-9][a-z0-9_-]{1,63}$')
);

create table if not exists public.audit_test_group_members (
  group_id uuid not null references public.audit_test_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('passenger','driver','auditor')),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id),
  unique (user_id)
);

create index if not exists audit_test_group_members_group_idx
  on public.audit_test_group_members(group_id, enabled);
create index if not exists audit_test_group_members_user_idx
  on public.audit_test_group_members(user_id, enabled);

alter table public.audit_test_groups enable row level security;
alter table public.audit_test_group_members enable row level security;

revoke all on table public.audit_test_groups from anon;
revoke all on table public.audit_test_group_members from anon;
grant select on table public.audit_test_groups to authenticated;
grant select on table public.audit_test_group_members to authenticated;
grant all on table public.audit_test_groups to service_role;
grant all on table public.audit_test_group_members to service_role;

drop policy if exists audit_groups_select_own on public.audit_test_groups;
create policy audit_groups_select_own
on public.audit_test_groups
for select
to authenticated
using (
  exists (
    select 1
    from public.audit_test_group_members m
    where m.group_id = audit_test_groups.id
      and m.user_id = (select auth.uid())
      and m.enabled = true
  )
);

drop policy if exists audit_group_members_select_own on public.audit_test_group_members;
create policy audit_group_members_select_own
on public.audit_test_group_members
for select
to authenticated
using (user_id = (select auth.uid()));

create or replace function app_private.audit_group_id_for_user(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.group_id
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_id
    and m.enabled = true
    and g.active = true
  limit 1;
$$;

revoke all on function app_private.audit_group_id_for_user(uuid) from public;
revoke all on function app_private.audit_group_id_for_user(uuid) from anon;
revoke all on function app_private.audit_group_id_for_user(uuid) from authenticated;

create or replace function public.same_operational_scope(
  p_user_a uuid,
  p_user_b uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_group_a uuid;
  v_group_b uuid;
begin
  if p_user_a is null or p_user_b is null then
    return false;
  end if;

  v_group_a := app_private.audit_group_id_for_user(p_user_a);
  v_group_b := app_private.audit_group_id_for_user(p_user_b);

  if v_group_a is null and v_group_b is null then
    return true;
  end if;

  return v_group_a is not null
    and v_group_b is not null
    and v_group_a = v_group_b;
end;
$$;

revoke all on function public.same_operational_scope(uuid, uuid) from public;
revoke all on function public.same_operational_scope(uuid, uuid) from anon;
grant execute on function public.same_operational_scope(uuid, uuid)
  to authenticated, service_role;

create or replace function public.ride_request_matches_user_scope(
  p_ride_request_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, app_private
as $$
  select exists (
    select 1
    from public.ride_requests r
    where r.id = p_ride_request_id
      and public.same_operational_scope(r.passenger_id, p_user_id)
  );
$$;

revoke all on function public.ride_request_matches_user_scope(uuid, uuid) from public;
revoke all on function public.ride_request_matches_user_scope(uuid, uuid) from anon;
grant execute on function public.ride_request_matches_user_scope(uuid, uuid)
  to authenticated, service_role;

create or replace function public.current_operational_scope()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app_private
as $$
declare
  v_uid uuid := auth.uid();
  v_group_id uuid;
  v_name text;
  v_slug text;
  v_role text;
begin
  if v_uid is null then
    raise exception 'No autorizado';
  end if;

  select m.group_id, g.name, g.slug, m.role
    into v_group_id, v_name, v_slug, v_role
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = v_uid
    and m.enabled = true
    and g.active = true
  limit 1;

  return jsonb_build_object(
    'mode', case when v_group_id is null then 'production' else 'audit' end,
    'group_id', v_group_id,
    'group_name', v_name,
    'group_slug', v_slug,
    'role', v_role
  );
end;
$$;

revoke all on function public.current_operational_scope() from public;
revoke all on function public.current_operational_scope() from anon;
grant execute on function public.current_operational_scope()
  to authenticated, service_role;

create or replace function public.admin_audit_sandbox_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_groups jsonb;
  v_candidates jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', g.id,
        'name', g.name,
        'slug', g.slug,
        'active', g.active,
        'created_at', g.created_at,
        'members', coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'user_id', m.user_id,
                'role', m.role,
                'enabled', m.enabled,
                'full_name', u.full_name,
                'email', au.email,
                'active_mode', u.active_mode
              )
              order by m.role, u.full_name nulls last, au.email
            )
            from public.audit_test_group_members m
            left join public.users u on u.id = m.user_id
            left join auth.users au on au.id = m.user_id
            where m.group_id = g.id
          ),
          '[]'::jsonb
        )
      )
      order by g.created_at asc
    ),
    '[]'::jsonb
  )
  into v_groups
  from public.audit_test_groups g;

  select coalesce(
    jsonb_agg(to_jsonb(c) order by c.full_name nulls last, c.email),
    '[]'::jsonb
  )
  into v_candidates
  from (
    select
      u.id,
      u.full_name,
      au.email,
      u.active_mode,
      u.account_status,
      m.group_id,
      m.role as audit_role,
      m.enabled as audit_enabled
    from public.users u
    join auth.users au on au.id = u.id
    left join public.audit_test_group_members m on m.user_id = u.id
    where u.account_status = 'active'
    order by u.full_name nulls last, au.email
    limit 500
  ) c;

  return jsonb_build_object(
    'groups', v_groups,
    'candidates', v_candidates
  );
end;
$$;

create or replace function public.admin_upsert_audit_group(
  p_group_id uuid,
  p_name text,
  p_slug text,
  p_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_name text := nullif(trim(p_name), '');
  v_slug text := lower(trim(p_slug));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if v_name is null then
    raise exception 'Nombre requerido';
  end if;
  if v_slug is null or v_slug !~ '^[a-z0-9][a-z0-9_-]{1,63}$' then
    raise exception 'Identificador inválido';
  end if;

  if p_group_id is null then
    insert into public.audit_test_groups(name, slug, active, updated_at)
    values (v_name, v_slug, coalesce(p_active, true), now())
    returning id into v_id;
  else
    update public.audit_test_groups
    set name = v_name,
        slug = v_slug,
        active = coalesce(p_active, active),
        updated_at = now()
    where id = p_group_id
    returning id into v_id;

    if v_id is null then
      raise exception 'Entorno no encontrado';
    end if;
  end if;

  return v_id;
end;
$$;

create or replace function public.admin_set_audit_group_member(
  p_group_id uuid,
  p_user_id uuid,
  p_role text,
  p_enabled boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := lower(trim(coalesce(p_role, '')));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if not exists (select 1 from public.audit_test_groups where id = p_group_id) then
    raise exception 'Entorno no encontrado';
  end if;
  if not exists (select 1 from public.users where id = p_user_id) then
    raise exception 'Usuario no encontrado';
  end if;
  if v_role not in ('passenger','driver','auditor') then
    raise exception 'Rol de auditoría inválido';
  end if;

  delete from public.audit_test_group_members
  where user_id = p_user_id
    and group_id <> p_group_id;

  insert into public.audit_test_group_members(
    group_id, user_id, role, enabled, updated_at
  )
  values (
    p_group_id, p_user_id, v_role, coalesce(p_enabled, true), now()
  )
  on conflict (group_id, user_id)
  do update set
    role = excluded.role,
    enabled = excluded.enabled,
    updated_at = now();
end;
$$;

create or replace function public.admin_remove_audit_group_member(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  delete from public.audit_test_group_members where user_id = p_user_id;
end;
$$;

create or replace function public.admin_set_audit_group_active(
  p_group_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  update public.audit_test_groups
  set active = coalesce(p_active, false),
      updated_at = now()
  where id = p_group_id;
  if not found then
    raise exception 'Entorno no encontrado';
  end if;
end;
$$;

revoke all on function public.admin_audit_sandbox_state() from public;
revoke all on function public.admin_audit_sandbox_state() from anon;
grant execute on function public.admin_audit_sandbox_state() to authenticated;

revoke all on function public.admin_upsert_audit_group(uuid,text,text,boolean) from public;
revoke all on function public.admin_upsert_audit_group(uuid,text,text,boolean) from anon;
grant execute on function public.admin_upsert_audit_group(uuid,text,text,boolean)
  to authenticated;

revoke all on function public.admin_set_audit_group_member(uuid,uuid,text,boolean) from public;
revoke all on function public.admin_set_audit_group_member(uuid,uuid,text,boolean) from anon;
grant execute on function public.admin_set_audit_group_member(uuid,uuid,text,boolean)
  to authenticated;

revoke all on function public.admin_remove_audit_group_member(uuid) from public;
revoke all on function public.admin_remove_audit_group_member(uuid) from anon;
grant execute on function public.admin_remove_audit_group_member(uuid) to authenticated;

revoke all on function public.admin_set_audit_group_active(uuid,boolean) from public;
revoke all on function public.admin_set_audit_group_active(uuid,boolean) from anon;
grant execute on function public.admin_set_audit_group_active(uuid,boolean)
  to authenticated;

with group_row as (
  insert into public.audit_test_groups(name, slug, active, updated_at)
  values ('Auditoría QA principal', 'qa-core', true, now())
  on conflict (slug)
  do update set name = excluded.name, active = true, updated_at = now()
  returning id
),
resolved_group as (
  select id from group_row
  union all
  select id from public.audit_test_groups where slug = 'qa-core'
  limit 1
)
insert into public.audit_test_group_members(group_id, user_id, role, enabled, updated_at)
select
  g.id,
  au.id,
  case
    when lower(au.email) = 'qa-driver@expressdelivery.pro' then 'driver'
    else 'passenger'
  end,
  true,
  now()
from resolved_group g
join auth.users au
  on lower(au.email) in (
    'qa-passenger@expressdelivery.pro',
    'qa-driver@expressdelivery.pro'
  )
on conflict (user_id)
do update set
  group_id = excluded.group_id,
  role = excluded.role,
  enabled = true,
  updated_at = now();
