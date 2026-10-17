create or replace function public.same_operational_scope(p_user_a uuid, p_user_b uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, app_private
as $function$
declare
  v_env_a text;
  v_env_b text;
  v_group_a uuid;
  v_group_b uuid;
begin
  if p_user_a is null or p_user_b is null then
    return false;
  end if;

  select lower(b.environment)
    into v_env_a
  from public.account_runtime_bindings b
  where b.user_id = p_user_a
  limit 1;

  if v_env_a is null then
    v_env_a := case when exists(
      select 1
      from public.audit_test_group_members m
      join public.audit_test_groups g on g.id = m.group_id
      where m.user_id = p_user_a
        and m.enabled = true
        and g.active = true
    ) then 'preview' else 'production' end;
  end if;

  select lower(b.environment)
    into v_env_b
  from public.account_runtime_bindings b
  where b.user_id = p_user_b
  limit 1;

  if v_env_b is null then
    v_env_b := case when exists(
      select 1
      from public.audit_test_group_members m
      join public.audit_test_groups g on g.id = m.group_id
      where m.user_id = p_user_b
        and m.enabled = true
        and g.active = true
    ) then 'preview' else 'production' end;
  end if;

  if v_env_a is distinct from v_env_b then
    return false;
  end if;

  if v_env_a = 'production' then
    return true;
  end if;

  if v_env_a <> 'preview' then
    return false;
  end if;

  select m.group_id
    into v_group_a
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_a
    and m.enabled = true
    and g.active = true
  order by m.updated_at desc nulls last, m.created_at desc
  limit 1;

  select m.group_id
    into v_group_b
  from public.audit_test_group_members m
  join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_b
    and m.enabled = true
    and g.active = true
  order by m.updated_at desc nulls last, m.created_at desc
  limit 1;

  return v_group_a is not null
    and v_group_b is not null
    and v_group_a = v_group_b;
end;
$function$;
