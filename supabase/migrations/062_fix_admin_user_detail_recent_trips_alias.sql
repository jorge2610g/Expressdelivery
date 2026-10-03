-- Fix admin user detail recent trips aggregation alias.
-- Prevents PostgREST 42P01: missing FROM-clause entry for table "x".

create or replace function public.admin_user_detail(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth'
as $function$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'user',jsonb_build_object(
      'id',u.id,
      'full_name',u.full_name,
      'email',au.email,
      'phone',u.phone,
      'avatar_url',u.avatar_url,
      'preferred_language',u.preferred_language,
      'active_mode',u.active_mode,
      'account_status',u.account_status,
      'last_zone_id',u.last_zone_id,
      'created_at',u.created_at,
      'updated_at',u.updated_at
    ),
    'zone',case when z.id is null then null else to_jsonb(z) end,
    'driver',case when d.id is null then null else to_jsonb(d) end,
    'wallet',(
      select case when w.user_id is null then null else to_jsonb(w) end
      from public.wallet_accounts w where w.user_id=u.id
    ),
    'rating_summary',jsonb_build_object(
      'count',(select count(*) from public.ratings r where r.to_user_id=u.id),
      'average',coalesce((select round(avg(r.score)::numeric,2) from public.ratings r where r.to_user_id=u.id),0)
    ),
    'qa',(
      select jsonb_build_object(
        'group_id',m.group_id,
        'group_name',g.name,
        'role',m.role,
        'enabled',m.enabled,
        'group_active',g.active
      )
      from public.audit_test_group_members m
      join public.audit_test_groups g on g.id=m.group_id
      where m.user_id=u.id
      limit 1
    ),
    'recent_trips',coalesce((
      select jsonb_agg(q.trip_json order by q.created_at desc)
      from (
        select
          jsonb_build_object(
            'id',t.id,
            'role',case when t.passenger_id=u.id then 'passenger' else 'driver' end,
            'status',t.status,
            'final_fare',t.final_fare,
            'payment_status',t.payment_status,
            'created_at',t.created_at,
            'completed_at',t.completed_at,
            'pickup_address',rr.pickup_address,
            'destination_address',rr.destination_address
          ) as trip_json,
          t.created_at
        from public.trips t
        left join public.ride_requests rr on rr.id=t.ride_request_id
        where t.passenger_id=u.id or t.driver_id=u.id
        order by t.created_at desc
        limit 20
      ) q
    ),'[]'::jsonb)
  )
  into v_result
  from public.users u
  left join auth.users au on au.id=u.id
  left join public.driver_profiles d on d.id=u.id
  left join public.service_zones z on z.id=coalesce(u.last_zone_id,d.zone_id)
  where u.id=p_user_id;

  if v_result is null then
    raise exception 'Usuario no encontrado';
  end if;

  return v_result;
end;
$function$;

revoke execute on function public.admin_user_detail(uuid) from public,anon;
grant execute on function public.admin_user_detail(uuid) to authenticated;
