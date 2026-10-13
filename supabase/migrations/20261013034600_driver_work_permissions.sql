-- Per-driver independent operating permissions. The same web/backend serves
-- Preview and Production; the signed-in identity owns its runtime.
-- Existing approved Taxi drivers retain legacy access until explicitly changed.
create table if not exists public.driver_work_permissions (
  driver_id uuid not null references public.driver_profiles(id) on delete cascade,
  channel text not null check (channel in ('preview','production')),
  service_key text not null check (service_key in ('ride','parcel','market')),
  zone_id uuid not null references public.service_zones(id),
  status text not null check (status in ('pending','approved','rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid,
  updated_at timestamptz not null default now(),
  primary key(driver_id,channel,service_key)
);
create index if not exists idx_driver_work_permissions_pending
  on public.driver_work_permissions(channel,status,zone_id,service_key);
alter table public.driver_work_permissions enable row level security;
revoke all on public.driver_work_permissions from anon,authenticated;
grant select on public.driver_work_permissions to authenticated;
drop policy if exists driver_work_permissions_read_self on public.driver_work_permissions;
create policy driver_work_permissions_read_self on public.driver_work_permissions
  for select to authenticated
  using (driver_id=(select auth.uid()) or public.is_admin());

create or replace function public.driver_work_permission_allowed(
  p_driver_id uuid,p_service_key text,p_channel text
) returns boolean
language sql stable security definer set search_path=public
as $$
  select case when p_driver_id is null or p_service_key not in ('ride','parcel','market')
              or p_channel not in ('preview','production')
              or (auth.uid() is distinct from p_driver_id and not public.is_admin())
              or public.admin_user_runtime_environment(p_driver_id)<>p_channel
              then false
         else coalesce(
           (select d.status='approved'
            from public.driver_work_permissions d
            where d.driver_id=p_driver_id and d.channel=p_channel
              and d.service_key=p_service_key
              and d.zone_id=(select dp.zone_id from public.driver_profiles dp where dp.id=p_driver_id)),
           p_service_key='ride' -- historical taxi approval compatibility only
         )
         end;
$$;

-- Both parcel deliveries and commercial deliveries require an enabled
-- driver-facing Delivery service in this driver's zone and runtime.
create or replace function public.driver_delivery_zone_enabled(
  p_driver_id uuid,p_channel text
) returns boolean
language sql stable security definer set search_path=public
as $$
  select case when p_driver_id is null
       or p_channel<>public.admin_user_runtime_environment(p_driver_id)
       or (auth.uid() is distinct from p_driver_id and not public.is_admin())
       then false
       else exists (
         select 1 from public.driver_profiles dp
         join public.zone_service_catalog zc
           on zc.zone_id=dp.zone_id and zc.service_key='delivery'
         join public.service_catalog cat
           on cat.service_key='delivery'
         left join public.admin_environment_config a
           on p_channel='preview' and a.environment='preview'
          and a.module='zone_services'
          and a.record_key=dp.zone_id::text || ':delivery'
         where dp.id=p_driver_id
           and cat.enabled and cat.driver_visible
           and case when p_channel='preview'
              then coalesce((a.payload->>'enabled')::boolean,false)
              else zc.enabled end
           and case when p_channel='preview'
              then coalesce((a.payload->>'driver_visible')::boolean,false)
              else zc.driver_visible end
       ) end;
$$;

-- Driver can request but cannot self-approve a service.
create or replace function public.request_driver_work_permission(
  p_service_key text,p_channel text default 'production'
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=lower(trim(coalesce(p_channel,'')));
  v_zone uuid;
  v_status text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Cuenta no autorizada';
  end if;
  if p_service_key not in ('ride','parcel','market') or v_channel not in ('preview','production')
     or public.admin_user_runtime_environment(v_uid)<>v_channel then
    raise exception 'Servicio o entorno no autorizado';
  end if;
  select zone_id into v_zone from public.driver_profiles where id=v_uid;
  if v_zone is null then raise exception 'Completa el registro de conductor y su zona'; end if;
  insert into public.driver_work_permissions(driver_id,channel,service_key,zone_id,status)
  values(v_uid,v_channel,p_service_key,v_zone,'pending')
  on conflict(driver_id,channel,service_key) do update
    set zone_id=excluded.zone_id,
        status=case when driver_work_permissions.status='approved'
                        and driver_work_permissions.zone_id=excluded.zone_id
                    then 'approved' else 'pending' end,
        requested_at=case when driver_work_permissions.status='approved'
                              and driver_work_permissions.zone_id=excluded.zone_id
                          then driver_work_permissions.requested_at else now() end,
        updated_at=now();
  select status into v_status from public.driver_work_permissions
  where driver_id=v_uid and channel=v_channel and service_key=p_service_key;
  return jsonb_build_object('service_key',p_service_key,'status',v_status,'channel',v_channel);
end;
$$;

create or replace function public.my_driver_work_permissions(
  p_channel text default 'production'
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_uid uuid:=auth.uid(); v_zone uuid; v_channel text:=lower(trim(coalesce(p_channel,'')));
begin
  if v_uid is null or v_channel not in ('preview','production')
     or public.admin_user_runtime_environment(v_uid)<>v_channel then
    raise exception 'Entorno no autorizado';
  end if;
  select zone_id into v_zone from public.driver_profiles where id=v_uid;
  if v_zone is null then return '[]'::jsonb; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'service_key',k.service_key,
      'status',coalesce(w.status,case when k.service_key='ride' then 'approved' else 'not_requested' end),
      'channel',v_channel,'zone_id',v_zone
    ) order by k.ordinal),'[]'::jsonb)
    from (values ('ride',1),('parcel',2),('market',3)) k(service_key,ordinal)
    left join public.driver_work_permissions w
      on w.driver_id=v_uid and w.zone_id=v_zone
       and w.channel=v_channel and w.service_key=k.service_key);
end;
$$;

create or replace function public.admin_driver_work_permission_list(
  p_driver_id uuid,p_channel text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_zone uuid;
begin
  if not public.is_admin() then raise exception 'Administrador requerido'; end if;
  perform public.admin_assert_target_environment(p_driver_id,p_channel);
  select zone_id into v_zone from public.driver_profiles where id=p_driver_id;
  if v_zone is null then raise exception 'Conductor sin zona asignada'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'service_key',k.service_key,'status',
    coalesce(w.status,case when k.service_key='ride' then 'approved' else 'not_requested' end),
    'requested_at',w.requested_at,'reviewed_at',w.reviewed_at,
    'zone_id',v_zone,'channel',p_channel
    ) order by k.ordinal),'[]'::jsonb)
    from (values ('ride',1),('parcel',2),('market',3)) k(service_key,ordinal)
    left join public.driver_work_permissions w
      on w.driver_id=p_driver_id and w.zone_id=v_zone
       and w.channel=p_channel and w.service_key=k.service_key);
end;
$$;

create or replace function public.admin_set_driver_work_permission(
  p_driver_id uuid,p_service_key text,p_status text,p_channel text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_zone uuid;
begin
  if not public.is_admin() then raise exception 'Administrador requerido'; end if;
  perform public.admin_assert_target_environment(p_driver_id,p_channel);
  if p_service_key not in ('ride','parcel','market')
     or p_status not in ('approved','pending','rejected') then
    raise exception 'Permiso inválido';
  end if;
  select zone_id into v_zone from public.driver_profiles where id=p_driver_id;
  if v_zone is null then raise exception 'El conductor debe tener una zona'; end if;
  insert into public.driver_work_permissions(
      driver_id,channel,service_key,zone_id,status,reviewed_at,reviewed_by)
  values(p_driver_id,p_channel,p_service_key,v_zone,p_status,now(),auth.uid())
  on conflict(driver_id,channel,service_key) do update
    set status=excluded.status,zone_id=excluded.zone_id,
        reviewed_at=now(),reviewed_by=auth.uid(),updated_at=now();
  return jsonb_build_object('service_key',p_service_key,'status',p_status,
                            'zone_id',v_zone,'channel',p_channel);
end;
$$;
revoke all on function public.admin_set_driver_work_permission(uuid,text,text,text) from public;
revoke all on function public.admin_driver_work_permission_list(uuid,text) from public;
grant execute on function public.admin_set_driver_work_permission(uuid,text,text,text) to authenticated;
grant execute on function public.admin_driver_work_permission_list(uuid,text) to authenticated;
grant execute on function public.request_driver_work_permission(text,text) to authenticated;
grant execute on function public.my_driver_work_permissions(text) to authenticated;
grant execute on function public.driver_work_permission_allowed(uuid,text,text) to authenticated;
grant execute on function public.driver_delivery_zone_enabled(uuid,text) to authenticated;
