-- AdminExpress runtime-scope isolation.
-- One UI, two data planes: preview and production.
-- Backend remains authoritative for environment access and target ownership.

alter table public.admin_users
  add column if not exists allow_preview boolean not null default true,
  add column if not exists allow_production boolean not null default true;

-- Zone monitors were already hard-pinned to Production by the UI.
update public.admin_users
set allow_preview = false,
    allow_production = true,
    updated_at = now()
where access_role = 'zone_monitor'
  and active = true;

create or replace function public.admin_environment_allowed(p_channel text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := lower(trim(coalesce(p_channel,'')));
  v_allowed boolean := false;
begin
  if v_channel not in ('preview','production') then
    return false;
  end if;

  select case
    when v_channel='preview' then a.allow_preview and a.access_role <> 'zone_monitor'
    else a.allow_production
  end
  into v_allowed
  from public.admin_users a
  join public.users u on u.id=a.user_id
  where a.user_id=auth.uid()
    and a.active=true
    and u.account_status='active'
  limit 1;

  return coalesce(v_allowed,false);
end;
$function$;

create or replace function public.admin_assert_environment(p_channel text)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := lower(trim(coalesce(p_channel,'')));
begin
  if v_channel not in ('preview','production') then
    raise exception 'Entorno administrativo inválido';
  end if;
  if not public.admin_environment_allowed(v_channel) then
    raise exception 'No autorizado para el entorno %', v_channel;
  end if;
  return v_channel;
end;
$function$;

create or replace function public.admin_user_runtime_environment(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_environment text;
begin
  select b.environment
  into v_environment
  from public.account_runtime_bindings b
  where b.user_id=p_user_id;

  if v_environment in ('preview','production') then
    return v_environment;
  end if;

  if exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=p_user_id
      and m.enabled=true
      and g.active=true
  ) then
    return 'preview';
  end if;

  return 'production';
end;
$function$;

create or replace function public.admin_assert_target_environment(
  p_user_id uuid,
  p_channel text
)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := public.admin_assert_environment(p_channel);
  v_target text;
begin
  if p_user_id is null then
    raise exception 'Usuario requerido';
  end if;

  v_target := public.admin_user_runtime_environment(p_user_id);
  if v_target <> v_channel then
    raise exception 'El registro pertenece a % y el panel está en %', v_target, v_channel;
  end if;
  return v_channel;
end;
$function$;

create or replace function public.admin_access_context()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'allowed',true,
    'role',a.access_role,
    'read_only',a.access_role='zone_monitor',
    'zone_id',a.zone_id,
    'zone_key',z.zone_key,
    'zone_name',z.name,
    'city',z.city,
    'country',z.country,
    'country_code',z.country_code,
    'allow_preview',a.allow_preview and a.access_role <> 'zone_monitor',
    'allow_production',a.allow_production,
    'can_switch_environment',
      (a.allow_preview and a.access_role <> 'zone_monitor') and a.allow_production,
    'default_environment',
      case
        when a.access_role='zone_monitor' then 'production'
        when a.allow_preview and a.access_role <> 'zone_monitor' then 'preview'
        when a.allow_production then 'production'
        else null
      end,
    'allowed_environments',
      (
        select coalesce(jsonb_agg(x.env order by x.sort_order),'[]'::jsonb)
        from (
          select 'production'::text env,1 sort_order where a.allow_production
          union all
          select 'preview'::text env,2 sort_order
          where a.allow_preview and a.access_role <> 'zone_monitor'
        ) x
      )
  )
  into v_result
  from public.admin_users a
  join public.users u on u.id=a.user_id
  left join public.service_zones z on z.id=a.zone_id
  where a.user_id=auth.uid()
    and a.active=true
    and u.account_status='active'
  limit 1;

  return coalesce(v_result,jsonb_build_object('allowed',false));
end;
$function$;

create or replace function public.admin_driver_detail_v2(
  p_user_id uuid,
  p_channel text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform public.admin_assert_target_environment(p_user_id,p_channel);
  return public.admin_driver_detail(p_user_id);
end;
$function$;

create or replace function public.admin_user_detail_v2(
  p_user_id uuid,
  p_channel text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform public.admin_assert_target_environment(p_user_id,p_channel);
  return public.admin_user_detail(p_user_id);
end;
$function$;

create or replace function public.admin_trip_detail_v2(
  p_trip_id uuid,
  p_channel text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := public.admin_assert_environment(p_channel);
  v_trip_channel text;
begin
  select lower(coalesce(nullif(trim(t.channel),''),'production'))
  into v_trip_channel
  from public.trips t
  where t.id=p_trip_id;

  if v_trip_channel is null then
    raise exception 'Viaje no encontrado';
  end if;
  if v_trip_channel <> v_channel then
    raise exception 'El viaje pertenece a % y el panel está en %',v_trip_channel,v_channel;
  end if;

  return public.admin_trip_detail(p_trip_id);
end;
$function$;

create or replace function public.admin_set_driver_approval_v2(
  p_user_id uuid,
  p_status text,
  p_channel text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform public.admin_assert_target_environment(p_user_id,p_channel);
  perform public.admin_set_driver_approval(p_user_id,p_status);
end;
$function$;

create or replace function public.admin_set_account_status_v2(
  p_user_id uuid,
  p_status text,
  p_channel text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform public.admin_assert_target_environment(p_user_id,p_channel);
  perform public.admin_set_account_status(p_user_id,p_status);
end;
$function$;

create or replace function public.admin_update_driver_profile_v2(
  p_user_id uuid,
  p_full_name text,
  p_phone text,
  p_account_status text,
  p_license_number text,
  p_city text,
  p_zone_id uuid,
  p_approval_status text,
  p_online_status text,
  p_vehicle_type text,
  p_vehicle_brand text,
  p_vehicle_model text,
  p_vehicle_color text,
  p_vehicle_plate text,
  p_vehicle_year integer,
  p_channel text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;
begin
  perform public.admin_assert_target_environment(p_user_id,p_channel);
  v_result := public.admin_update_driver_profile(
    p_user_id,p_full_name,p_phone,p_account_status,p_license_number,p_city,
    p_zone_id,p_approval_status,p_online_status,p_vehicle_type,p_vehicle_brand,
    p_vehicle_model,p_vehicle_color,p_vehicle_plate,p_vehicle_year
  );
  perform public.admin_log_action(
    'admin_scope_confirmed','driver_profile',p_user_id::text,
    jsonb_build_object('environment',lower(trim(p_channel)))
  );
  return v_result;
end;
$function$;

create or replace function public.admin_update_user_profile_v2(
  p_user_id uuid,
  p_full_name text,
  p_phone text,
  p_active_mode text,
  p_account_status text,
  p_zone_id uuid,
  p_channel text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;
begin
  perform public.admin_assert_target_environment(p_user_id,p_channel);
  v_result := public.admin_update_user_profile(
    p_user_id,p_full_name,p_phone,p_active_mode,p_account_status,p_zone_id
  );
  perform public.admin_log_action(
    'admin_scope_confirmed','user',p_user_id::text,
    jsonb_build_object('environment',lower(trim(p_channel)))
  );
  return v_result;
end;
$function$;

create or replace function public.admin_upsert_driver_document_v2(
  p_document_id uuid,
  p_driver_id uuid,
  p_document_type text,
  p_document_number text,
  p_document_url text,
  p_status text,
  p_expires_at timestamptz,
  p_notes text,
  p_channel text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
begin
  perform public.admin_assert_target_environment(p_driver_id,p_channel);
  v_id := public.admin_upsert_driver_document(
    p_document_id,p_driver_id,p_document_type,p_document_number,p_document_url,
    p_status,p_expires_at,p_notes
  );
  perform public.admin_log_action(
    'admin_scope_confirmed','driver_document',v_id::text,
    jsonb_build_object(
      'environment',lower(trim(p_channel)),
      'driver_id',p_driver_id
    )
  );
  return v_id;
end;
$function$;

create or replace function public.admin_resolve_emergency_v2(
  p_emergency_id uuid,
  p_channel text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid;
begin
  perform public.admin_assert_environment(p_channel);
  select e.user_id into v_user_id
  from public.emergency_events e
  where e.id=p_emergency_id;

  if v_user_id is null then
    raise exception 'Emergencia no encontrada';
  end if;

  perform public.admin_assert_target_environment(v_user_id,p_channel);
  perform public.admin_resolve_emergency(p_emergency_id);
  perform public.admin_log_action(
    'admin_scope_confirmed','emergency',p_emergency_id::text,
    jsonb_build_object('environment',lower(trim(p_channel)))
  );
end;
$function$;

-- Audit remains one table, but environment-aware reads classify legacy rows by
-- the target account when old actions did not yet include environment details.
create or replace function public.admin_audit_list_v2(
  p_channel text,
  p_limit integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := public.admin_assert_environment(p_channel);
begin
  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',a.id,
          'admin_user_id',a.admin_user_id,
          'admin_name',u.full_name,
          'action',a.action,
          'entity_type',a.entity_type,
          'entity_id',a.entity_id,
          'details',a.details || jsonb_build_object('resolved_environment',a.resolved_environment),
          'created_at',a.created_at
        )
        order by a.created_at desc
      ),
      '[]'::jsonb
    )
    from (
      select l.*,
        coalesce(
          nullif(l.details->>'environment',''),
          nullif(l.details->>'channel',''),
          case
            when l.entity_type in ('user','driver_profile')
              and l.entity_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
            then public.admin_user_runtime_environment(l.entity_id::uuid)
            when l.entity_type='driver_document'
              and (l.details->>'driver_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
            then public.admin_user_runtime_environment((l.details->>'driver_id')::uuid)
            else 'production'
          end
        ) as resolved_environment
      from public.admin_audit_log l
      order by l.created_at desc
      limit greatest(1,least(coalesce(p_limit,200) * 4,4000))
    ) a
    left join public.users u on u.id=a.admin_user_id
    where a.resolved_environment=v_channel
    limit greatest(1,least(coalesce(p_limit,200),1000))
  );
end;
$function$;

revoke execute on function public.admin_environment_allowed(text) from public,anon;
revoke execute on function public.admin_assert_environment(text) from public,anon;
revoke execute on function public.admin_user_runtime_environment(uuid) from public,anon;
revoke execute on function public.admin_assert_target_environment(uuid,text) from public,anon;

grant execute on function public.admin_environment_allowed(text) to authenticated;
grant execute on function public.admin_assert_environment(text) to authenticated;
grant execute on function public.admin_user_runtime_environment(uuid) to authenticated;
grant execute on function public.admin_assert_target_environment(uuid,text) to authenticated;
grant execute on function public.admin_driver_detail_v2(uuid,text) to authenticated;
grant execute on function public.admin_user_detail_v2(uuid,text) to authenticated;
grant execute on function public.admin_trip_detail_v2(uuid,text) to authenticated;
grant execute on function public.admin_set_driver_approval_v2(uuid,text,text) to authenticated;
grant execute on function public.admin_set_account_status_v2(uuid,text,text) to authenticated;
grant execute on function public.admin_update_driver_profile_v2(uuid,text,text,text,text,text,uuid,text,text,text,text,text,text,text,integer,text) to authenticated;
grant execute on function public.admin_update_user_profile_v2(uuid,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.admin_upsert_driver_document_v2(uuid,uuid,text,text,text,text,timestamptz,text,text) to authenticated;
grant execute on function public.admin_resolve_emergency_v2(uuid,text) to authenticated;
