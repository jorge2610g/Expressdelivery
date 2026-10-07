-- Scope identity verification reads to the admin-selected country and zone.
-- Keeps the legacy RPC untouched so older clients continue to work.
-- 2026-10-07

create or replace function public.admin_identity_verification_list_scoped(
  p_limit integer default 200,
  p_country_code text default null,
  p_zone_id uuid default null,
  p_provider text default null,
  p_provider_environment text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return (
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.created_at desc),
      '[]'::jsonb
    )
    from (
      select
        v.*,
        u.full_name,
        u.phone,
        u.avatar_url,
        coalesce(dp.zone_id, u.last_zone_id) as scope_zone_id,
        sz.name as scope_zone_name,
        sz.zone_key as scope_zone_key,
        sz.country_code as scope_country_code,
        sz.country as scope_country
      from public.identity_verifications v
      left join public.users u
        on u.id = v.user_id
      left join public.driver_profiles dp
        on dp.id = v.user_id
      left join public.service_zones sz
        on sz.id = coalesce(dp.zone_id, u.last_zone_id)
      where
        (
          p_zone_id is null
          or coalesce(dp.zone_id, u.last_zone_id) = p_zone_id
        )
        and (
          p_country_code is null
          or upper(coalesce(sz.country_code, '')) = upper(p_country_code)
        )
        and (
          p_provider is null
          or lower(coalesce(v.provider, '')) = lower(p_provider)
        )
        and (
          p_provider_environment is null
          or lower(coalesce(v.provider_environment, '')) =
             lower(p_provider_environment)
        )
      order by v.created_at desc
      limit least(greatest(coalesce(p_limit, 200), 1), 500)
    ) x
  );
end;
$$;

revoke all on function public.admin_identity_verification_list_scoped(
  integer, text, uuid, text, text
) from public, anon;

grant execute on function public.admin_identity_verification_list_scoped(
  integer, text, uuid, text, text
) to authenticated, service_role;

comment on function public.admin_identity_verification_list_scoped(
  integer, text, uuid, text, text
) is
  'Admin identity list scoped by the user/driver operational zone. Verification document country is returned but is not used as the operational zone filter.';


-- Support inbox: only users whose operational zone matches the selected zone.
create or replace function public.admin_support_threads_scoped(
  p_channel text,
  p_zone_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel), ''), 'production'));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  if p_zone_id is null then return '[]'::jsonb; end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'user_id',x.user_id,
          'full_name',u.full_name,
          'phone',u.phone,
          'zone_id',coalesce(dp.zone_id,u.last_zone_id),
          'last_message',x.body,
          'last_sender_role',x.sender_role,
          'last_message_at',x.created_at,
          'unread_count',(
            select count(*)
            from public.support_messages sm2
            where sm2.user_id=x.user_id
              and sm2.sender_role='user'
              and sm2.read_by_admin=false
          )
        )
        order by x.created_at desc
      ),
      '[]'::jsonb
    )
    from (
      select distinct on (sm.user_id)
        sm.user_id, sm.body, sm.sender_role, sm.created_at
      from public.support_messages sm
      join public.users su on su.id=sm.user_id
      left join public.driver_profiles sdp on sdp.id=sm.user_id
      where coalesce(sdp.zone_id,su.last_zone_id)=p_zone_id
        and (
          (
            v_channel='preview'
            and exists(
              select 1
              from public.audit_test_group_members q
              where q.enabled=true and q.user_id=sm.user_id
            )
          )
          or (
            v_channel='production'
            and not exists(
              select 1
              from public.audit_test_group_members q
              where q.enabled=true and q.user_id=sm.user_id
            )
          )
        )
      order by sm.user_id, sm.created_at desc
    ) x
    left join public.users u on u.id=x.user_id
    left join public.driver_profiles dp on dp.id=x.user_id
  );
end;
$$;

revoke all on function public.admin_support_threads_scoped(text, uuid)
  from public, anon;
grant execute on function public.admin_support_threads_scoped(text, uuid)
  to authenticated, service_role;

-- Notification history: selected zone plus truly global campaigns.
create or replace function public.admin_notification_campaign_list_scoped(
  p_channel text,
  p_zone_id uuid,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel),''),'production'));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  if p_zone_id is null then return '[]'::jsonb; end if;

  return (
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.created_at desc),
      '[]'::jsonb
    )
    from (
      select
        c.id,c.title,c.body,c.audience,c.zone_id,z.name as zone_name,
        c.partner_id,p.name as partner_name,c.recipients_targeted,
        c.push_enabled_recipients,c.created_at,c.channel,
        coalesce(ev.provider_accepted_users,0)::int as provider_accepted_users,
        coalesce(ev.provider_accepted_attempts,0)::int as provider_accepted_attempts,
        coalesce(ev.provider_invalid_attempts,0)::int as provider_invalid_attempts,
        coalesce(ev.opened_users,0)::int as opened_users,
        coalesce(nt.read_users,0)::int as read_users
      from public.notification_campaigns c
      left join public.service_zones z on z.id=c.zone_id
      left join public.partner_organizations p on p.id=c.partner_id
      left join lateral (
        select
          count(distinct e.notification_id) filter(where e.event='provider_accepted') as provider_accepted_users,
          count(*) filter(where e.event='provider_accepted') as provider_accepted_attempts,
          count(*) filter(where e.event='provider_invalid') as provider_invalid_attempts,
          count(distinct e.notification_id) filter(where e.event='opened') as opened_users
        from public.notification_delivery_events e
        where e.campaign_id=c.id
      ) ev on true
      left join lateral (
        select count(*) filter(where n.is_read=true) as read_users
        from public.notifications n
        where n.campaign_id=c.id
      ) nt on true
      where c.channel=v_channel
        and (c.zone_id is null or c.zone_id=p_zone_id)
        and (p_from is null or c.created_at>=p_from)
        and (p_to is null or c.created_at<p_to)
      order by c.created_at desc
      limit greatest(1,least(coalesce(p_limit,100),500))
    ) x
  );
end;
$$;

revoke all on function public.admin_notification_campaign_list_scoped(
  text, uuid, timestamptz, timestamptz, integer
) from public, anon;
grant execute on function public.admin_notification_campaign_list_scoped(
  text, uuid, timestamptz, timestamptz, integer
) to authenticated, service_role;

-- Driver priority: only approved drivers from the selected operational zone.
create or replace function public.admin_driver_priority_state_scoped(
  p_channel text,
  p_zone_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel),''),'preview'));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;

  return jsonb_build_object(
    'settings', public.driver_priority_settings_for(v_channel),
    'drivers', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id',dp.id,
            'name',u.full_name,
            'rating',dp.rating,
            'completed_trips',dp.completed_trips,
            'zone_id',dp.zone_id,
            'is_qa',exists(
              select 1 from public.audit_test_group_members q
              where q.enabled=true and q.user_id=dp.id
            ),
            'priority',public.driver_priority_summary_for_v2(dp.id,v_channel)
          )
          order by (public.driver_priority_summary_for_v2(dp.id,v_channel)->>'score')::numeric desc
        ),
        '[]'::jsonb
      )
      from public.driver_profiles dp
      join public.users u on u.id=dp.id
      where dp.approval_status='approved'
        and dp.zone_id=p_zone_id
        and (
          (v_channel='preview' and exists(
            select 1 from public.audit_test_group_members q
            where q.enabled=true and q.user_id=dp.id
          ))
          or
          (v_channel='production' and not exists(
            select 1 from public.audit_test_group_members q
            where q.enabled=true and q.user_id=dp.id
          ))
        )
    )
  );
end;
$$;

revoke all on function public.admin_driver_priority_state_scoped(text, uuid)
  from public, anon;
grant execute on function public.admin_driver_priority_state_scoped(text, uuid)
  to authenticated, service_role;

-- Marketplace: global catalog plus only banners/merchants applicable to scope.
create or replace function public.admin_marketplace_state_scoped(
  p_country_code text,
  p_zone_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'settings',(
      select to_jsonb(s)-'id'
      from public.marketplace_settings s
      where id=true
    ),
    'categories',(
      select coalesce(
        jsonb_agg(to_jsonb(c) order by c.sort_order,c.name),
        '[]'::jsonb
      )
      from public.marketplace_categories c
    ),
    'banners',(
      select coalesce(
        jsonb_agg(to_jsonb(b) order by b.sort_order),
        '[]'::jsonb
      )
      from public.marketplace_banners b
      where
        (b.zone_id is null and b.country_code is null)
        or b.zone_id=p_zone_id
        or (
          b.zone_id is null
          and upper(coalesce(b.country_code,''))=upper(coalesce(p_country_code,''))
        )
    ),
    'merchants',(
      select coalesce(
        jsonb_agg(to_jsonb(m) order by m.sort_order,m.name),
        '[]'::jsonb
      )
      from public.marketplace_merchants m
      where m.zone_id=p_zone_id
    )
  );
end;
$$;

revoke all on function public.admin_marketplace_state_scoped(text, uuid)
  from public, anon;
grant execute on function public.admin_marketplace_state_scoped(text, uuid)
  to authenticated, service_role;

-- Dynamic pricing QA overrides: only the selected zone/city.
create or replace function public.admin_dynamic_pricing_qa_state_scoped(
  p_zone_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_zone_key text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select zone_key into v_zone_key
  from public.service_zones
  where id=p_zone_id
  limit 1;

  return jsonb_build_object(
    'settings',(
      select to_jsonb(s)
      from public.dynamic_pricing_settings s
      where id=true
    ),
    'cities',coalesce((
      select jsonb_agg(to_jsonb(o) order by o.city_name)
      from public.dynamic_pricing_qa_overrides o
      where o.city_key=v_zone_key
    ),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_dynamic_pricing_qa_state_scoped(uuid)
  from public, anon;
grant execute on function public.admin_dynamic_pricing_qa_state_scoped(uuid)
  to authenticated, service_role;
