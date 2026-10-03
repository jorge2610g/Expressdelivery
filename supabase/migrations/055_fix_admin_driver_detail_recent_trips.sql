-- Fix admin_driver_detail recent_trips aggregation ordering.
-- The previous implementation referenced x.created_at even though x is a JSONB alias.
-- Aggregate q.x and order by the real q.created_at column instead.

CREATE OR REPLACE FUNCTION public.admin_driver_detail(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
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
    'driver',to_jsonb(d),
    'zone',case when z.id is null then null else to_jsonb(z) end,
    'vehicles',coalesce((
      select jsonb_agg(to_jsonb(v) order by v.is_active desc,v.updated_at desc)
      from public.driver_vehicles v
      where v.driver_id=d.id
    ),'[]'::jsonb),
    'documents',coalesce((
      select jsonb_agg(to_jsonb(doc) order by doc.created_at desc)
      from public.driver_documents doc
      where doc.driver_id=d.id
    ),'[]'::jsonb),
    'identity_verifications',coalesce((
      select jsonb_agg(to_jsonb(iv) order by iv.created_at desc)
      from public.identity_verifications iv
      where iv.user_id=d.id
    ),'[]'::jsonb),
    'rating_summary',jsonb_build_object(
      'count',(select count(*) from public.ratings r where r.to_user_id=d.id),
      'average',coalesce((select round(avg(r.score)::numeric,2) from public.ratings r where r.to_user_id=d.id),0)
    ),
    'subscription',(
      select case when s.driver_id is null then null else jsonb_build_object(
        'status',s.status,
        'plan_id',s.plan_id,
        'plan_name',p.name,
        'plan_code',p.code,
        'zone_key',p.zone_key,
        'started_at',s.started_at,
        'expires_at',s.expires_at,
        'updated_at',s.updated_at
      ) end
      from public.driver_subscriptions s
      left join public.driver_subscription_plans p on p.id=s.plan_id
      where s.driver_id=d.id
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
      where m.user_id=d.id
      limit 1
    ),
    'partner',(
      select jsonb_build_object(
        'partner_id',pm.partner_id,
        'name',po.name,
        'type',po.organization_type,
        'status',pm.status
      )
      from public.driver_partner_memberships pm
      join public.partner_organizations po on po.id=pm.partner_id
      where pm.driver_id=d.id and pm.status='active'
      order by pm.started_at desc
      limit 1
    ),
    'recent_trips',coalesce((
      select jsonb_agg(q.x order by q.created_at desc)
      from (
        select jsonb_build_object(
          'id',t.id,
          'status',t.status,
          'final_fare',t.final_fare,
          'payment_status',t.payment_status,
          'created_at',t.created_at,
          'completed_at',t.completed_at,
          'pickup_address',rr.pickup_address,
          'destination_address',rr.destination_address
        ) as x,
        t.created_at
        from public.trips t
        left join public.ride_requests rr on rr.id=t.ride_request_id
        where t.driver_id=d.id
        order by t.created_at desc
        limit 20
      ) q
    ),'[]'::jsonb)
  )
  into v_result
  from public.driver_profiles d
  join public.users u on u.id=d.id
  left join auth.users au on au.id=d.id
  left join public.service_zones z on z.id=d.zone_id
  where d.id=p_user_id;

  if v_result is null then
    raise exception 'Conductor no encontrado';
  end if;
  return v_result;
end;
$function$;
