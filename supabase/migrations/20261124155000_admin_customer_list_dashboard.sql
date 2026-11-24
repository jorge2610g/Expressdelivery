-- Read-only data for the dedicated customer management presentation in Adminexpress.
begin;

create or replace function public.admin_customer_list_v1(
  p_channel text,
  p_zone_id uuid,
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0,
  p_status text default null
) returns jsonb
language plpgsql stable security definer set search_path=public,auth as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_zone uuid:=public.admin_effective_zone_id(p_zone_id);
  v_search text:=lower(trim(coalesce(p_search,'')));
  v_status text:=lower(trim(coalesce(p_status,'')));
  v_result jsonb;
begin
  perform public.admin_operator_assert_module('users');
  perform public.admin_assert_environment(v_channel);
  if v_status not in ('','pending','active','rejected','blocked','suspended','push_disabled') then
    raise exception 'Filtro de clientes inválido';
  end if;
  with base as (
    select u.id as user_id,u.full_name,au.email,u.phone,u.active_mode,u.account_status,
      u.created_at,z.country_code,z.currency_code,z.name as zone_name,z.city,z.region_department,z.country,
      coalesce(w.balance,0) as balance,
      coalesce(rating.average_rating,0) as rating,
      coalesce(rating.rating_count,0) as rating_count,
      coalesce(trips.completed_trips,0) as completed_trips,
      exists(select 1 from public.native_push_tokens n where n.user_id=u.id and n.channel=v_channel and n.active) as push_active,
      d.approval_status as driver_status,
      (v_channel='preview') as is_qa
    from public.users u
    left join auth.users au on au.id=u.id
    left join public.driver_profiles d on d.id=u.id
    left join public.service_zones z on z.id=coalesce(u.last_zone_id,d.zone_id)
    left join public.account_runtime_bindings rb on rb.user_id=u.id
    left join public.wallet_country_accounts w on w.user_id=u.id and w.country_code=z.country_code and w.channel=v_channel
    left join lateral (
      select round(avg(r.score)::numeric,2) as average_rating,count(*)::integer as rating_count
      from public.ratings r
      join public.trips rated_trip on rated_trip.id=r.trip_id
      join public.ride_requests rated_request on rated_request.id=rated_trip.ride_request_id
      where r.to_user_id=u.id and r.rated_role='passenger'
        and rated_trip.channel=v_channel and rated_request.channel=v_channel
        and rated_request.zone_id=v_zone
        and not public.is_merchant_courier_trip(r.trip_id)
    ) rating on true
    left join lateral (
      select count(*)::integer as completed_trips from public.trips t
      join public.ride_requests rr on rr.id=t.ride_request_id
      where t.passenger_id=u.id and t.status='completed' and t.channel=v_channel
        and rr.channel=v_channel and rr.zone_id=v_zone
    ) trips on true
    where z.id=v_zone
      and (coalesce(u.active_mode,'passenger')='passenger' or d.id is null or d.approval_status<>'approved')
      and public.normalize_runtime_channel(coalesce(rb.environment,
        case when exists(select 1 from public.audit_test_group_members m
          join public.audit_test_groups g on g.id=m.group_id
          where m.user_id=u.id and m.enabled and g.active) then 'preview' else 'production' end))=v_channel
      and (v_search='' or lower(coalesce(u.full_name,'')) like '%'||v_search||'%'
        or lower(coalesce(au.email,'')) like '%'||v_search||'%'
        or lower(coalesce(u.phone,'')) like '%'||v_search||'%')
  ), filtered as (
    select * from base where v_status=''
      or (v_status='pending' and account_status='pending')
      or (v_status='active' and account_status='active')
      or (v_status='rejected' and driver_status='rejected')
      or (v_status='blocked' and account_status='blocked')
      or (v_status='suspended' and account_status='suspended')
      or (v_status='push_disabled' and not push_active)
  )
  select jsonb_build_object(
    'total',(select count(*) from filtered),
    'rows',coalesce((select jsonb_agg(to_jsonb(page_row) order by page_row.created_at desc,page_row.full_name)
      from (select * from filtered order by created_at desc,full_name
        limit greatest(1,least(coalesce(p_limit,50),500)) offset greatest(0,coalesce(p_offset,0))) page_row),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;
revoke all on function public.admin_customer_list_v1(text,uuid,text,integer,integer,text) from public,anon;
grant execute on function public.admin_customer_list_v1(text,uuid,text,integer,integer,text) to authenticated,service_role;

create or replace function public.admin_customer_dashboard_v1(p_channel text,p_zone_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public,auth as $$
declare v_channel text:=public.normalize_runtime_channel(p_channel);v_zone uuid:=public.admin_effective_zone_id(p_zone_id);
begin
  perform public.admin_operator_assert_module('users');
  perform public.admin_assert_environment(v_channel);
  return (
    with audience as (
      select u.id,u.account_status,u.created_at,
        exists(select 1 from public.native_push_tokens n where n.user_id=u.id and n.channel=v_channel and n.active) as push_active
      from public.users u left join public.driver_profiles d on d.id=u.id
      left join public.service_zones z on z.id=coalesce(u.last_zone_id,d.zone_id)
      left join public.account_runtime_bindings rb on rb.user_id=u.id
      where z.id=v_zone
        and (coalesce(u.active_mode,'passenger')='passenger' or d.id is null or d.approval_status<>'approved')
        and public.normalize_runtime_channel(coalesce(rb.environment,
          case when exists(select 1 from public.audit_test_group_members m
            join public.audit_test_groups g on g.id=m.group_id
            where m.user_id=u.id and m.enabled and g.active) then 'preview' else 'production' end))=v_channel
    ), trip_users as (
      select distinct t.passenger_id as user_id from public.trips t
      join public.ride_requests rr on rr.id=t.ride_request_id
      where t.channel=v_channel and rr.channel=v_channel and rr.zone_id=v_zone and t.status='completed'
    )
    select jsonb_build_object(
      'total',(select count(*) from audience),
      'pending',(select count(*) from audience where account_status='pending'),
      'with_trips',(select count(*) from audience a join trip_users t on t.user_id=a.id),
      'new_30_days',(select count(*) from audience where created_at>=now()-interval '30 days'),
      'without_push',(select count(*) from audience where not push_active),
      'without_push_with_trips',(select count(*) from audience a join trip_users t on t.user_id=a.id where not a.push_active)
    )
  );
end $$;
revoke all on function public.admin_customer_dashboard_v1(text,uuid) from public,anon;
grant execute on function public.admin_customer_dashboard_v1(text,uuid) to authenticated,service_role;
commit;
