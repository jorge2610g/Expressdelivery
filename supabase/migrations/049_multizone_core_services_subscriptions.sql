-- Express multizone core.
-- Zones are operational tenants for services, fares, subscriptions and dispatch.

alter table public.service_zones
  add column if not exists zone_key text,
  add column if not exists currency_code text not null default 'BOB';

update public.service_zones
set zone_key = case
  when lower(coalesce(city,name,'')) like '%iquique%' then 'iquique'
  when lower(coalesce(city,name,'')) like '%trinidad%' then 'trinidad'
  else lower(regexp_replace(
    translate(coalesce(nullif(trim(city),''),name),
      'ÁÉÍÓÚÜÑáéíóúüñ','AEIOUUNaeiouun'),
    '[^a-zA-Z0-9]+','_','g'))
end
where zone_key is null or trim(zone_key)='';

update public.service_zones
set currency_code=case
  when lower(coalesce(country,''))='chile' then 'CLP'
  when lower(coalesce(country,''))='bolivia' then 'BOB'
  else currency_code
end;

insert into public.service_zones(
  name,city,country,active,center_latitude,center_longitude,radius_km,
  zone_key,currency_code
)
select 'Trinidad','Trinidad','Bolivia',true,-14.8333,-64.9000,25,
       'trinidad','BOB'
where not exists(select 1 from public.service_zones where zone_key='trinidad');

update public.service_zones
set zone_key='iquique',currency_code='CLP'
where lower(coalesce(city,name,'')) like '%iquique%';

alter table public.service_zones alter column zone_key set not null;
create unique index if not exists service_zones_zone_key_uidx
  on public.service_zones(zone_key);

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='service_zones_zone_key_format'
      and conrelid='public.service_zones'::regclass
  ) then
    alter table public.service_zones
      add constraint service_zones_zone_key_format
      check(zone_key ~ '^[a-z0-9_]{2,60}$');
  end if;
end $$;

create table if not exists public.zone_service_catalog(
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  service_key text not null references public.service_catalog(service_key)
    on update cascade on delete cascade,
  enabled boolean not null default false,
  passenger_visible boolean not null default false,
  driver_visible boolean not null default false,
  allow_bidding boolean not null default true,
  allow_fixed_price boolean not null default true,
  scheduled_enabled boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(zone_id,service_key)
);

create index if not exists zone_service_catalog_zone_enabled_idx
  on public.zone_service_catalog(zone_id,enabled,sort_order);
alter table public.zone_service_catalog enable row level security;
drop policy if exists zone_service_catalog_read_authenticated
  on public.zone_service_catalog;
create policy zone_service_catalog_read_authenticated
on public.zone_service_catalog for select to authenticated using(true);

insert into public.zone_service_catalog(
 zone_id,service_key,enabled,passenger_visible,driver_visible,
 allow_bidding,allow_fixed_price,scheduled_enabled,sort_order
)
select z.id,s.service_key,
       case when z.zone_key='trinidad' then s.service_key='motorcycle' else s.enabled end,
       case when z.zone_key='trinidad' then s.service_key='motorcycle' else s.passenger_visible end,
       case when z.zone_key='trinidad' then s.service_key='motorcycle' else s.driver_visible end,
       s.allow_bidding,s.allow_fixed_price,s.scheduled_enabled,s.sort_order
from public.service_zones z cross join public.service_catalog s
on conflict(zone_id,service_key) do nothing;

alter table public.driver_profiles
  add column if not exists zone_id uuid
  references public.service_zones(id) on delete set null;
alter table public.ride_requests
  add column if not exists zone_id uuid
  references public.service_zones(id) on delete set null;
create index if not exists driver_profiles_zone_status_idx
  on public.driver_profiles(zone_id,approval_status,online_status);
create index if not exists ride_requests_zone_status_idx
  on public.ride_requests(zone_id,status,created_at desc);

alter table public.driver_subscription_plans
  drop constraint if exists driver_subscription_plans_code_key;
create unique index if not exists driver_subscription_plans_zone_code_uidx
  on public.driver_subscription_plans(zone_key,code);
do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='driver_subscription_plans_zone_key_fkey'
      and conrelid='public.driver_subscription_plans'::regclass
  ) then
    alter table public.driver_subscription_plans
      add constraint driver_subscription_plans_zone_key_fkey
      foreign key(zone_key) references public.service_zones(zone_key)
      on update cascade on delete restrict;
  end if;
end $$;

insert into public.driver_subscription_plans(
 code,name,amount,days,currency_code,benefits,active,sort_order,zone_key
)
select p.code,p.name,p.amount,p.days,z.currency_code,p.benefits,
       p.active,p.sort_order,'iquique'
from public.driver_subscription_plans p
join public.service_zones z on z.zone_key='iquique'
where p.zone_key='trinidad'
on conflict(zone_key,code) do nothing;

create table if not exists public.driver_subscription_zone_settings(
  zone_id uuid primary key references public.service_zones(id) on delete cascade,
  enabled boolean not null default false,
  enforce_access boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table public.driver_subscription_zone_settings enable row level security;
drop policy if exists driver_subscription_zone_settings_read_authenticated
  on public.driver_subscription_zone_settings;
create policy driver_subscription_zone_settings_read_authenticated
on public.driver_subscription_zone_settings for select
to authenticated using(true);

insert into public.driver_subscription_zone_settings(zone_id,enabled,enforce_access)
select z.id,
       case when z.zone_key='trinidad'
         then coalesce((select enabled from public.driver_subscription_settings where id=true),true)
         else false end,
       case when z.zone_key='trinidad'
         then coalesce((select enforce_access from public.driver_subscription_settings where id=true),false)
         else false end
from public.service_zones z
on conflict(zone_id) do nothing;

alter table public.driver_subscription_payments
  add column if not exists zone_key text;
alter table public.driver_subscription_history
  add column if not exists zone_key text;
create index if not exists driver_subscription_payments_zone_idx
  on public.driver_subscription_payments(zone_key,created_at desc);
create index if not exists driver_subscription_history_zone_idx
  on public.driver_subscription_history(zone_key,created_at desc);

CREATE OR REPLACE FUNCTION public.admin_set_driver_subscription_zone_settings(p_zone_key text, p_enabled boolean, p_enforce_access boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone_id uuid;
  v_row public.driver_subscription_zone_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select id into v_zone_id
  from public.service_zones
  where zone_key=lower(trim(p_zone_key)) and active=true
  limit 1;
  if v_zone_id is null then raise exception 'Zona no encontrada'; end if;

  insert into public.driver_subscription_zone_settings(
    zone_id,enabled,enforce_access,updated_at,updated_by
  )
  values(
    v_zone_id,coalesce(p_enabled,false),coalesce(p_enforce_access,false),
    now(),auth.uid()
  )
  on conflict(zone_id) do update set
    enabled=excluded.enabled,
    enforce_access=excluded.enforce_access,
    updated_at=now(),
    updated_by=auth.uid()
  returning * into v_row;

  if v_row.enforce_access then
    update public.driver_profiles dp
    set online_status='offline',updated_at=now()
    where dp.zone_id=v_zone_id
      and dp.online_status='online'
      and not public.driver_subscription_allows_dispatch(dp.id);
  end if;

  return to_jsonb(v_row);
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_set_zone_service(p_zone_id uuid, p_service_key text, p_enabled boolean, p_passenger_visible boolean, p_driver_visible boolean, p_allow_bidding boolean, p_allow_fixed_price boolean, p_scheduled_enabled boolean, p_sort_order integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.zone_service_catalog%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if not exists(select 1 from public.service_zones where id=p_zone_id) then
    raise exception 'Zona no encontrada';
  end if;
  if not exists(select 1 from public.service_catalog where service_key=p_service_key) then
    raise exception 'Servicio no encontrado';
  end if;

  insert into public.zone_service_catalog(
    zone_id,service_key,enabled,passenger_visible,driver_visible,
    allow_bidding,allow_fixed_price,scheduled_enabled,sort_order,updated_at
  )
  values(
    p_zone_id,p_service_key,coalesce(p_enabled,false),
    coalesce(p_passenger_visible,false),coalesce(p_driver_visible,false),
    coalesce(p_allow_bidding,true),coalesce(p_allow_fixed_price,true),
    coalesce(p_scheduled_enabled,true),coalesce(p_sort_order,100),now()
  )
  on conflict(zone_id,service_key) do update set
    enabled=excluded.enabled,
    passenger_visible=excluded.passenger_visible,
    driver_visible=excluded.driver_visible,
    allow_bidding=excluded.allow_bidding,
    allow_fixed_price=excluded.allow_fixed_price,
    scheduled_enabled=excluded.scheduled_enabled,
    sort_order=excluded.sort_order,
    updated_at=now()
  returning * into v_row;

  return to_jsonb(v_row);
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_upsert_zone(p_id uuid, p_name text, p_city text, p_country text, p_active boolean, p_center_latitude numeric, p_center_longitude numeric, p_radius_km numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if trim(coalesce(p_name,''))='' then
    raise exception 'Nombre requerido';
  end if;

  if p_radius_km is null or p_radius_km <= 0 then
    raise exception 'Radio inválido';
  end if;

  if p_id is null then
    insert into public.service_zones(
      name, city, country, active,
      center_latitude, center_longitude, radius_km
    )
    values(
      trim(p_name),
      nullif(trim(coalesce(p_city,'')),''),
      coalesce(nullif(trim(coalesce(p_country,'')),''),'Chile'),
      coalesce(p_active,true),
      p_center_latitude,
      p_center_longitude,
      p_radius_km
    )
    returning id into v_id;
  else
    update public.service_zones
    set name=trim(p_name),
        city=nullif(trim(coalesce(p_city,'')),''),
        country=coalesce(nullif(trim(coalesce(p_country,'')),''),'Chile'),
        active=coalesce(p_active,true),
        center_latitude=p_center_latitude,
        center_longitude=p_center_longitude,
        radius_km=p_radius_km
    where id=p_id
    returning id into v_id;
  end if;

  if v_id is null then
    raise exception 'Zona no encontrada';
  end if;

  return v_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_upsert_zone(p_id uuid, p_name text, p_city text, p_country text, p_active boolean, p_center_latitude numeric, p_center_longitude numeric, p_radius_km numeric, p_zone_key text, p_currency_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
  v_key text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Nombre requerido'; end if;
  if p_radius_km is null or p_radius_km<=0 then raise exception 'Radio inválido'; end if;

  v_key := lower(trim(coalesce(p_zone_key,'')));
  if v_key='' then
    v_key := lower(
      regexp_replace(
        translate(coalesce(nullif(trim(p_city),''),trim(p_name)),
          'ÁÉÍÓÚÜÑáéíóúüñ','AEIOUUNaeiouun'),
        '[^a-zA-Z0-9]+','_','g'
      )
    );
  end if;
  v_key := trim(both '_' from v_key);

  if v_key !~ '^[a-z0-9_]{2,60}$' then
    raise exception 'Clave de zona inválida';
  end if;

  if p_id is null then
    insert into public.service_zones(
      name,city,country,active,center_latitude,center_longitude,radius_km,
      zone_key,currency_code
    )
    values(
      trim(p_name),nullif(trim(coalesce(p_city,'')),''),
      coalesce(nullif(trim(coalesce(p_country,'')),''),'Bolivia'),
      coalesce(p_active,true),p_center_latitude,p_center_longitude,p_radius_km,
      v_key,upper(coalesce(nullif(trim(p_currency_code),''),'BOB'))
    )
    returning id into v_id;
  else
    update public.service_zones
    set name=trim(p_name),
        city=nullif(trim(coalesce(p_city,'')),''),
        country=coalesce(nullif(trim(coalesce(p_country,'')),''),country),
        active=coalesce(p_active,true),
        center_latitude=p_center_latitude,
        center_longitude=p_center_longitude,
        radius_km=p_radius_km,
        zone_key=v_key,
        currency_code=upper(coalesce(nullif(trim(p_currency_code),''),currency_code)),
        updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Zona no encontrada'; end if;
  return v_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_zone_service_list(p_zone_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',s.id,
          'service_key',s.service_key,
          'name',s.name,
          'description',s.description,
          'icon_key',s.icon_key,
          'vehicle_type',s.vehicle_type,
          'enabled',coalesce(zs.enabled,false),
          'passenger_visible',coalesce(zs.passenger_visible,false),
          'driver_visible',coalesce(zs.driver_visible,false),
          'allow_bidding',coalesce(zs.allow_bidding,s.allow_bidding),
          'allow_fixed_price',coalesce(zs.allow_fixed_price,s.allow_fixed_price),
          'scheduled_enabled',coalesce(zs.scheduled_enabled,s.scheduled_enabled),
          'sort_order',coalesce(zs.sort_order,s.sort_order),
          'zone_id',p_zone_id
        )
        order by coalesce(zs.sort_order,s.sort_order),s.name
      ),
      '[]'::jsonb
    )
    from public.service_catalog s
    left join public.zone_service_catalog zs
      on zs.service_key=s.service_key and zs.zone_id=p_zone_id
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_zone_subscription_settings(p_zone_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone public.service_zones%rowtype;
  v_settings public.driver_subscription_zone_settings%rowtype;
  v_global public.driver_subscription_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select * into v_zone
  from public.service_zones
  where zone_key=lower(trim(p_zone_key))
  limit 1;
  if not found then raise exception 'Zona no encontrada'; end if;

  select * into v_settings
  from public.driver_subscription_zone_settings
  where zone_id=v_zone.id;

  select * into v_global
  from public.driver_subscription_settings where id=true;

  return jsonb_build_object(
    'zone_id',v_zone.id,
    'zone_key',v_zone.zone_key,
    'zone_name',v_zone.name,
    'currency_code',v_zone.currency_code,
    'enabled',coalesce(v_settings.enabled,false),
    'enforce_access',coalesce(v_settings.enforce_access,false),
    'provider',coalesce(v_global.provider,'veripagos'),
    'provider_enabled',coalesce(v_global.provider_enabled,false),
    'qr_validity',coalesce(v_global.qr_validity,'0/00:15')
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.app_geo_policy(p_lat numeric, p_lng numeric, p_for text DEFAULT 'passenger'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone_id uuid;
  v_zone jsonb;
  v_has_coverage boolean;
  v_security jsonb;
begin
  v_has_coverage := exists(
    select 1 from public.service_zones z where z.active=true
  );
  v_zone_id := public.service_zone_id_for_point(p_lat,p_lng);

  if v_zone_id is not null then
    select jsonb_build_object(
      'id',z.id,'zone_key',z.zone_key,'name',z.name,'city',z.city,
      'country',z.country,'currency_code',z.currency_code
    )
    into v_zone
    from public.service_zones z where z.id=v_zone_id;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',s.id,
        'name',s.name,
        'zone_type',s.zone_type,
        'severity',s.severity,
        'message',s.message,
        'applies_to',s.applies_to
      )
      order by s.severity desc
    ),
    '[]'::jsonb
  )
  into v_security
  from public.security_zones s
  where s.active=true
    and (s.applies_to='both' or s.applies_to=coalesce(p_for,'passenger'))
    and public.point_in_json_polygon(p_lat,p_lng,s.polygon);

  return jsonb_build_object(
    'coverage_enforced',v_has_coverage,
    'inside_coverage',(not v_has_coverage) or v_zone_id is not null,
    'zone',v_zone,
    'security_zones',v_security
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.app_zone_context(p_lat numeric, p_lng numeric, p_for text DEFAULT 'passenger'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone_id uuid;
  v_zone jsonb;
  v_services jsonb := '[]'::jsonb;
  v_subscription jsonb := null;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_zone_id := public.service_zone_id_for_point(p_lat,p_lng);

  if v_zone_id is null then
    return jsonb_build_object(
      'inside_coverage',false,
      'zone',null,
      'services','[]'::jsonb,
      'subscription',null
    );
  end if;

  select jsonb_build_object(
    'id',z.id,
    'zone_key',z.zone_key,
    'name',z.name,
    'city',z.city,
    'country',z.country,
    'currency_code',z.currency_code,
    'center_latitude',z.center_latitude,
    'center_longitude',z.center_longitude,
    'radius_km',z.radius_km
  )
  into v_zone
  from public.service_zones z
  where z.id=v_zone_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'service_key',s.service_key,
        'name',s.name,
        'description',s.description,
        'icon_key',s.icon_key,
        'vehicle_type',coalesce(s.vehicle_type,'car'),
        'enabled',zs.enabled,
        'passenger_visible',zs.passenger_visible,
        'driver_visible',zs.driver_visible,
        'allow_bidding',zs.allow_bidding,
        'allow_fixed_price',zs.allow_fixed_price,
        'scheduled_enabled',zs.scheduled_enabled,
        'sort_order',zs.sort_order,
        'fare_rule',public.effective_fare_rule(s.service_key,v_zone_id)
      )
      order by zs.sort_order,s.name
    ),
    '[]'::jsonb
  )
  into v_services
  from public.zone_service_catalog zs
  join public.service_catalog s on s.service_key=zs.service_key
  where zs.zone_id=v_zone_id
    and zs.enabled=true
    and case
      when lower(coalesce(p_for,'passenger'))='driver' then zs.driver_visible
      else zs.passenger_visible
    end;

  select jsonb_build_object(
    'enabled',coalesce(zs.enabled,false),
    'enforce_access',coalesce(zs.enforce_access,false),
    'provider',coalesce(gs.provider,'veripagos'),
    'provider_enabled',coalesce(gs.provider_enabled,false),
    'qr_validity',coalesce(gs.qr_validity,'0/00:15')
  )
  into v_subscription
  from public.driver_subscription_zone_settings zs
  left join public.driver_subscription_settings gs on gs.id=true
  where zs.zone_id=v_zone_id;

  return jsonb_build_object(
    'inside_coverage',true,
    'zone',v_zone,
    'services',coalesce(v_services,'[]'::jsonb),
    'subscription',v_subscription
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.available_ride_requests_for_driver()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_scheduled_before integer := 30;
  v_visible_seconds integer := 180;
  v_max_visible integer := 20;
  v_radius numeric := 15;
  v_lat numeric;
  v_lng numeric;
  v_zone_id uuid;
  v_audit boolean := false;
  v_limit integer := 20;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if not public.is_approved_online_driver(v_uid) then return '[]'::jsonb; end if;

  select
    coalesce(scheduled_publish_before_minutes,30),
    coalesce(request_visible_seconds,180),
    coalesce(max_visible_requests_driver,20),
    coalesce(max_driver_request_radius_km,15)
  into v_scheduled_before,v_visible_seconds,v_max_visible,v_radius
  from public.app_settings where id=true;

  select exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid and m.enabled=true and g.active=true
  ) into v_audit;

  v_limit := case when v_audit then 250 else least(greatest(v_max_visible,1),100) end;

  select latitude,longitude,zone_id into v_lat,v_lng,v_zone_id
  from public.driver_profiles where id=v_uid limit 1;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc),'[]'::jsonb)
  into v_result
  from (
    select r.*
    from public.ride_requests r
    where r.status in ('searching','offers_received')
      and r.expires_at>now()
      and r.passenger_id<>v_uid
      and public.same_operational_scope(r.passenger_id,v_uid)
      and (v_zone_id is null or r.zone_id is null or r.zone_id=v_zone_id)
      and (r.scheduled_for is null or r.scheduled_for<=now()+make_interval(mins=>least(greatest(v_scheduled_before,5),1440)))
      and (r.scheduled_for is not null or r.created_at>now()-make_interval(secs=>least(greatest(v_visible_seconds,30),1800)))
      and (
        v_zone_id is null
        or exists(
          select 1 from public.zone_service_catalog zs
          where zs.zone_id=v_zone_id
            and zs.service_key=r.category
            and zs.enabled=true
            and zs.driver_visible=true
        )
      )
      and (
        v_lat is null or v_lng is null
        or r.pickup_latitude is null or r.pickup_longitude is null
        or public.geo_distance_km(v_lat,v_lng,r.pickup_latitude,r.pickup_longitude)
          <= least(greatest(v_radius,1),100)
      )
    order by r.created_at asc
    limit v_limit
  ) x;

  return v_result;
end;
$function$


CREATE OR REPLACE FUNCTION public.driver_subscription_allows_dispatch(p_driver_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone_id uuid;
  v_zone_key text;
  v_enabled boolean := false;
  v_enforce boolean := false;
begin
  select dp.zone_id into v_zone_id
  from public.driver_profiles dp where dp.id=p_driver_id;

  if v_zone_id is null then
    return case
      when not coalesce((select enforce_access from public.driver_subscription_settings where id=true),false)
        then true
      else exists(
        select 1 from public.driver_subscriptions s
        where s.driver_id=p_driver_id and s.status='active' and s.expires_at>now()
      )
    end;
  end if;

  select z.zone_key into v_zone_key
  from public.service_zones z where z.id=v_zone_id;

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
$function$


CREATE OR REPLACE FUNCTION public.driver_subscription_catalog_for_me()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_zone_id uuid;
  v_zone_key text;
  v_zone_name text;
  v_currency text;
  v_enabled boolean := false;
  v_enforce boolean := false;
  v_global public.driver_subscription_settings%rowtype;
  v_plans jsonb;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;

  select dp.zone_id into v_zone_id
  from public.driver_profiles dp where dp.id=v_uid;

  if v_zone_id is null then
    return jsonb_build_object(
      'zone',null,'enabled',false,'enforce_access',false,'plans','[]'::jsonb
    );
  end if;

  select zone_key,name,currency_code into v_zone_key,v_zone_name,v_currency
  from public.service_zones where id=v_zone_id;

  select enabled,enforce_access into v_enabled,v_enforce
  from public.driver_subscription_zone_settings where zone_id=v_zone_id;

  select * into v_global
  from public.driver_subscription_settings where id=true;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.sort_order,p.id),'[]'::jsonb)
  into v_plans
  from public.driver_subscription_plans p
  where p.zone_key=v_zone_key and p.active=true;

  return jsonb_build_object(
    'zone',jsonb_build_object(
      'id',v_zone_id,'zone_key',v_zone_key,'name',v_zone_name,'currency_code',v_currency
    ),
    'enabled',coalesce(v_enabled,false),
    'enforce_access',coalesce(v_enforce,false),
    'provider',coalesce(v_global.provider,'veripagos'),
    'provider_enabled',coalesce(v_global.provider_enabled,false),
    'qr_validity',coalesce(v_global.qr_validity,'0/00:15'),
    'plans',coalesce(v_plans,'[]'::jsonb)
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.geo_distance_km(p_lat1 numeric, p_lng1 numeric, p_lat2 numeric, p_lng2 numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_lat1 is null or p_lng1 is null or p_lat2 is null or p_lng2 is null
      then null
    else (
      6371 * acos(
        least(1,greatest(-1,
          cos(radians(p_lat1::double precision))
          * cos(radians(p_lat2::double precision))
          * cos(radians(p_lng2::double precision)-radians(p_lng1::double precision))
          + sin(radians(p_lat1::double precision))
          * sin(radians(p_lat2::double precision))
        ))
      )
    )::numeric
  end;
$function$


CREATE OR REPLACE FUNCTION public.nearby_online_driver_markers(p_lat numeric, p_lng numeric, p_radius_km numeric DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb;
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  with candidates as (
    select
      round(dp.latitude::numeric, 3) as latitude,
      round(dp.longitude::numeric, 3) as longitude,
      coalesce(
        (
          select dv.vehicle_type
          from public.driver_vehicles dv
          where dv.driver_id = dp.id and dv.is_active = true
          order by dv.updated_at desc
          limit 1
        ),
        case
          when lower(coalesce(dp.vehicle_summary,'')) like '%moto%' then 'motorcycle'
          when lower(coalesce(dp.vehicle_summary,'')) like '%xl%' then 'xl'
          else 'car'
        end
      ) as vehicle_type,
      (
        6371 * acos(
          least(1, greatest(-1,
            cos(radians(p_lat::double precision))
            * cos(radians(dp.latitude::double precision))
            * cos(radians(dp.longitude::double precision) - radians(p_lng::double precision))
            + sin(radians(p_lat::double precision))
            * sin(radians(dp.latitude::double precision))
          ))
        )
      ) as distance_km
    from public.driver_profiles dp
    where dp.approval_status = 'approved'
      and dp.online_status = 'online'
      and dp.latitude is not null
      and dp.longitude is not null
      and public.same_operational_scope(v_uid, dp.id)
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'latitude', latitude,
        'longitude', longitude,
        'vehicle_type', vehicle_type,
        'distance_km', round(distance_km::numeric, 1)
      )
      order by distance_km
    ),
    '[]'::jsonb
  )
  into v_result
  from (
    select * from candidates
    where distance_km <= greatest(0.5, least(coalesce(p_radius_km, 5), 20))
    order by distance_km
    limit 12
  ) q;

  return v_result;
end;
$function$


CREATE OR REPLACE FUNCTION public.nearby_online_driver_markers(p_lat numeric, p_lng numeric, p_radius_km numeric DEFAULT 5, p_vehicle_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb;
  v_requested text := nullif(lower(trim(coalesce(p_vehicle_type,''))),'');
  v_uid uuid := auth.uid();
  v_audit boolean := false;
  v_limit integer := 16;
  v_zone_id uuid;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;

  v_zone_id := public.service_zone_id_for_point(p_lat,p_lng);

  select exists(
    select 1 from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid and m.enabled=true and g.active=true
  ) into v_audit;
  if v_audit then v_limit:=250; end if;

  with candidates as (
    select
      round(dp.latitude::numeric,5) latitude,
      round(dp.longitude::numeric,5) longitude,
      coalesce(dp.heading_degrees,0) heading_degrees,
      coalesce(
        (select dv.vehicle_type from public.driver_vehicles dv
         where dv.driver_id=dp.id and dv.is_active=true
         order by dv.updated_at desc limit 1),
        case
          when lower(coalesce(dp.vehicle_summary,'')) like '%moto%' then 'motorcycle'
          when lower(coalesce(dp.vehicle_summary,'')) like '%xl%' then 'xl'
          else 'car'
        end
      ) vehicle_type,
      public.geo_distance_km(p_lat,p_lng,dp.latitude,dp.longitude) distance_km
    from public.driver_profiles dp
    where dp.approval_status='approved'
      and dp.online_status='online'
      and dp.latitude is not null
      and dp.longitude is not null
      and public.same_operational_scope(v_uid,dp.id)
      and (v_zone_id is null or dp.zone_id is null or dp.zone_id=v_zone_id)
  )
  select coalesce(
    jsonb_agg(jsonb_build_object(
      'latitude',latitude,'longitude',longitude,
      'vehicle_type',vehicle_type,'heading_degrees',heading_degrees,
      'distance_km',round(distance_km::numeric,1)
    ) order by distance_km),
    '[]'::jsonb
  )
  into v_result
  from (
    select * from candidates
    where distance_km<=greatest(0.5,least(coalesce(p_radius_km,5),20))
      and (v_requested is null or vehicle_type=v_requested)
    order by distance_km
    limit v_limit
  ) q;

  return v_result;
end;
$function$


CREATE OR REPLACE FUNCTION public.quote_service_fare_for_location(p_service_key text, p_distance_km numeric, p_duration_minutes numeric, p_lat numeric, p_lng numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone_id uuid;
  v_rule jsonb;
  v_base numeric := 0;
  v_per_km numeric := 0;
  v_per_minute numeric := 0;
  v_minimum numeric := 0;
  v_surge numeric := 1;
  v_amount numeric := 0;
  v_currency text := 'BOB';
  v_zone_key text;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;

  v_zone_id := public.service_zone_id_for_point(p_lat,p_lng);
  if v_zone_id is null then
    raise exception 'Fuera de una zona activa de Express';
  end if;

  select zone_key,currency_code into v_zone_key,v_currency
  from public.service_zones where id=v_zone_id;

  if not exists(
    select 1
    from public.zone_service_catalog zs
    where zs.zone_id=v_zone_id
      and zs.service_key=p_service_key
      and zs.enabled=true
      and zs.passenger_visible=true
  ) then
    raise exception 'Servicio no disponible en esta zona';
  end if;

  v_rule := public.effective_fare_rule(
    nullif(trim(coalesce(p_service_key,'')),''),
    v_zone_id
  );

  if v_rule is null then
    select coalesce(
      case when p_service_key='delivery' then min_delivery_fare else min_ride_fare end,
      0
    )
    into v_minimum
    from public.app_settings where id=true;
    v_amount := v_minimum;
  else
    v_base := coalesce((v_rule->>'base_fare')::numeric,0);
    v_per_km := coalesce((v_rule->>'per_km')::numeric,0);
    v_per_minute := coalesce((v_rule->>'per_minute')::numeric,0);
    v_minimum := coalesce((v_rule->>'minimum_fare')::numeric,0);
    v_surge := greatest(coalesce((v_rule->>'surge_multiplier')::numeric,1),1);

    v_amount := greatest(
      v_minimum,
      (
        v_base
        + v_per_km * greatest(coalesce(p_distance_km,0),0)
        + v_per_minute * greatest(coalesce(p_duration_minutes,0),0)
      ) * v_surge
    );
  end if;

  return jsonb_build_object(
    'amount',round(v_amount,2),
    'currency',coalesce(v_currency,'BOB'),
    'zone_id',v_zone_id,
    'zone_key',v_zone_key,
    'distance_km',round(greatest(coalesce(p_distance_km,0),0),2),
    'duration_minutes',greatest(round(coalesce(p_duration_minutes,0)),0),
    'rule',v_rule
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.seed_service_zone_rows()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.zone_service_catalog(
    zone_id,service_key,enabled,passenger_visible,driver_visible,
    allow_bidding,allow_fixed_price,scheduled_enabled,sort_order
  )
  select
    z.id,new.service_key,false,false,false,
    new.allow_bidding,new.allow_fixed_price,new.scheduled_enabled,new.sort_order
  from public.service_zones z
  on conflict(zone_id,service_key) do nothing;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.seed_zone_service_rows()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.zone_service_catalog(
    zone_id,service_key,enabled,passenger_visible,driver_visible,
    allow_bidding,allow_fixed_price,scheduled_enabled,sort_order
  )
  select
    new.id,s.service_key,false,false,false,
    s.allow_bidding,s.allow_fixed_price,s.scheduled_enabled,s.sort_order
  from public.service_catalog s
  on conflict(zone_id,service_key) do nothing;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.seed_zone_subscription_settings()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.driver_subscription_zone_settings(zone_id,enabled,enforce_access)
  values(new.id,false,false)
  on conflict(zone_id) do nothing;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.service_zone_id_for_point(p_lat numeric, p_lng numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if p_lat is null or p_lng is null then return null; end if;

  select z.id
  into v_id
  from public.service_zones z
  where z.active=true
    and (
      (
        exists(select 1 from public.service_zone_polygons p where p.zone_id=z.id and p.active=true)
        and exists(
          select 1 from public.service_zone_polygons p
          where p.zone_id=z.id and p.active=true
            and public.point_in_json_polygon(p_lat,p_lng,p.polygon)
        )
      )
      or
      (
        not exists(select 1 from public.service_zone_polygons p where p.zone_id=z.id and p.active=true)
        and z.center_latitude is not null
        and z.center_longitude is not null
        and public.geo_distance_km(
          p_lat,p_lng,z.center_latitude,z.center_longitude
        ) <= greatest(coalesce(z.radius_km,20),0.5)
      )
    )
  order by
    case when exists(
      select 1 from public.service_zone_polygons p
      where p.zone_id=z.id and p.active=true
        and public.point_in_json_polygon(p_lat,p_lng,p.polygon)
    ) then 0 else 1 end,
    public.geo_distance_km(p_lat,p_lng,z.center_latitude,z.center_longitude)
  limit 1;

  return v_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.set_driver_zone_from_location()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone uuid;
  v_city text;
begin
  if new.latitude is not null and new.longitude is not null then
    v_zone := public.service_zone_id_for_point(new.latitude,new.longitude);
    new.zone_id := v_zone;
    if v_zone is not null then
      select city into v_city from public.service_zones where id=v_zone;
      if v_city is not null then new.city := v_city; end if;
    end if;
  else
    new.zone_id := null;
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.set_ride_zone_from_pickup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_zone uuid;
  v_currency text;
begin
  if new.pickup_latitude is not null and new.pickup_longitude is not null then
    v_zone := public.service_zone_id_for_point(new.pickup_latitude,new.pickup_longitude);
    new.zone_id := v_zone;
    if v_zone is not null then
      select currency_code into v_currency from public.service_zones where id=v_zone;
      new.currency := coalesce(v_currency,new.currency,'BOB');
    end if;
  else
    new.zone_id := null;
  end if;
  return new;
end;
$function$


drop trigger if exists trg_seed_zone_service_rows on public.service_zones;
create trigger trg_seed_zone_service_rows
after insert on public.service_zones
for each row execute function public.seed_zone_service_rows();

drop trigger if exists trg_seed_service_zone_rows on public.service_catalog;
create trigger trg_seed_service_zone_rows
after insert on public.service_catalog
for each row execute function public.seed_service_zone_rows();

drop trigger if exists trg_driver_zone_from_location on public.driver_profiles;
create trigger trg_driver_zone_from_location
before insert or update of latitude,longitude on public.driver_profiles
for each row execute function public.set_driver_zone_from_location();

drop trigger if exists trg_ride_zone_from_pickup on public.ride_requests;
create trigger trg_ride_zone_from_pickup
before insert or update of pickup_latitude,pickup_longitude on public.ride_requests
for each row execute function public.set_ride_zone_from_pickup();

drop trigger if exists trg_seed_zone_subscription_settings on public.service_zones;
create trigger trg_seed_zone_subscription_settings
after insert on public.service_zones
for each row execute function public.seed_zone_subscription_settings();

create or replace function public.set_subscription_record_zone()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.plan_id is not null then
    select p.zone_key into new.zone_key
    from public.driver_subscription_plans p where p.id=new.plan_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_subscription_payment_zone
  on public.driver_subscription_payments;
create trigger trg_subscription_payment_zone
before insert or update of plan_id on public.driver_subscription_payments
for each row execute function public.set_subscription_record_zone();

drop trigger if exists trg_subscription_history_zone
  on public.driver_subscription_history;
create trigger trg_subscription_history_zone
before insert or update of plan_id on public.driver_subscription_history
for each row execute function public.set_subscription_record_zone();

update public.driver_profiles dp
set zone_id=public.service_zone_id_for_point(dp.latitude,dp.longitude)
where dp.latitude is not null and dp.longitude is not null;
update public.ride_requests r
set zone_id=public.service_zone_id_for_point(r.pickup_latitude,r.pickup_longitude)
where r.pickup_latitude is not null and r.pickup_longitude is not null;
update public.driver_subscription_payments p
set zone_key=pl.zone_key
from public.driver_subscription_plans pl
where pl.id=p.plan_id and p.zone_key is null;
update public.driver_subscription_history h
set zone_key=pl.zone_key
from public.driver_subscription_plans pl
where pl.id=h.plan_id and h.zone_key is null;

grant execute on function public.app_zone_context(numeric,numeric,text)
  to authenticated;
grant execute on function public.quote_service_fare_for_location(text,numeric,numeric,numeric,numeric)
  to authenticated;
grant execute on function public.driver_subscription_catalog_for_me()
  to authenticated;
grant execute on function public.admin_zone_service_list(uuid)
  to authenticated;
grant execute on function public.admin_set_zone_service(uuid,text,boolean,boolean,boolean,boolean,boolean,boolean,integer)
  to authenticated;
grant execute on function public.admin_zone_subscription_settings(text)
  to authenticated;
grant execute on function public.admin_set_driver_subscription_zone_settings(text,boolean,boolean)
  to authenticated;
