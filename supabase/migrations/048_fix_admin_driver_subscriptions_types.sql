
create or replace function public.admin_driver_subscriptions(p_search text default null)
returns table(
  driver_id uuid,
  full_name text,
  email text,
  phone text,
  approval_status text,
  online_status text,
  subscription_status text,
  plan_id bigint,
  plan_name text,
  started_at timestamptz,
  expires_at timestamptz,
  remaining_seconds bigint
)
language plpgsql
stable
security definer
set search_path=public,auth
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select
    dp.id::uuid,
    coalesce(u.full_name,'')::text,
    coalesce(au.email,'')::text,
    coalesce(u.phone,'')::text,
    coalesce(dp.approval_status,'')::text,
    coalesce(dp.online_status,'')::text,
    coalesce(ds.status,'inactive')::text,
    ds.plan_id::bigint,
    dsp.name::text,
    ds.started_at::timestamptz,
    ds.expires_at::timestamptz,
    case
      when ds.expires_at is null then 0::bigint
      else greatest(
        0::bigint,
        extract(epoch from (ds.expires_at-now()))::bigint
      )
    end::bigint
  from public.driver_profiles dp
  left join public.users u on u.id=dp.id
  left join auth.users au on au.id=dp.id
  left join public.driver_subscriptions ds on ds.driver_id=dp.id
  left join public.driver_subscription_plans dsp on dsp.id=ds.plan_id
  where coalesce(trim(p_search),'')=''
     or coalesce(u.full_name,'') ilike '%'||trim(p_search)||'%'
     or coalesce(au.email,'') ilike '%'||trim(p_search)||'%'
     or coalesce(u.phone,'') ilike '%'||trim(p_search)||'%'
  order by
    coalesce(ds.expires_at,'epoch'::timestamptz) desc,
    coalesce(u.full_name,au.email::text,'');
end;
$$;

revoke all on function public.admin_driver_subscriptions(text) from public,anon;
grant execute on function public.admin_driver_subscriptions(text) to authenticated;
