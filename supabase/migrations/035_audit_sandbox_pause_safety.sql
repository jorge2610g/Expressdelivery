-- Safety semantics for paused audit sandboxes.
-- A paused/disabled audit membership remains isolated from production.
-- Only removing the membership returns an account to normal production scope.

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
  v_member_enabled_a boolean;
  v_member_enabled_b boolean;
  v_group_active_a boolean;
  v_group_active_b boolean;
begin
  if p_user_a is null or p_user_b is null then
    return false;
  end if;

  select m.group_id, m.enabled, g.active
    into v_group_a, v_member_enabled_a, v_group_active_a
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_a
  limit 1;

  select m.group_id, m.enabled, g.active
    into v_group_b, v_member_enabled_b, v_group_active_b
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_b
  limit 1;

  if v_group_a is null and v_group_b is null then
    return true;
  end if;

  if v_group_a is null or v_group_b is null then
    return false;
  end if;

  return v_group_a = v_group_b
    and coalesce(v_member_enabled_a, false)
    and coalesce(v_member_enabled_b, false)
    and coalesce(v_group_active_a, false)
    and coalesce(v_group_active_b, false);
end;
$$;

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
  v_member_enabled boolean;
  v_group_active boolean;
begin
  if v_uid is null then
    raise exception 'No autorizado';
  end if;

  select m.group_id, g.name, g.slug, m.role, m.enabled, g.active
    into v_group_id, v_name, v_slug, v_role, v_member_enabled, v_group_active
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = v_uid
  limit 1;

  return jsonb_build_object(
    'mode',
      case
        when v_group_id is null then 'production'
        when coalesce(v_member_enabled, false)
          and coalesce(v_group_active, false) then 'audit'
        else 'audit_paused'
      end,
    'group_id', v_group_id,
    'group_name', v_name,
    'group_slug', v_slug,
    'role', v_role,
    'member_enabled', v_member_enabled,
    'group_active', v_group_active
  );
end;
$$;
