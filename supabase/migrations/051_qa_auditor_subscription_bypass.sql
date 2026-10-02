create or replace function public.driver_subscription_allows_dispatch(p_driver_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_zone_id uuid;
  v_zone_key text;
  v_enabled boolean := false;
  v_enforce boolean := false;
begin
  -- QA identities in active audit groups are test-only and must not be blocked
  -- by a commercial subscription gate.
  if exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=p_driver_id
      and m.enabled=true
      and g.active=true
  ) then
    return true;
  end if;

  select dp.zone_id into v_zone_id
  from public.driver_profiles dp
  where dp.id=p_driver_id;

  if v_zone_id is null then
    return case
      when not coalesce(
        (select enforce_access from public.driver_subscription_settings where id=true),
        false
      )
        then true
      else exists(
        select 1
        from public.driver_subscriptions s
        where s.driver_id=p_driver_id
          and s.status='active'
          and s.expires_at>now()
      )
    end;
  end if;

  select z.zone_key into v_zone_key
  from public.service_zones z
  where z.id=v_zone_id;

  select coalesce(s.enabled,false),coalesce(s.enforce_access,false)
  into v_enabled,v_enforce
  from public.driver_subscription_zone_settings s
  where s.zone_id=v_zone_id;

  if not coalesce(v_enabled,false) or not coalesce(v_enforce,false) then
    return true;
  end if;

  return exists(
    select 1
    from public.driver_subscriptions s
    join public.driver_subscription_plans p on p.id=s.plan_id
    where s.driver_id=p_driver_id
      and s.status='active'
      and s.expires_at>now()
      and p.zone_key=v_zone_key
      and p.active=true
  );
end;
$$;
