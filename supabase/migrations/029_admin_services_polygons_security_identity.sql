-- Adminexpress: servicios, polígonos, zonas de seguridad e identidad.
-- Aplicado inicialmente en producción el 2026-10-02. Este archivo conserva
-- la migración en el repositorio para que el backend siga siendo reproducible.

create table if not exists public.service_catalog (
  id uuid primary key default gen_random_uuid(),
  service_key text not null unique,
  name text not null,
  description text,
  icon_key text,
  vehicle_type text,
  enabled boolean not null default true,
  allow_bidding boolean not null default true,
  allow_fixed_price boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.service_catalog(service_key,name,description,icon_key,vehicle_type,enabled,allow_bidding,allow_fixed_price,sort_order)
values
 ('economy','Express','Viaje económico estándar','local_taxi','car',true,true,true,10),
 ('comfort','Comfort','Vehículos con mayor comodidad','airline_seat_recline_extra','car',true,true,true,20),
 ('xl','XL','Vehículos con mayor capacidad','airport_shuttle','car',true,true,true,30),
 ('motorcycle','Moto','Viajes en motocicleta','two_wheeler','motorcycle',true,true,true,40),
 ('delivery','Delivery','Envíos y entregas','local_shipping','motorcycle',true,true,true,50)
on conflict (service_key) do nothing;

create table if not exists public.service_zone_polygons (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  name text not null default 'Cobertura principal',
  polygon jsonb not null default '[]'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists service_zone_polygons_zone_id_idx
  on public.service_zone_polygons(zone_id);

create table if not exists public.security_zones (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  zone_type text not null default 'red'
    check (zone_type in ('red','caution','safe')),
  applies_to text not null default 'both'
    check (applies_to in ('both','passenger','driver')),
  severity integer not null default 3 check (severity between 1 and 5),
  polygon jsonb not null default '[]'::jsonb,
  message text,
  active boolean not null default true,
  city text,
  country text not null default 'Bolivia',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.identity_verification_settings (
  id boolean primary key default true check (id),
  provider text not null default 'manual',
  document_enabled boolean not null default true,
  face_enabled boolean not null default true,
  face_match_enabled boolean not null default true,
  liveness_enabled boolean not null default false,
  require_driver boolean not null default true,
  require_passenger boolean not null default false,
  min_face_score numeric not null default 0.75,
  min_liveness_score numeric not null default 0.70,
  manual_review_on_fail boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.identity_verification_settings(id)
values(true)
on conflict (id) do nothing;

create table if not exists public.identity_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  subject_role text not null default 'driver'
    check (subject_role in ('driver','passenger')),
  document_type text,
  status text not null default 'pending'
    check (status in ('pending','processing','verified','review','rejected')),
  provider text not null default 'manual',
  document_score numeric,
  face_match_score numeric,
  liveness_score numeric,
  result jsonb not null default '{}'::jsonb,
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists identity_verifications_user_id_idx
  on public.identity_verifications(user_id);

alter table public.service_catalog enable row level security;
alter table public.service_zone_polygons enable row level security;
alter table public.security_zones enable row level security;
alter table public.identity_verification_settings enable row level security;
alter table public.identity_verifications enable row level security;

create or replace function public.admin_service_list()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(s) order by s.sort_order,s.name),'[]'::jsonb)
    from public.service_catalog s
  );
end; $$;

create or replace function public.admin_upsert_service(
  p_id uuid, p_service_key text, p_name text, p_description text,
  p_icon_key text, p_vehicle_type text, p_enabled boolean,
  p_allow_bidding boolean, p_allow_fixed_price boolean, p_sort_order integer
)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if trim(coalesce(p_service_key,''))='' then raise exception 'Clave requerida'; end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Nombre requerido'; end if;
  if p_id is null then
    insert into public.service_catalog(
      service_key,name,description,icon_key,vehicle_type,enabled,
      allow_bidding,allow_fixed_price,sort_order
    )
    values(
      lower(trim(p_service_key)),trim(p_name),nullif(trim(coalesce(p_description,'')),''),
      nullif(trim(coalesce(p_icon_key,'')),''),nullif(trim(coalesce(p_vehicle_type,'')),''),
      coalesce(p_enabled,true),coalesce(p_allow_bidding,true),
      coalesce(p_allow_fixed_price,true),coalesce(p_sort_order,0)
    ) returning id into v_id;
  else
    update public.service_catalog
    set service_key=lower(trim(p_service_key)), name=trim(p_name),
        description=nullif(trim(coalesce(p_description,'')),''),
        icon_key=nullif(trim(coalesce(p_icon_key,'')),''),
        vehicle_type=nullif(trim(coalesce(p_vehicle_type,'')),''),
        enabled=coalesce(p_enabled,true),
        allow_bidding=coalesce(p_allow_bidding,true),
        allow_fixed_price=coalesce(p_allow_fixed_price,true),
        sort_order=coalesce(p_sort_order,0), updated_at=now()
    where id=p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Servicio no encontrado'; end if;
  perform public.admin_log_action('upsert','service_catalog',v_id::text,
    jsonb_build_object('name',p_name,'key',p_service_key));
  return v_id;
end; $$;

create or replace function public.admin_zone_polygon_list()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(
      to_jsonb(p) || jsonb_build_object('zone_name',z.name,'city',z.city,'country',z.country)
      order by p.updated_at desc
    ),'[]'::jsonb)
    from public.service_zone_polygons p
    join public.service_zones z on z.id=p.zone_id
  );
end; $$;

create or replace function public.admin_upsert_zone_polygon(
  p_id uuid, p_zone_id uuid, p_name text, p_polygon jsonb, p_active boolean
)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_zone_id is null then raise exception 'Zona requerida'; end if;
  if jsonb_typeof(coalesce(p_polygon,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_polygon,'[]'::jsonb)) < 3 then
    raise exception 'El polígono necesita al menos 3 puntos';
  end if;
  if p_id is null then
    insert into public.service_zone_polygons(zone_id,name,polygon,active)
    values(p_zone_id,coalesce(nullif(trim(p_name),''),'Cobertura principal'),
      p_polygon,coalesce(p_active,true))
    returning id into v_id;
  else
    update public.service_zone_polygons
    set zone_id=p_zone_id, name=coalesce(nullif(trim(p_name),''),'Cobertura principal'),
        polygon=p_polygon, active=coalesce(p_active,true), updated_at=now()
    where id=p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Polígono no encontrado'; end if;
  perform public.admin_log_action('upsert','service_zone_polygon',v_id::text,
    jsonb_build_object('zone_id',p_zone_id,'points',jsonb_array_length(p_polygon)));
  return v_id;
end; $$;

create or replace function public.admin_security_zone_list()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(s) order by s.severity desc,s.updated_at desc),'[]'::jsonb)
    from public.security_zones s
  );
end; $$;

create or replace function public.admin_upsert_security_zone(
  p_id uuid, p_name text, p_zone_type text, p_applies_to text,
  p_severity integer, p_polygon jsonb, p_message text, p_active boolean,
  p_city text, p_country text
)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Nombre requerido'; end if;
  if p_zone_type not in ('red','caution','safe') then raise exception 'Tipo inválido'; end if;
  if p_applies_to not in ('both','passenger','driver') then raise exception 'Destino inválido'; end if;
  if jsonb_typeof(coalesce(p_polygon,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_polygon,'[]'::jsonb)) < 3 then
    raise exception 'La zona necesita al menos 3 puntos';
  end if;
  if p_id is null then
    insert into public.security_zones(
      name,zone_type,applies_to,severity,polygon,message,active,city,country
    )
    values(
      trim(p_name),p_zone_type,p_applies_to,
      least(greatest(coalesce(p_severity,3),1),5),p_polygon,
      nullif(trim(coalesce(p_message,'')),''),
      coalesce(p_active,true),nullif(trim(coalesce(p_city,'')),''),
      coalesce(nullif(trim(coalesce(p_country,'')),''),'Bolivia')
    ) returning id into v_id;
  else
    update public.security_zones
    set name=trim(p_name), zone_type=p_zone_type, applies_to=p_applies_to,
        severity=least(greatest(coalesce(p_severity,3),1),5),
        polygon=p_polygon, message=nullif(trim(coalesce(p_message,'')),''),
        active=coalesce(p_active,true), city=nullif(trim(coalesce(p_city,'')),''),
        country=coalesce(nullif(trim(coalesce(p_country,'')),''),'Bolivia'),
        updated_at=now()
    where id=p_id returning id into v_id;
  end if;
  if v_id is null then raise exception 'Zona de seguridad no encontrada'; end if;
  perform public.admin_log_action('upsert','security_zone',v_id::text,
    jsonb_build_object('name',p_name,'type',p_zone_type,'severity',p_severity));
  return v_id;
end; $$;

create or replace function public.admin_identity_settings_get()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select to_jsonb(i) from public.identity_verification_settings i where i.id=true
  );
end; $$;

create or replace function public.admin_identity_settings_update(
  p_provider text, p_document_enabled boolean, p_face_enabled boolean,
  p_face_match_enabled boolean, p_liveness_enabled boolean,
  p_require_driver boolean, p_require_passenger boolean,
  p_min_face_score numeric, p_min_liveness_score numeric,
  p_manual_review_on_fail boolean
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  update public.identity_verification_settings
  set provider=coalesce(nullif(trim(p_provider),''),'manual'),
      document_enabled=coalesce(p_document_enabled,true),
      face_enabled=coalesce(p_face_enabled,true),
      face_match_enabled=coalesce(p_face_match_enabled,true),
      liveness_enabled=coalesce(p_liveness_enabled,false),
      require_driver=coalesce(p_require_driver,true),
      require_passenger=coalesce(p_require_passenger,false),
      min_face_score=least(greatest(coalesce(p_min_face_score,.75),0),1),
      min_liveness_score=least(greatest(coalesce(p_min_liveness_score,.70),0),1),
      manual_review_on_fail=coalesce(p_manual_review_on_fail,true),
      updated_at=now()
  where id=true
  returning to_jsonb(identity_verification_settings.*) into v_result;
  perform public.admin_log_action(
    'update','identity_verification_settings','global',v_result
  );
  return v_result;
end; $$;

create or replace function public.admin_identity_verification_list(p_limit integer default 200)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb)
    from (
      select v.*, u.full_name, u.email, u.phone
      from public.identity_verifications v
      left join public.users u on u.id=v.user_id
      order by v.created_at desc
      limit least(greatest(coalesce(p_limit,200),1),500)
    ) x
  );
end; $$;

create or replace function public.app_runtime_config()
returns jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object(
    'settings',(select to_jsonb(s) from public.app_settings s where s.id=true),
    'services',(select coalesce(jsonb_agg(to_jsonb(c) order by c.sort_order,c.name),'[]'::jsonb)
                from public.service_catalog c where c.enabled=true),
    'security_zones',(select coalesce(jsonb_agg(to_jsonb(z) order by z.severity desc),'[]'::jsonb)
                      from public.security_zones z where z.active=true)
  );
$$;

update public.app_settings
set default_country=case when default_country='Chile' then 'Bolivia' else default_country end,
    timezone=case when timezone='America/Santiago' then 'America/La_Paz' else timezone end,
    updated_at=now()
where id=true;
