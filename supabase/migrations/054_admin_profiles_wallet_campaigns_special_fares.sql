-- Admin profiles, wallet subscriptions, targeted campaigns and special fixed fares.
-- This migration mirrors the production changes introduced after 053.

alter table public.users
  add column if not exists last_zone_id uuid
  references public.service_zones(id) on delete set null;

create index if not exists users_last_zone_idx
  on public.users(last_zone_id,account_status);

create table if not exists public.driver_documents(
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.driver_profiles(id) on delete cascade,
  document_type text not null,
  document_number text,
  document_url text,
  status text not null default 'pending'
    check(status in ('pending','verified','rejected','expired')),
  expires_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists driver_documents_driver_idx
  on public.driver_documents(driver_id,status,created_at desc);
alter table public.driver_documents enable row level security;
revoke all on public.driver_documents from anon,authenticated;

alter table public.notifications
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create table if not exists public.fare_special_zones(
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  name text not null,
  zone_type text not null default 'custom'
    check(zone_type in ('airport','terminal','custom')),
  service_key text not null references public.service_catalog(service_key),
  polygon jsonb not null default '[]'::jsonb,
  fixed_fare numeric not null check(fixed_fare>0),
  priority integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists fare_special_zones_lookup_idx
  on public.fare_special_zones(zone_id,service_key,active,priority desc);
alter table public.fare_special_zones enable row level security;
revoke all on public.fare_special_zones from anon,authenticated;

alter table public.ride_requests
  add column if not exists special_fare_zone_id uuid
    references public.fare_special_zones(id) on delete set null,
  add column if not exists special_fare_zone_name text;

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
      select jsonb_agg(x order by x.created_at desc)
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
$function$

CREATE OR REPLACE FUNCTION public.admin_driver_list_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'user_id',d.id,
          'full_name',u.full_name,
          'email',au.email,
          'phone',u.phone,
          'approval_status',d.approval_status,
          'online_status',d.online_status,
          'license_number',d.license_number,
          'vehicle_summary',d.vehicle_summary,
          'city',d.city,
          'rating',d.rating,
          'completed_trips',d.completed_trips,
          'zone_id',d.zone_id,
          'zone_key',z.zone_key,
          'zone_name',z.name,
          'currency_code',z.currency_code,
          'is_qa',
            (
              exists(
                select 1
                from public.audit_test_group_members m
                join public.audit_test_groups g on g.id=m.group_id
                where m.user_id=d.id and m.enabled=true and g.active=true
              )
              or (
                lower(coalesce(au.email,'')) like 'qa-%@expressdelivery.pro'
                or lower(coalesce(u.full_name,'')) like 'qa %'
              )
            ),
          'partner_id',pm.partner_id,
          'partner_name',po.name,
          'created_at',d.created_at
        )
        order by
          case d.approval_status
            when 'pending' then 0
            when 'approved' then 1
            else 2
          end,
          d.created_at desc
      ),
      '[]'::jsonb
    )
    from public.driver_profiles d
    join public.users u on u.id=d.id
    left join auth.users au on au.id=d.id
    left join public.service_zones z on z.id=d.zone_id
    left join lateral (
      select x.partner_id
      from public.driver_partner_memberships x
      where x.driver_id=d.id and x.status='active'
      order by x.started_at desc
      limit 1
    ) pm on true
    left join public.partner_organizations po on po.id=pm.partner_id
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_partner_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',p.id,
          'partner_code',p.partner_code,
          'name',p.name,
          'organization_type',p.organization_type,
          'status',p.status,
          'commission_percent',p.commission_percent,
          'zone_id',p.zone_id,
          'zone_name',z.name,
          'zone_key',z.zone_key,
          'contact_name',p.contact_name,
          'contact_phone',p.contact_phone,
          'contact_email',p.contact_email
        )
        order by z.name,p.name
      ),
      '[]'::jsonb
    )
    from public.partner_organizations p
    left join public.service_zones z on z.id=p.zone_id
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_partner_list(p_zone_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]'::jsonb)
    from (
      select
        p.id, p.zone_id, p.partner_code, p.name, p.organization_type, p.status,
        p.commission_percent, p.contact_name, p.contact_phone, p.contact_email,
        p.notes, p.created_at, p.updated_at,
        count(distinct m.driver_id) filter (where m.status='active')::int as drivers_active,
        coalesce(sum(pay.amount) filter (where pay.status='approved'),0)::numeric as payments_approved,
        coalesce(sum(pay.partner_commission_amount) filter (where pay.status='approved'),0)::numeric as commission_generated,
        coalesce((
          select sum(s.commission_amount)
          from public.partner_settlements s
          where s.partner_id=p.id and s.status='paid'
        ),0)::numeric as commission_paid
      from public.partner_organizations p
      left join public.driver_partner_memberships m on m.partner_id=p.id
      left join public.driver_subscription_payments pay on pay.partner_id=p.id
      where p.zone_id=p_zone_id
      group by p.id
    ) x
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_send_announcement_v2(p_title text, p_body text, p_audience text DEFAULT 'drivers'::text, p_zone_id uuid DEFAULT NULL::uuid, p_partner_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count integer:=0;
  v_title text:=trim(coalesce(p_title,''));
  v_body text:=trim(coalesce(p_body,''));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if char_length(v_title)<1 or char_length(v_title)>90 then
    raise exception 'Título inválido';
  end if;
  if char_length(v_body)<1 or char_length(v_body)>1000 then
    raise exception 'Mensaje inválido';
  end if;
  if p_audience not in ('drivers','passengers','all') then
    raise exception 'Audiencia inválida';
  end if;
  if p_zone_id is not null
     and not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active=true) then
    raise exception 'Zona inválida';
  end if;
  if p_partner_id is not null
     and not exists(select 1 from public.partner_organizations p where p.id=p_partner_id and p.status='active') then
    raise exception 'Empresa/organización inválida';
  end if;

  insert into public.notifications(user_id,title,body,type,metadata)
  select
    u.id,
    v_title,
    v_body,
    'admin_announcement',
    jsonb_strip_nulls(jsonb_build_object(
      'audience',p_audience,
      'zone_id',p_zone_id,
      'partner_id',p_partner_id,
      'campaign',true
    ))
  from public.users u
  left join public.driver_profiles dp on dp.id=u.id
  where u.account_status='active'
    and (
      p_audience='all'
      or (
        p_audience='drivers'
        and dp.id is not null
        and dp.approval_status='approved'
      )
      or (
        p_audience='passengers'
        and (
          u.active_mode='passenger'
          or dp.id is null
          or dp.approval_status<>'approved'
        )
      )
    )
    and (
      p_zone_id is null
      or coalesce(u.last_zone_id,dp.zone_id)=p_zone_id
    )
    and (
      p_partner_id is null
      or exists(
        select 1
        from public.driver_partner_memberships m
        where m.driver_id=u.id
          and m.partner_id=p_partner_id
          and m.status='active'
      )
    );

  get diagnostics v_count=row_count;

  perform public.admin_log_action(
    'send_announcement',
    'notifications',
    coalesce(p_partner_id::text,p_zone_id::text,p_audience),
    jsonb_strip_nulls(jsonb_build_object(
      'title',v_title,
      'recipients',v_count,
      'audience',p_audience,
      'zone_id',p_zone_id,
      'partner_id',p_partner_id
    ))
  );

  return jsonb_build_object(
    'recipients',v_count,
    'audience',p_audience,
    'zone_id',p_zone_id,
    'partner_id',p_partner_id
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_special_fare_list(p_zone_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(
      jsonb_agg(to_jsonb(s) order by s.priority desc,s.name),
      '[]'::jsonb
    )
    from public.fare_special_zones s
    where s.zone_id=p_zone_id
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_trip_detail(p_trip_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select jsonb_build_object(
    'trip',to_jsonb(t),
    'request',to_jsonb(rr),
    'zone',case when z.id is null then null else to_jsonb(z) end,
    'passenger',jsonb_build_object(
      'id',pu.id,'full_name',pu.full_name,'phone',pu.phone
    ),
    'driver',jsonb_build_object(
      'id',du.id,'full_name',du.full_name,'phone',du.phone
    ),
    'payments',coalesce((
      select jsonb_agg(to_jsonb(p) order by p.created_at desc)
      from public.payment_transactions p
      where p.trip_id=t.id
    ),'[]'::jsonb),
    'wallet_movements',coalesce((
      select jsonb_agg(to_jsonb(wt) order by wt.created_at desc)
      from public.wallet_transactions wt
      where wt.trip_id=t.id
    ),'[]'::jsonb),
    'status_history',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',h.id,
          'status',h.status,
          'changed_by',h.changed_by,
          'changed_by_name',hu.full_name,
          'created_at',h.created_at
        )
        order by h.created_at
      )
      from public.trip_status_history h
      left join public.users hu on hu.id=h.changed_by
      where h.trip_id=t.id
    ),'[]'::jsonb),
    'ratings',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',r.id,
          'from_user_id',r.from_user_id,
          'to_user_id',r.to_user_id,
          'score',r.score,
          'comment',r.comment,
          'created_at',r.created_at
        )
        order by r.created_at
      )
      from public.ratings r
      where r.trip_id=t.id
    ),'[]'::jsonb)
  )
  into v_result
  from public.trips t
  left join public.ride_requests rr on rr.id=t.ride_request_id
  left join public.users pu on pu.id=t.passenger_id
  left join public.users du on du.id=t.driver_id
  left join public.service_zones z on z.id=rr.zone_id
  where t.id=p_trip_id;

  if v_result is null then
    raise exception 'Viaje no encontrado';
  end if;
  return v_result;
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_update_driver_profile(p_user_id uuid, p_full_name text, p_phone text, p_account_status text, p_license_number text, p_city text, p_zone_id uuid, p_approval_status text, p_online_status text, p_vehicle_type text, p_vehicle_brand text, p_vehicle_model text, p_vehicle_color text, p_vehicle_plate text, p_vehicle_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_vehicle_id uuid;
  v_summary text;
  v_online text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_account_status not in ('active','suspended','blocked') then
    raise exception 'Estado de cuenta inválido';
  end if;
  if p_approval_status not in ('pending','approved','rejected','suspended') then
    raise exception 'Estado de conductor inválido';
  end if;
  if p_online_status not in ('online','offline','busy') then
    raise exception 'Estado operativo inválido';
  end if;
  if p_vehicle_type not in ('car','motorcycle','xl') then
    raise exception 'Tipo de vehículo inválido';
  end if;
  if p_zone_id is null
     or not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active=true) then
    raise exception 'Zona inválida';
  end if;

  v_summary=trim(concat_ws(' ',
    nullif(trim(p_vehicle_brand),''),
    nullif(trim(p_vehicle_model),'')
  ));
  if nullif(trim(p_vehicle_plate),'') is not null then
    v_summary=trim(v_summary || ' · ' || trim(p_vehicle_plate));
  end if;

  update public.users
  set full_name=nullif(trim(p_full_name),''),
      phone=nullif(trim(p_phone),''),
      account_status=p_account_status,
      last_zone_id=p_zone_id,
      updated_at=now()
  where id=p_user_id;
  if not found then raise exception 'Usuario no encontrado'; end if;

  update public.driver_profiles
  set license_number=nullif(trim(p_license_number),''),
      vehicle_summary=nullif(v_summary,''),
      city=nullif(trim(p_city),''),
      zone_id=p_zone_id,
      approval_status=p_approval_status,
      online_status='offline',
      updated_at=now()
  where id=p_user_id;
  if not found then raise exception 'Conductor no encontrado'; end if;

  select id into v_vehicle_id
  from public.driver_vehicles
  where driver_id=p_user_id
  order by is_active desc,updated_at desc
  limit 1;

  update public.driver_vehicles
  set is_active=false,updated_at=now()
  where driver_id=p_user_id;

  if v_vehicle_id is null then
    insert into public.driver_vehicles(
      driver_id,vehicle_type,brand,model,color,plate,year,is_active,updated_at
    )
    values(
      p_user_id,p_vehicle_type,
      nullif(trim(p_vehicle_brand),''),
      nullif(trim(p_vehicle_model),''),
      nullif(trim(p_vehicle_color),''),
      nullif(trim(p_vehicle_plate),''),
      p_vehicle_year,true,now()
    );
  else
    update public.driver_vehicles
    set vehicle_type=p_vehicle_type,
        brand=nullif(trim(p_vehicle_brand),''),
        model=nullif(trim(p_vehicle_model),''),
        color=nullif(trim(p_vehicle_color),''),
        plate=nullif(trim(p_vehicle_plate),''),
        year=p_vehicle_year,
        is_active=true,
        updated_at=now()
    where id=v_vehicle_id;
  end if;

  v_online := case
    when p_account_status='active'
      and p_approval_status='approved'
      and p_online_status in ('online','busy')
      and public.driver_subscription_allows_dispatch(p_user_id)
    then p_online_status
    else 'offline'
  end;

  update public.driver_profiles
  set online_status=v_online,updated_at=now()
  where id=p_user_id;

  perform public.admin_log_action(
    'update_driver_profile','driver_profile',p_user_id::text,
    jsonb_build_object(
      'approval_status',p_approval_status,
      'online_status',v_online,
      'zone_id',p_zone_id,
      'vehicle_type',p_vehicle_type,
      'plate',nullif(trim(p_vehicle_plate),'')
    )
  );

  return public.admin_driver_detail(p_user_id);
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_update_user_profile(p_user_id uuid, p_full_name text, p_phone text, p_active_mode text, p_account_status text, p_zone_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user public.users%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_active_mode not in ('passenger','driver') then
    raise exception 'Modo inválido';
  end if;
  if p_account_status not in ('active','suspended','blocked') then
    raise exception 'Estado de cuenta inválido';
  end if;
  if p_zone_id is not null
     and not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active=true) then
    raise exception 'Zona inválida';
  end if;

  update public.users
  set full_name=nullif(trim(p_full_name),''),
      phone=nullif(trim(p_phone),''),
      active_mode=p_active_mode,
      account_status=p_account_status,
      last_zone_id=p_zone_id,
      updated_at=now()
  where id=p_user_id
  returning * into v_user;

  if not found then raise exception 'Usuario no encontrado'; end if;

  if p_account_status<>'active' then
    update public.driver_profiles
    set online_status='offline',updated_at=now()
    where id=p_user_id;
  end if;

  perform public.admin_log_action(
    'update_user_profile','user',p_user_id::text,
    jsonb_build_object(
      'full_name',v_user.full_name,
      'phone',v_user.phone,
      'active_mode',v_user.active_mode,
      'account_status',v_user.account_status,
      'zone_id',v_user.last_zone_id
    )
  );

  return to_jsonb(v_user);
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_upsert_driver_document(p_document_id uuid, p_driver_id uuid, p_document_type text, p_document_number text, p_document_url text, p_status text, p_expires_at timestamp with time zone, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_doc public.driver_documents%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_status not in ('pending','verified','rejected','expired') then
    raise exception 'Estado de documento inválido';
  end if;
  if not exists(select 1 from public.driver_profiles where id=p_driver_id) then
    raise exception 'Conductor no encontrado';
  end if;

  if p_document_id is null then
    insert into public.driver_documents(
      driver_id,document_type,document_number,document_url,status,expires_at,notes
    )
    values(
      p_driver_id,trim(p_document_type),
      nullif(trim(p_document_number),''),
      nullif(trim(p_document_url),''),
      p_status,p_expires_at,nullif(trim(p_notes),'')
    )
    returning * into v_doc;
  else
    update public.driver_documents
    set document_type=trim(p_document_type),
        document_number=nullif(trim(p_document_number),''),
        document_url=nullif(trim(p_document_url),''),
        status=p_status,
        expires_at=p_expires_at,
        notes=nullif(trim(p_notes),''),
        updated_at=now()
    where id=p_document_id and driver_id=p_driver_id
    returning * into v_doc;
    if not found then raise exception 'Documento no encontrado'; end if;
  end if;

  perform public.admin_log_action(
    'upsert_driver_document','driver_document',v_doc.id::text,
    jsonb_build_object(
      'driver_id',p_driver_id,
      'document_type',v_doc.document_type,
      'status',v_doc.status
    )
  );
  return to_jsonb(v_doc);
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_upsert_special_fare_zone(p_id uuid, p_zone_id uuid, p_name text, p_zone_type text, p_service_key text, p_polygon jsonb, p_fixed_fare numeric, p_priority integer, p_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.fare_special_zones%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_zone_type not in ('airport','terminal','custom') then
    raise exception 'Tipo de zona especial inválido';
  end if;
  if p_fixed_fare is null or p_fixed_fare<=0 then
    raise exception 'La tarifa fija debe ser mayor a cero';
  end if;
  if jsonb_typeof(coalesce(p_polygon,'[]'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_polygon,'[]'::jsonb))<3 then
    raise exception 'El polígono debe tener al menos 3 puntos';
  end if;

  if p_id is null then
    insert into public.fare_special_zones(
      zone_id,name,zone_type,service_key,polygon,
      fixed_fare,priority,active
    )
    values(
      p_zone_id,trim(p_name),p_zone_type,p_service_key,p_polygon,
      p_fixed_fare,coalesce(p_priority,100),coalesce(p_active,true)
    )
    returning * into v_row;
  else
    update public.fare_special_zones
    set zone_id=p_zone_id,
        name=trim(p_name),
        zone_type=p_zone_type,
        service_key=p_service_key,
        polygon=p_polygon,
        fixed_fare=p_fixed_fare,
        priority=coalesce(p_priority,100),
        active=coalesce(p_active,true),
        updated_at=now()
    where id=p_id
    returning * into v_row;
    if not found then raise exception 'Zona especial no encontrada'; end if;
  end if;

  perform public.admin_log_action(
    'upsert_special_fare_zone','special_fare_zone',v_row.id::text,
    jsonb_build_object(
      'zone_id',v_row.zone_id,
      'name',v_row.name,
      'zone_type',v_row.zone_type,
      'service_key',v_row.service_key,
      'fixed_fare',v_row.fixed_fare,
      'priority',v_row.priority,
      'active',v_row.active
    )
  );

  return to_jsonb(v_row);
end;
$function$

CREATE OR REPLACE FUNCTION public.admin_user_detail(p_user_id uuid)
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
      select jsonb_agg(x order by x.created_at desc)
      from (
        select jsonb_build_object(
          'id',t.id,
          'role',case when t.passenger_id=u.id then 'passenger' else 'driver' end,
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
$function$

CREATE OR REPLACE FUNCTION public.admin_user_list_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'user_id',u.id,
          'full_name',u.full_name,
          'email',au.email,
          'phone',u.phone,
          'active_mode',u.active_mode,
          'account_status',u.account_status,
          'driver_status',d.approval_status,
          'zone_id',coalesce(u.last_zone_id,d.zone_id),
          'zone_key',z.zone_key,
          'zone_name',z.name,
          'is_qa',
            (
              exists(
                select 1
                from public.audit_test_group_members m
                join public.audit_test_groups g on g.id=m.group_id
                where m.user_id=u.id and m.enabled=true and g.active=true
              )
              or (
                lower(coalesce(au.email,'')) like 'qa-%@expressdelivery.pro'
                or lower(coalesce(u.full_name,'')) like 'qa %'
              )
            ),
          'created_at',u.created_at
        )
        order by u.created_at desc
      ),
      '[]'::jsonb
    )
    from public.users u
    left join auth.users au on au.id=u.id
    left join public.driver_profiles d on d.id=u.id
    left join public.service_zones z on z.id=coalesce(u.last_zone_id,d.zone_id)
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.apply_special_fixed_fare()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone_id uuid;
  v_special jsonb;
  v_currency text;
begin
  if new.pickup_latitude is null
     or new.pickup_longitude is null
     or new.destination_latitude is null
     or new.destination_longitude is null then
    new.special_fare_zone_id:=null;
    new.special_fare_zone_name:=null;
    return new;
  end if;

  v_zone_id:=coalesce(
    new.zone_id,
    public.service_zone_id_for_point(
      new.pickup_latitude,new.pickup_longitude
    )
  );

  if v_zone_id is null then
    return new;
  end if;

  v_special:=public.special_fare_for_route(
    v_zone_id,new.category,
    new.pickup_latitude,new.pickup_longitude,
    new.destination_latitude,new.destination_longitude
  );

  if v_special is null then
    new.special_fare_zone_id:=null;
    new.special_fare_zone_name:=null;
    return new;
  end if;

  select currency_code into v_currency
  from public.service_zones
  where id=v_zone_id;

  new.zone_id:=v_zone_id;
  new.proposed_fare:=(v_special->>'fixed_fare')::numeric;
  new.base_fare:=new.proposed_fare;
  new.pricing_mode:='fixed';
  new.currency:=coalesce(v_currency,new.currency);
  new.demand_multiplier:=1;
  new.special_fare_zone_id:=(v_special->>'id')::uuid;
  new.special_fare_zone_name:=v_special->>'name';

  return new;
end;
$function$

CREATE OR REPLACE FUNCTION public.ensure_wallet()
 RETURNS wallet_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_wallet public.wallet_accounts%rowtype;
  v_currency text := 'BOB';
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select coalesce(z.currency_code,'BOB')
  into v_currency
  from public.users u
  left join public.driver_profiles dp on dp.id=u.id
  left join public.service_zones z on z.id=coalesce(u.last_zone_id,dp.zone_id)
  where u.id=auth.uid();

  insert into public.wallet_accounts(user_id,currency)
  values(auth.uid(),coalesce(v_currency,'BOB'))
  on conflict(user_id) do update
    set currency=case
      when public.wallet_accounts.balance=0
        then excluded.currency
      else public.wallet_accounts.currency
    end,
    updated_at=case
      when public.wallet_accounts.balance=0
        and public.wallet_accounts.currency is distinct from excluded.currency
        then now()
      else public.wallet_accounts.updated_at
    end;

  select * into v_wallet
  from public.wallet_accounts
  where user_id=auth.uid();

  return v_wallet;
end;
$function$

CREATE OR REPLACE FUNCTION public.partner_send_announcement(p_partner_id uuid, p_title text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_count integer:=0;
  v_title text:=trim(coalesce(p_title,''));
  v_body text:=trim(coalesce(p_body,''));
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  if not exists(
    select 1
    from public.partner_members pm
    join public.partner_organizations po on po.id=pm.partner_id
    where pm.partner_id=p_partner_id
      and pm.user_id=v_uid
      and pm.active=true
      and pm.role in ('owner','manager','operator')
      and po.status='active'
  ) then
    raise exception 'No autorizado para esta organización';
  end if;

  if char_length(v_title)<1 or char_length(v_title)>90 then
    raise exception 'Título inválido';
  end if;
  if char_length(v_body)<1 or char_length(v_body)>1000 then
    raise exception 'Mensaje inválido';
  end if;

  insert into public.notifications(user_id,title,body,type,metadata)
  select
    u.id,
    v_title,
    v_body,
    'admin_announcement',
    jsonb_build_object(
      'audience','drivers',
      'partner_id',p_partner_id,
      'campaign',true
    )
  from public.driver_partner_memberships m
  join public.users u on u.id=m.driver_id
  join public.driver_profiles dp on dp.id=m.driver_id
  where m.partner_id=p_partner_id
    and m.status='active'
    and u.account_status='active'
    and dp.approval_status='approved';

  get diagnostics v_count=row_count;

  return jsonb_build_object(
    'recipients',v_count,
    'partner_id',p_partner_id
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.pay_driver_subscription_with_wallet(p_plan_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_plan public.driver_subscription_plans%rowtype;
  v_zone public.service_zones%rowtype;
  v_zone_settings public.driver_subscription_zone_settings%rowtype;
  v_wallet public.wallet_accounts%rowtype;
  v_payment public.driver_subscription_payments%rowtype;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Sesión requerida';
  end if;

  if not exists(select 1 from public.driver_profiles d where d.id=v_uid) then
    raise exception 'Perfil de conductor requerido';
  end if;

  select p.* into v_plan
  from public.driver_subscription_plans p
  where p.id=p_plan_id and p.active=true;
  if not found then raise exception 'Plan no disponible'; end if;

  select z.* into v_zone
  from public.driver_profiles d
  join public.service_zones z on z.id=d.zone_id
  where d.id=v_uid and z.active=true;
  if not found then
    raise exception 'No se pudo determinar la zona del conductor';
  end if;

  if v_plan.zone_key<>v_zone.zone_key then
    raise exception 'El plan no está disponible en tu zona actual';
  end if;

  select * into v_zone_settings
  from public.driver_subscription_zone_settings
  where zone_id=v_zone.id;

  if not found or not coalesce(v_zone_settings.enabled,false) then
    raise exception 'Las suscripciones no están habilitadas en esta zona';
  end if;

  perform public.ensure_wallet();

  select * into v_wallet
  from public.wallet_accounts
  where user_id=v_uid
  for update;

  if upper(coalesce(v_wallet.currency,''))<>upper(coalesce(v_plan.currency_code,'')) then
    raise exception
      'La billetera está en % y este plan se cobra en %. No se mezclan monedas.',
      v_wallet.currency,v_plan.currency_code;
  end if;

  if coalesce(v_wallet.balance,0)<v_plan.amount then
    raise exception 'Saldo insuficiente en la billetera';
  end if;

  insert into public.driver_subscription_payments(
    driver_id,plan_id,amount,currency_code,provider,status,
    provider_data,paid_at,expires_at,zone_key
  )
  values(
    v_uid,v_plan.id,v_plan.amount,v_plan.currency_code,
    'wallet','pending',
    jsonb_build_object(
      'source','express_wallet',
      'balance_before',v_wallet.balance
    ),
    now(),now()+interval '15 minutes',v_plan.zone_key
  )
  returning * into v_payment;

  update public.wallet_accounts
  set balance=balance-v_plan.amount,
      updated_at=now()
  where user_id=v_uid;

  insert into public.wallet_transactions(
    user_id,amount,type,status,reference,created_at
  )
  values(
    v_uid,
    -v_plan.amount,
    'payment',
    'completed',
    'driver_subscription:'||v_payment.id::text,
    now()
  );

  v_result:=public.service_finalize_driver_subscription_payment(
    v_payment.id,
    'wallet-'||v_payment.id::text,
    jsonb_build_object(
      'source','express_wallet',
      'balance_before',v_wallet.balance,
      'balance_after',v_wallet.balance-v_plan.amount
    )
  );

  update public.driver_subscription_history
  set notes='Billetera Express',
      zone_key=v_plan.zone_key
  where payment_id=v_payment.id
    and action='payment_approved';

  insert into public.notifications(user_id,title,body,type,metadata)
  values(
    v_uid,
    'Suscripción activada',
    'Tu plan '||v_plan.name||' fue pagado con Billetera Express.',
    'driver_subscription',
    jsonb_build_object(
      'payment_id',v_payment.id,
      'plan_id',v_plan.id,
      'zone_key',v_plan.zone_key,
      'provider','wallet'
    )
  );

  return v_result || jsonb_build_object(
    'provider','wallet',
    'payment_id',v_payment.id,
    'balance_before',v_wallet.balance,
    'balance_after',v_wallet.balance-v_plan.amount,
    'currency_code',v_plan.currency_code
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.set_my_zone_from_location(p_lat numeric, p_lng numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_zone_id uuid;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_zone_id:=public.service_zone_id_for_point(p_lat,p_lng);

  update public.users
  set last_zone_id=v_zone_id,
      updated_at=case
        when last_zone_id is distinct from v_zone_id then now()
        else updated_at
      end
  where id=v_uid
    and last_zone_id is distinct from v_zone_id;

  return v_zone_id;
end;
$function$

CREATE OR REPLACE FUNCTION public.special_fare_for_my_route(p_service_key text, p_pickup_lat numeric, p_pickup_lng numeric, p_destination_lat numeric, p_destination_lng numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone_id uuid;
  v_zone public.service_zones%rowtype;
  v_special jsonb;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;

  v_zone_id:=public.service_zone_id_for_point(p_pickup_lat,p_pickup_lng);
  if v_zone_id is null then
    return jsonb_build_object('matched',false);
  end if;

  select * into v_zone
  from public.service_zones
  where id=v_zone_id;

  v_special:=public.special_fare_for_route(
    v_zone_id,p_service_key,
    p_pickup_lat,p_pickup_lng,
    p_destination_lat,p_destination_lng
  );

  if v_special is null then
    return jsonb_build_object(
      'matched',false,
      'zone_id',v_zone_id,
      'zone_name',v_zone.name,
      'currency',v_zone.currency_code
    );
  end if;

  return jsonb_build_object(
    'matched',true,
    'zone_id',v_zone_id,
    'zone_name',v_zone.name,
    'currency',v_zone.currency_code,
    'special_zone',v_special,
    'amount',(v_special->>'fixed_fare')::numeric
  );
end;
$function$

CREATE OR REPLACE FUNCTION public.special_fare_for_route(p_zone_id uuid, p_service_key text, p_pickup_lat numeric, p_pickup_lng numeric, p_destination_lat numeric, p_destination_lng numeric)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select to_jsonb(x)
  from (
    select
      s.id,
      s.zone_id,
      s.name,
      s.zone_type,
      s.service_key,
      s.fixed_fare,
      s.priority,
      case
        when p_pickup_lat is not null and p_pickup_lng is not null
          and public.point_in_json_polygon(
            p_pickup_lat,p_pickup_lng,s.polygon
          ) then true else false
      end as pickup_inside,
      case
        when p_destination_lat is not null and p_destination_lng is not null
          and public.point_in_json_polygon(
            p_destination_lat,p_destination_lng,s.polygon
          ) then true else false
      end as destination_inside
    from public.fare_special_zones s
    where s.active=true
      and s.zone_id=p_zone_id
      and s.service_key=p_service_key
      and (
        (
          p_pickup_lat is not null and p_pickup_lng is not null
          and public.point_in_json_polygon(
            p_pickup_lat,p_pickup_lng,s.polygon
          )
        )
        or
        (
          p_destination_lat is not null and p_destination_lng is not null
          and public.point_in_json_polygon(
            p_destination_lat,p_destination_lng,s.polygon
          )
        )
      )
    order by s.priority desc,s.fixed_fare desc,s.created_at
    limit 1
  ) x;
$function$

drop trigger if exists zz_apply_special_fixed_fare on public.ride_requests;
create trigger zz_apply_special_fixed_fare
before insert or update of
  category,pickup_latitude,pickup_longitude,
  destination_latitude,destination_longitude,proposed_fare
on public.ride_requests
for each row execute function public.apply_special_fixed_fare();

revoke execute on function public.admin_driver_list_v2() from public,anon;
revoke execute on function public.admin_user_list_v2() from public,anon;
revoke execute on function public.admin_driver_detail(uuid) from public,anon;
revoke execute on function public.admin_user_detail(uuid) from public,anon;
revoke execute on function public.admin_trip_detail(uuid) from public,anon;
revoke execute on function public.admin_update_user_profile(uuid,text,text,text,text,uuid) from public,anon;
revoke execute on function public.admin_update_driver_profile(uuid,text,text,text,text,text,uuid,text,text,text,text,text,text,text,integer) from public,anon;
revoke execute on function public.admin_upsert_driver_document(uuid,uuid,text,text,text,text,timestamptz,text) from public,anon;
revoke execute on function public.pay_driver_subscription_with_wallet(bigint) from public,anon;
revoke execute on function public.set_my_zone_from_location(numeric,numeric) from public,anon;
revoke execute on function public.admin_send_announcement_v2(text,text,text,uuid,uuid) from public,anon;
revoke execute on function public.partner_send_announcement(uuid,text,text) from public,anon;
revoke execute on function public.admin_partner_list() from public,anon;
revoke execute on function public.special_fare_for_my_route(text,numeric,numeric,numeric,numeric) from public,anon;
revoke execute on function public.admin_special_fare_list(uuid) from public,anon;
revoke execute on function public.admin_upsert_special_fare_zone(uuid,uuid,text,text,text,jsonb,numeric,integer,boolean) from public,anon;

grant execute on function public.admin_driver_list_v2() to authenticated;
grant execute on function public.admin_user_list_v2() to authenticated;
grant execute on function public.admin_driver_detail(uuid) to authenticated;
grant execute on function public.admin_user_detail(uuid) to authenticated;
grant execute on function public.admin_trip_detail(uuid) to authenticated;
grant execute on function public.admin_update_user_profile(uuid,text,text,text,text,uuid) to authenticated;
grant execute on function public.admin_update_driver_profile(uuid,text,text,text,text,text,uuid,text,text,text,text,text,text,text,integer) to authenticated;
grant execute on function public.admin_upsert_driver_document(uuid,uuid,text,text,text,text,timestamptz,text) to authenticated;
grant execute on function public.pay_driver_subscription_with_wallet(bigint) to authenticated;
grant execute on function public.set_my_zone_from_location(numeric,numeric) to authenticated;
grant execute on function public.admin_send_announcement_v2(text,text,text,uuid,uuid) to authenticated;
grant execute on function public.partner_send_announcement(uuid,text,text) to authenticated;
grant execute on function public.admin_partner_list() to authenticated;
grant execute on function public.special_fare_for_my_route(text,numeric,numeric,numeric,numeric) to authenticated;
grant execute on function public.admin_special_fare_list(uuid) to authenticated;
grant execute on function public.admin_upsert_special_fare_zone(uuid,uuid,text,text,text,jsonb,numeric,integer,boolean) to authenticated;
