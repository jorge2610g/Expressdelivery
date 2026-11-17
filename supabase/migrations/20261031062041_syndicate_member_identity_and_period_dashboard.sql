-- Sindicato identity and reporting: only completed plan payments contribute.
begin;
alter table public.partner_organizations
  add column if not exists logo_url text,
  add column if not exists brand_color text not null default '#ED6B1F';

alter table public.partner_organizations
  drop constraint if exists partner_organizations_brand_color_check;
alter table public.partner_organizations
  add constraint partner_organizations_brand_color_check
  check (brand_color ~ '^#[0-9A-Fa-f]{6}$');

alter table public.driver_partner_memberships
  add column if not exists member_number smallint,
  add column if not exists channel text not null default 'production'
    check(channel in ('preview','production'));
alter table public.driver_partner_join_requests
  add column if not exists channel text not null default 'production'
    check(channel in ('preview','production'));
alter table public.driver_partner_memberships
  drop constraint if exists driver_partner_memberships_member_number_check;
alter table public.driver_partner_memberships
  add constraint driver_partner_memberships_member_number_check
  check (member_number is null or member_number between 1 and 100);

insert into storage.buckets(id,name,public)
values('partner-logos','partner-logos',true)
on conflict(id) do update set public=true;
drop policy if exists partner_logo_org_write on storage.objects;
create policy partner_logo_org_write on storage.objects for insert to authenticated
with check (
  bucket_id='partner-logos' and (public.is_admin() or exists (
    select 1 from public.partner_members pm
    where pm.partner_id=split_part(name,'/',1)::uuid and pm.user_id=auth.uid()
      and pm.active and pm.role in ('owner','manager')
  ))
);
drop policy if exists partner_logo_org_update on storage.objects;
create policy partner_logo_org_update on storage.objects for update to authenticated
using (bucket_id='partner-logos' and (public.is_admin() or exists (
    select 1 from public.partner_members pm
    where pm.partner_id=split_part(name,'/',1)::uuid and pm.user_id=auth.uid()
      and pm.active and pm.role in ('owner','manager')
  ))) with check (bucket_id='partner-logos' and (public.is_admin() or exists (
    select 1 from public.partner_members pm where pm.partner_id=split_part(name,'/',1)::uuid
      and pm.user_id=auth.uid() and pm.active and pm.role in ('owner','manager')
  )));
drop policy if exists partner_logo_org_delete on storage.objects;
create policy partner_logo_org_delete on storage.objects for delete to authenticated
using (bucket_id='partner-logos' and (public.is_admin() or exists (
    select 1 from public.partner_members pm
    where pm.partner_id=split_part(name,'/',1)::uuid and pm.user_id=auth.uid()
      and pm.active and pm.role in ('owner','manager')
  )));
drop index if exists public.driver_partner_memberships_number_uidx;
create unique index driver_partner_memberships_number_uidx
  on public.driver_partner_memberships(partner_id, channel, member_number)
  where member_number is not null and status in ('active','suspended');

alter table public.partner_settlements
  add column if not exists channel text not null default 'production'
    check(channel in ('preview','production'));

create or replace function public.partner_save_branding(
  p_partner_id uuid, p_name text, p_logo_url text, p_brand_color text
) returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  if not public.is_admin() and not exists (
    select 1 from public.partner_members pm
    where pm.partner_id=p_partner_id and pm.user_id=auth.uid()
      and pm.active and pm.role in ('owner','manager')
  ) then raise exception 'No autorizado'; end if;
  if coalesce(trim(p_name),'')='' or p_brand_color !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Datos de identidad inválidos';
  end if;
  update public.partner_organizations
  set name=trim(p_name), logo_url=nullif(trim(coalesce(p_logo_url,'')),''),
      brand_color=upper(p_brand_color), updated_at=now()
  where id=p_partner_id;
  if not found then raise exception 'Sindicato no encontrado'; end if;
end $$;

create or replace function public.partner_add_driver(
  p_partner_id uuid, p_driver_id uuid, p_member_number smallint
) returns void language plpgsql security definer set search_path=public,auth as $$
declare v_zone uuid; v_membership_id bigint; v_runtime jsonb; v_channel text;
begin
  if auth.uid() is null or p_member_number not between 1 and 100 then
    raise exception 'Datos inválidos';
  end if;
  if not public.is_admin() and not exists (
    select 1 from public.partner_members pm where pm.partner_id=p_partner_id
      and pm.user_id=auth.uid() and pm.active and pm.role in ('owner','manager')
  ) then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then raise exception 'Entorno no autorizado'; end if;
  v_channel:=v_runtime->>'environment';
  select zone_id into v_zone from public.partner_organizations where id=p_partner_id and status='active';
  if v_zone is null then raise exception 'Sindicato no encontrado o inactivo'; end if;
  if not exists(select 1 from public.driver_profiles where id=p_driver_id and (zone_id is null or zone_id=v_zone)) then
    raise exception 'El conductor no pertenece a esta zona';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_partner_id::text||':'||p_driver_id::text,0));
  select id into v_membership_id from public.driver_partner_memberships
    where partner_id=p_partner_id and driver_id=p_driver_id and channel=v_channel
      and status in ('active','suspended') order by started_at desc nulls last limit 1 for update;
  if v_membership_id is null then
    insert into public.driver_partner_memberships(partner_id,driver_id,status,started_at,approved_by,member_number,channel)
    values(p_partner_id,p_driver_id,'active',now(),auth.uid(),p_member_number,v_channel);
  else
    update public.driver_partner_memberships set status='active',ended_at=null,
      approved_by=auth.uid(),member_number=p_member_number where id=v_membership_id;
  end if;
end $$;

create or replace function public.partner_completed_plan_summary(
  p_partner_id uuid, p_from timestamptz, p_to timestamptz
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_runtime jsonb; v_channel text;
begin
  if auth.uid() is null or (not public.is_admin() and not exists (
    select 1 from public.partner_members pm where pm.partner_id=p_partner_id
      and pm.user_id=auth.uid() and pm.active and pm.role in ('owner','manager','treasurer')
  )) then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then
    raise exception 'Entorno de datos no autorizado';
  end if;
  v_channel:=v_runtime->>'environment';
  return jsonb_build_object(
    'completed_count',(select count(*) from public.driver_subscription_payments pay
      where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel=v_channel
        and coalesce(pay.paid_at,pay.created_at)>=p_from and coalesce(pay.paid_at,pay.created_at)<p_to),
    'plans_total',(select coalesce(sum(pay.amount),0) from public.driver_subscription_payments pay
      where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel=v_channel
        and coalesce(pay.paid_at,pay.created_at)>=p_from and coalesce(pay.paid_at,pay.created_at)<p_to),
    'commission_estimated',(select coalesce(sum(pay.partner_commission_amount),0) from public.driver_subscription_payments pay
      where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel=v_channel
        and coalesce(pay.paid_at,pay.created_at)>=p_from and coalesce(pay.paid_at,pay.created_at)<p_to),
    'payments',(select coalesce(jsonb_agg(jsonb_build_object('payment_id',pay.id,'driver_id',pay.driver_id,
      'driver_name',coalesce(u.full_name,'Conductor'),
      'amount',pay.amount,'commission',pay.partner_commission_amount,'currency',pay.currency_code,
      'paid_at',coalesce(pay.paid_at,pay.created_at)) order by coalesce(pay.paid_at,pay.created_at) desc),'[]'::jsonb)
      from public.driver_subscription_payments pay left join public.users u on u.id=pay.driver_id
      where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel=v_channel
        and coalesce(pay.paid_at,pay.created_at)>=p_from and coalesce(pay.paid_at,pay.created_at)<p_to)
  );
end $$;

create or replace function public.partner_driver_list(p_partner_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_runtime jsonb; v_channel text;
begin
  if auth.uid() is null or (not public.is_admin() and not exists(
    select 1 from public.partner_members pm where pm.partner_id=p_partner_id
      and pm.user_id=auth.uid() and pm.active
  )) then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then raise exception 'Entorno no autorizado'; end if;
  v_channel:=v_runtime->>'environment';
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name),'[]'::jsonb)
    from (select dp.id driver_id,coalesce(u.full_name,au.email::text,'') full_name,
      coalesce(u.phone,'') phone,dp.approval_status,dp.online_status,dp.rating,
      dp.completed_trips,m.member_number,p.name partner_name,p.logo_url,p.brand_color
      from public.driver_partner_memberships m
      join public.partner_organizations p on p.id=m.partner_id
      join public.driver_profiles dp on dp.id=m.driver_id
      left join public.users u on u.id=dp.id left join auth.users au on au.id=dp.id
      where m.partner_id=p_partner_id and m.channel=v_channel and m.status in ('active','suspended')) x);
end $$;

create or replace function public.partner_search_drivers(
  p_partner_id uuid, p_query text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_zone uuid; v_query text:=trim(coalesce(p_query,'')); v_runtime jsonb; v_channel text;
begin
  if auth.uid() is null or (not public.is_admin() and not exists (
    select 1 from public.partner_members pm where pm.partner_id=p_partner_id
      and pm.user_id=auth.uid() and pm.active and pm.role in ('owner','manager')
  )) then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then raise exception 'Entorno no autorizado'; end if;
  v_channel:=v_runtime->>'environment';
  if length(v_query)<2 then raise exception 'Escribe al menos dos caracteres'; end if;
  select zone_id into v_zone from public.partner_organizations
    where id=p_partner_id and status='active';
  if v_zone is null then raise exception 'Sindicato no encontrado o inactivo'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.full_name),'[]'::jsonb)
    from (select dp.id driver_id,coalesce(u.full_name,au.email::text,'') full_name,
      coalesce(u.phone,'') phone
      from public.driver_profiles dp
      left join public.users u on u.id=dp.id left join auth.users au on au.id=dp.id
      where dp.zone_id=v_zone
        and (u.full_name ilike '%'||v_query||'%' or u.phone ilike '%'||v_query||'%'
          or au.email ilike '%'||v_query||'%')
        and not exists(select 1 from public.driver_partner_memberships m
          where m.partner_id=p_partner_id and m.driver_id=dp.id and m.channel=v_channel and m.status in ('active','suspended'))
      order by u.full_name limit 30) x);
end $$;

create or replace function public.partner_approve_join_request(
  p_request_id bigint, p_approve boolean, p_notes text default null,
  p_member_number smallint default null
) returns void language plpgsql security definer set search_path=public,auth as $$
declare v_req public.driver_partner_join_requests%rowtype; v_runtime jsonb; v_channel text; v_zone uuid;
begin
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then raise exception 'Entorno no autorizado'; end if;
  v_channel:=v_runtime->>'environment';
  select * into v_req from public.driver_partner_join_requests
    where id=p_request_id and status='pending' and channel=v_channel for update;
  if v_req.id is null then raise exception 'Solicitud no encontrada'; end if;
  if not public.is_admin() and not exists(
    select 1 from public.partner_members where partner_id=v_req.partner_id
      and user_id=auth.uid() and active and role in ('owner','manager','operator')
  ) then raise exception 'No autorizado'; end if;
  if p_approve and (p_member_number is null or p_member_number not between 1 and 100) then
    raise exception 'Asigna un número de socio del 1 al 100';
  end if;
  if p_approve then
    select zone_id into v_zone from public.partner_organizations
      where id=v_req.partner_id and status='active';
    if v_zone is null then raise exception 'Sindicato no encontrado o inactivo'; end if;
    if not exists(select 1 from public.driver_profiles where id=v_req.driver_id and (zone_id is null or zone_id=v_zone)) then
      raise exception 'El conductor no pertenece a esta zona';
    end if;
    if exists(select 1 from public.driver_partner_memberships
      where partner_id=v_req.partner_id and channel=v_channel and member_number=p_member_number
        and driver_id<>v_req.driver_id and status in ('active','suspended')) then raise exception 'Ese número de socio ya está ocupado'; end if;
  end if;
  update public.driver_partner_join_requests set
    status=case when p_approve then 'approved' else 'rejected' end,
    reviewed_at=now(),reviewed_by=auth.uid(),notes=nullif(trim(coalesce(p_notes,'')),'')
    where id=p_request_id;
  if p_approve then
    update public.driver_partner_memberships set status='ended',ended_at=now()
      where driver_id=v_req.driver_id and channel=v_channel and status='active';
    insert into public.driver_partner_memberships(driver_id,partner_id,approved_by,status,
      started_at,member_number,channel)
      values(v_req.driver_id,v_req.partner_id,auth.uid(),'active',now(),p_member_number,v_channel);
    update public.driver_profiles set zone_id=v_zone,updated_at=now() where id=v_req.driver_id;
  end if;
end $$;

create or replace function public.partner_join_request_list(p_partner_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_runtime jsonb; v_channel text;
begin
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then raise exception 'Entorno no autorizado'; end if;
  v_channel:=v_runtime->>'environment';
  if auth.uid() is null or (not public.is_admin() and not exists(
    select 1 from public.partner_members where partner_id=p_partner_id
      and user_id=auth.uid() and active and role in ('owner','manager','operator')
  )) then raise exception 'No autorizado'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.requested_at desc),'[]'::jsonb)
    from (select r.id,r.driver_id,coalesce(u.full_name,au.email::text,'') driver_name,
      r.status,r.requested_at,r.notes
      from public.driver_partner_join_requests r
      left join public.users u on u.id=r.driver_id left join auth.users au on au.id=r.driver_id
      where r.partner_id=p_partner_id and r.status='pending' and r.channel=v_channel) x);
end $$;

create or replace function public.driver_request_partner(p_partner_id uuid)
returns bigint language plpgsql security definer set search_path=public,auth as $$
declare v_id bigint; v_driver_zone uuid; v_partner_zone uuid; v_runtime jsonb; v_channel text;
begin
  if auth.uid() is null or not exists(select 1 from public.driver_profiles where id=auth.uid()) then
    raise exception 'No autorizado';
  end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then raise exception 'Entorno no autorizado'; end if;
  v_channel:=v_runtime->>'environment';
  select zone_id into v_driver_zone from public.driver_profiles where id=auth.uid();
  select zone_id into v_partner_zone from public.partner_organizations where id=p_partner_id and status='active';
  if v_partner_zone is null or v_driver_zone is distinct from v_partner_zone then
    raise exception 'Sindicato no disponible en tu zona';
  end if;
  update public.driver_partner_join_requests set status='cancelled',reviewed_at=now()
    where driver_id=auth.uid() and channel=v_channel and status='pending';
  insert into public.driver_partner_join_requests(driver_id,partner_id,channel)
    values(auth.uid(),p_partner_id,v_channel) returning id into v_id;
  return v_id;
end $$;

create or replace function public.partner_send_announcement(
  p_partner_id uuid,p_title text,p_body text
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_uid uuid:=auth.uid(); v_count integer:=0; v_title text:=trim(coalesce(p_title,''));
  v_body text:=trim(coalesce(p_body,'')); v_runtime jsonb; v_channel text;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then raise exception 'Entorno no autorizado'; end if;
  v_channel:=v_runtime->>'environment';
  if not public.is_admin() and not exists(
    select 1 from public.partner_members pm join public.partner_organizations po on po.id=pm.partner_id
    where pm.partner_id=p_partner_id and pm.user_id=v_uid and pm.active
      and pm.role in ('owner','manager','operator') and po.status='active'
  ) then raise exception 'No autorizado para esta organización'; end if;
  if char_length(v_title)<1 or char_length(v_title)>90 then raise exception 'Título inválido'; end if;
  if char_length(v_body)<1 or char_length(v_body)>1000 then raise exception 'Mensaje inválido'; end if;
  insert into public.notifications(user_id,title,body,type,metadata,channel)
    select u.id,v_title,v_body,'admin_announcement',jsonb_build_object(
      'audience','drivers','partner_id',p_partner_id,'campaign',true),v_channel
    from public.driver_partner_memberships m join public.users u on u.id=m.driver_id
    join public.driver_profiles dp on dp.id=m.driver_id
    where m.partner_id=p_partner_id and m.channel=v_channel and m.status='active'
      and u.account_status='active' and dp.approval_status='approved';
  get diagnostics v_count=row_count;
  return jsonb_build_object('recipients',v_count,'partner_id',p_partner_id,'channel',v_channel);
end $$;

create or replace function public.partner_set_membership_status(
  p_partner_id uuid,p_driver_id uuid,p_status text
) returns void language plpgsql security definer set search_path=public,auth as $$
declare v_runtime jsonb; v_channel text;
begin
  if auth.uid() is null or (not public.is_admin() and not exists(
    select 1 from public.partner_members pm where pm.partner_id=p_partner_id
      and pm.user_id=auth.uid() and pm.active and pm.role in ('owner','manager')
  )) then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then raise exception 'Entorno no autorizado'; end if;
  v_channel:=v_runtime->>'environment';
  if p_status not in ('active','suspended','removed') then raise exception 'Estado inválido'; end if;
  update public.driver_partner_memberships set status=p_status,
    ended_at=case when p_status='removed' then now() when p_status='active' then null else ended_at end,
    member_number=case when p_status='removed' then null else member_number end
  where partner_id=p_partner_id and driver_id=p_driver_id and channel=v_channel;
  if not found then raise exception 'El conductor no pertenece al sindicato'; end if;
end $$;

create or replace function public.partner_my_dashboard()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_runtime jsonb; v_channel text;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false then
    raise exception 'Entorno de datos no autorizado';
  end if;
  v_channel:=v_runtime->>'environment';
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'partner_id',p.id,'name',p.name,'logo_url',p.logo_url,'brand_color',p.brand_color,
    'role',case when public.is_admin() then 'admin' else pm.role end,
    'zone_id',p.zone_id,'commission_percent',p.commission_percent,
    'drivers_active',(select count(*) from public.driver_partner_memberships m where m.partner_id=p.id and m.channel=v_channel and m.status='active'),
    'commission_generated',(select coalesce(sum(pay.partner_commission_amount),0) from public.driver_subscription_payments pay where pay.partner_id=p.id and pay.status='approved' and pay.channel=v_channel),
    'commission_paid',(select coalesce(sum(s.commission_amount),0) from public.partner_settlements s where s.partner_id=p.id and s.status='paid' and s.channel=v_channel)
  ) order by p.name),'[]'::jsonb) from public.partner_organizations p
    left join public.partner_members pm on pm.partner_id=p.id
      and pm.user_id=auth.uid() and pm.active
    where p.status='active' and (public.is_admin() or pm.user_id is not null));
end $$;

create or replace function public.driver_partner_public_identity(p_trip_id uuid,p_driver_id uuid)
returns jsonb language sql security definer set search_path=public,auth as $$
  select jsonb_build_object('partner_id',p.id,'partner_name',p.name,
    'logo_url',p.logo_url,'brand_color',p.brand_color,'member_number',m.member_number)
  from public.trips t
  join public.driver_partner_memberships m on m.driver_id=t.driver_id
  join public.partner_organizations p on p.id=m.partner_id and p.status='active'
  where auth.uid() is not null and t.id=p_trip_id and t.driver_id=p_driver_id
    and t.passenger_id=auth.uid()
    and t.channel=(public.resolve_current_runtime_environment()->>'environment')
    and m.channel=t.channel and m.status='active'
  order by m.started_at desc nulls last limit 1
$$;

revoke execute on function public.partner_save_branding(uuid,text,text,text) from public,anon;
revoke execute on function public.partner_add_driver(uuid,uuid,smallint) from public,anon;
revoke execute on function public.partner_completed_plan_summary(uuid,timestamptz,timestamptz) from public,anon;
revoke all on function public.driver_partner_public_identity(uuid,uuid) from public,anon;
grant execute on function public.partner_save_branding(uuid,text,text,text) to authenticated;
grant execute on function public.partner_add_driver(uuid,uuid,smallint) to authenticated;
grant execute on function public.partner_completed_plan_summary(uuid,timestamptz,timestamptz) to authenticated;
revoke all on function public.partner_search_drivers(uuid,text) from public,anon;
grant execute on function public.partner_search_drivers(uuid,text) to authenticated;
revoke all on function public.partner_approve_join_request(bigint,boolean,text,smallint) from public,anon;
grant execute on function public.partner_approve_join_request(bigint,boolean,text,smallint) to authenticated;
revoke all on function public.partner_review_join_request(bigint,boolean,text) from public,anon,authenticated;
revoke all on function public.partner_join_request_list(uuid) from public,anon;
grant execute on function public.partner_join_request_list(uuid) to authenticated;
revoke all on function public.driver_request_partner(uuid) from public,anon;
grant execute on function public.driver_request_partner(uuid) to authenticated;
revoke all on function public.partner_send_announcement(uuid,text,text) from public,anon;
grant execute on function public.partner_send_announcement(uuid,text,text) to authenticated;
revoke execute on function public.partner_driver_list(uuid) from public,anon;
revoke execute on function public.partner_my_dashboard() from public,anon;
grant execute on function public.partner_driver_list(uuid) to authenticated;
grant execute on function public.partner_my_dashboard() to authenticated;
revoke execute on function public.partner_set_membership_status(uuid,uuid,text) from public,anon;
grant execute on function public.partner_set_membership_status(uuid,uuid,text) to authenticated;
grant execute on function public.driver_partner_public_identity(uuid,uuid) to authenticated;

-- Admin Express uses a local Preview store and the database only for Production.
-- The production RPCs therefore explicitly assert Production and exclude pending
-- plan-payment rows from every list and aggregate.
create or replace function public.admin_partner_payment_list(
  p_partner_id uuid, p_limit integer default 200
) returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
begin
  perform public.admin_assert_environment('production');
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
    from (select pay.id,pay.driver_id,coalesce(u.full_name,au.email::text,'') driver_name,
      pay.amount,pay.currency_code,pay.status,pay.provider,pay.partner_commission_percent,
      pay.partner_commission_amount,pay.created_at,pay.paid_at
      from public.driver_subscription_payments pay
      left join public.users u on u.id=pay.driver_id
      left join auth.users au on au.id=pay.driver_id
      where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel='production'
      order by pay.created_at desc limit greatest(1,least(coalesce(p_limit,200),500))) x);
end $$;

create or replace function public.admin_partner_settlement_list(p_partner_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  perform public.admin_assert_environment('production');
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at desc),'[]'::jsonb)
    from public.partner_settlements s
    where s.partner_id=p_partner_id and s.channel='production');
end $$;

create or replace function public.admin_partner_dashboard(
  p_partner_id uuid,p_from timestamptz default null,p_to timestamptz default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_partner jsonb;
begin
  perform public.admin_assert_environment('production');
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select jsonb_build_object('id',p.id,'name',p.name,'partner_code',p.partner_code,
    'organization_type',p.organization_type,'status',p.status,
    'commission_percent',p.commission_percent,'zone_id',p.zone_id,
    'zone_name',z.name,'currency_code',z.currency_code)
  into v_partner from public.partner_organizations p
  left join public.service_zones z on z.id=p.zone_id where p.id=p_partner_id;
  if v_partner is null then raise exception 'Aliado no encontrado'; end if;
  return jsonb_build_object('partner',v_partner,
    'metrics',jsonb_build_object(
      'drivers_total',(select count(*) from public.driver_partner_memberships m where m.partner_id=p_partner_id and m.status='active'),
      'drivers_online',(select count(*) from public.driver_partner_memberships m join public.driver_profiles d on d.id=m.driver_id where m.partner_id=p_partner_id and m.status='active' and d.online_status='online'),
      'payments_count',(select count(*) from public.driver_subscription_payments pay where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel='production' and (p_from is null or coalesce(pay.paid_at,pay.created_at)>=p_from) and (p_to is null or coalesce(pay.paid_at,pay.created_at)<p_to)),
      'gross_amount',(select coalesce(sum(pay.amount),0) from public.driver_subscription_payments pay where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel='production' and (p_from is null or coalesce(pay.paid_at,pay.created_at)>=p_from) and (p_to is null or coalesce(pay.paid_at,pay.created_at)<p_to)),
      'commission_generated',(select coalesce(sum(pay.partner_commission_amount),0) from public.driver_subscription_payments pay where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel='production' and (p_from is null or coalesce(pay.paid_at,pay.created_at)>=p_from) and (p_to is null or coalesce(pay.paid_at,pay.created_at)<p_to)),
      'commission_paid',(select coalesce(sum(s.commission_amount),0) from public.partner_settlements s where s.partner_id=p_partner_id and s.status='paid' and s.channel='production' and (p_from is null or coalesce(s.paid_at,s.created_at)>=p_from) and (p_to is null or coalesce(s.paid_at,s.created_at)<p_to)),
      'commission_pending',(select greatest(coalesce((select sum(pay.partner_commission_amount) from public.driver_subscription_payments pay where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel='production'),0)-coalesce((select sum(s.commission_amount) from public.partner_settlements s where s.partner_id=p_partner_id and s.status='paid' and s.channel='production'),0),0))
    ),
    'payments',public.admin_partner_payment_list(p_partner_id,100),
    'settlements',public.admin_partner_settlement_list(p_partner_id));
end $$;

create or replace function public.admin_partner_list(p_zone_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  p_zone_id:=public.admin_scope_zone(p_zone_id);
  perform public.admin_assert_environment('production');
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]'::jsonb)
    from (select p.id,p.zone_id,p.partner_code,p.name,p.organization_type,p.status,
      p.commission_percent,p.contact_name,p.contact_phone,p.contact_email,p.notes,
      p.created_at,p.updated_at,p.logo_url,p.brand_color,
      (select count(*)::int from public.driver_partner_memberships m
        where m.partner_id=p.id and m.status='active') drivers_active,
      (select coalesce(sum(pay.amount),0)::numeric from public.driver_subscription_payments pay
        where pay.partner_id=p.id and pay.status='approved' and pay.channel='production') payments_approved,
      (select coalesce(sum(pay.partner_commission_amount),0)::numeric from public.driver_subscription_payments pay
        where pay.partner_id=p.id and pay.status='approved' and pay.channel='production') commission_generated,
      (select coalesce(sum(s.commission_amount),0)::numeric from public.partner_settlements s
        where s.partner_id=p.id and s.status='paid' and s.channel='production') commission_paid
      from public.partner_organizations p
      where p.zone_id=p_zone_id) x);
end $$;

create or replace function public.admin_create_partner_settlement(
  p_partner_id uuid,p_period_start timestamptz default null,
  p_period_end timestamptz default null,p_notes text default null
) returns bigint language plpgsql security definer set search_path=public as $$
declare v_id bigint; v_zone uuid; v_currency text;
begin
  perform public.admin_assert_environment('production');
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select p.zone_id,z.currency_code into v_zone,v_currency
    from public.partner_organizations p join public.service_zones z on z.id=p.zone_id
    where p.id=p_partner_id;
  if v_zone is null then raise exception 'Aliado no encontrado'; end if;
  insert into public.partner_settlements(partner_id,zone_id,period_start,period_end,currency_code,notes,created_by,channel)
  values(p_partner_id,v_zone,p_period_start,p_period_end,v_currency,
    nullif(trim(coalesce(p_notes,'')),''),auth.uid(),'production') returning id into v_id;
  insert into public.partner_settlement_items(settlement_id,payment_id,gross_amount,commission_amount)
  select v_id,pay.id,pay.amount,coalesce(pay.partner_commission_amount,0)
    from public.driver_subscription_payments pay
    where pay.partner_id=p_partner_id and pay.status='approved' and pay.channel='production'
      and (p_period_start is null or coalesce(pay.paid_at,pay.updated_at)>=p_period_start)
      and (p_period_end is null or coalesce(pay.paid_at,pay.updated_at)<=p_period_end)
      and not exists(select 1 from public.partner_settlement_items i where i.payment_id=pay.id);
  update public.partner_settlements s set gross_amount=coalesce(x.gross,0),commission_amount=coalesce(x.commission,0)
    from (select settlement_id,sum(gross_amount) gross,sum(commission_amount) commission
      from public.partner_settlement_items where settlement_id=v_id group by settlement_id) x
    where s.id=v_id;
  return v_id;
end $$;

revoke all on function public.admin_partner_payment_list(uuid,integer) from public,anon;
grant execute on function public.admin_partner_payment_list(uuid,integer) to authenticated;
revoke all on function public.admin_partner_settlement_list(uuid) from public,anon;
grant execute on function public.admin_partner_settlement_list(uuid) to authenticated;
revoke all on function public.admin_partner_dashboard(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.admin_partner_dashboard(uuid,timestamptz,timestamptz) to authenticated;
revoke all on function public.admin_partner_list(uuid) from public,anon;
grant execute on function public.admin_partner_list(uuid) to authenticated;
revoke all on function public.admin_create_partner_settlement(uuid,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.admin_create_partner_settlement(uuid,timestamptz,timestamptz,text) to authenticated;
commit;
