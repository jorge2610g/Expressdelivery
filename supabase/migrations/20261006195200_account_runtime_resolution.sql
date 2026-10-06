-- Resolve Preview/Production from the authenticated account for Production
-- candidates used in Google Play Internal Testing.
--
-- This is additive: existing Preview APK behavior remains unchanged. A normal
-- account can never self-elect Preview. Preview is returned only for an
-- existing Preview binding or an active QA-group membership.

create or replace function public.resolve_current_runtime_environment()
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_bound text;
  v_source text;
  v_member_enabled boolean:=false;
  v_group_active boolean:=false;
begin
  if v_uid is null then
    raise exception 'No autorizado';
  end if;

  select b.environment,b.source
  into v_bound,v_source
  from public.account_runtime_bindings b
  where b.user_id=v_uid;

  if v_bound is null then
    select coalesce(m.enabled,false),coalesce(g.active,false)
    into v_member_enabled,v_group_active
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid
    order by m.updated_at desc nulls last,m.created_at desc
    limit 1;

    if coalesce(v_member_enabled,false) and coalesce(v_group_active,false) then
      insert into public.account_runtime_bindings(
        user_id,environment,source,bound_at,updated_at
      )
      values(v_uid,'preview','existing_audit_membership',now(),now())
      on conflict(user_id) do nothing;

      v_bound:='preview';
      v_source:='existing_audit_membership';
    else
      insert into public.account_runtime_bindings(
        user_id,environment,source,bound_at,updated_at
      )
      values(v_uid,'production','production_first_login',now(),now())
      on conflict(user_id) do nothing;

      v_bound:='production';
      v_source:='production_first_login';
    end if;
  end if;

  if v_bound='preview' then
    select coalesce(m.enabled,false),coalesce(g.active,false)
    into v_member_enabled,v_group_active
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid
    order by m.updated_at desc nulls last,m.created_at desc
    limit 1;

    if not coalesce(v_member_enabled,false)
       or not coalesce(v_group_active,false) then
      return jsonb_build_object(
        'allowed',false,
        'environment','preview',
        'source',v_source,
        'reason','preview_membership_inactive'
      );
    end if;
  end if;

  return jsonb_build_object(
    'allowed',true,
    'environment',v_bound,
    'source',v_source,
    'reason','ok'
  );
end;
$function$;

revoke all on function public.resolve_current_runtime_environment()
from public,anon;
grant execute on function public.resolve_current_runtime_environment()
to authenticated;

comment on function public.resolve_current_runtime_environment() is
  'Returns the server-authoritative runtime environment for the current account. Normal accounts default to Production; Preview requires an existing Preview binding or active QA membership.';
