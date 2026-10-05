-- Global country / zone coverage controls for Express.
-- Countries are master switches; cities/zones remain the actual GPS coverage.
-- Admin controls country activation, driver registration and Didit per country.

create table if not exists public.service_countries (
  country_code text primary key,
  name text not null,
  currency_code text not null default 'USD',
  active boolean not null default false,
  driver_registration_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_countries_code_chk check (country_code ~ '^[A-Z]{2}$'),
  constraint service_countries_currency_chk check (currency_code ~ '^[A-Z]{3}$')
);

alter table public.service_countries enable row level security;
revoke all on table public.service_countries from anon, authenticated;

insert into public.service_countries(
  country_code,name,currency_code,active,driver_registration_enabled
)
select distinct on (upper(z.country_code))
  upper(z.country_code),
  z.country,
  upper(z.currency_code),
  bool_or(z.active) over (partition by upper(z.country_code)),
  true
from public.service_zones z
where nullif(trim(coalesce(z.country_code,'')),'') is not null
order by upper(z.country_code),z.updated_at desc
on conflict (country_code) do update set
  name=excluded.name,
  currency_code=excluded.currency_code,
  updated_at=now();

create table if not exists public.identity_verification_country_settings (
  country_code text primary key
    references public.service_countries(country_code) on delete cascade,
  didit_enabled boolean not null default false,
  manual_fallback_enabled boolean not null default true,
  production_workflow_id text,
  sandbox_workflow_id text,
  updated_at timestamptz not null default now()
);

alter table public.identity_verification_country_settings enable row level security;
revoke all on table public.identity_verification_country_settings
  from anon, authenticated;

insert into public.identity_verification_country_settings(
  country_code,didit_enabled,manual_fallback_enabled
)
select country_code,country_code in ('CL','BO'),true
from public.service_countries
on conflict (country_code) do nothing;

alter table public.service_zones
  add column if not exists driver_registration_enabled boolean
  not null default true;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname='service_zones_country_code_fk'
      and conrelid='public.service_zones'::regclass
  ) then
    alter table public.service_zones
      add constraint service_zones_country_code_fk
      foreign key (country_code)
      references public.service_countries(country_code)
      on update cascade;
  end if;
end $$;

create index if not exists service_zones_country_active_idx
  on public.service_zones(country_code,active,driver_registration_enabled);

create or replace function public.admin_country_list()
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'country_code',c.country_code,
          'name',c.name,
          'currency_code',c.currency_code,
          'active',c.active,
          'driver_registration_enabled',c.driver_registration_enabled,
          'didit_enabled',coalesce(v.didit_enabled,false),
          'manual_fallback_enabled',coalesce(v.manual_fallback_enabled,true),
          'production_workflow_configured',
            nullif(trim(coalesce(v.production_workflow_id,'')),'') is not null,
          'sandbox_workflow_configured',
            nullif(trim(coalesce(v.sandbox_workflow_id,'')),'') is not null,
          'zones_total',(
            select count(*) from public.service_zones z
            where upper(coalesce(z.country_code,''))=c.country_code
          ),
          'zones_active',(
            select count(*) from public.service_zones z
            where upper(coalesce(z.country_code,''))=c.country_code
              and z.active=true
          )
        )
        order by c.name
      ),
      '[]'::jsonb
    )
    from public.service_countries c
    left join public.identity_verification_country_settings v
      on v.country_code=c.country_code
  );
end;
$$;

revoke all on function public.admin_country_list() from public,anon;
grant execute on function public.admin_country_list() to authenticated;

create or replace function public.admin_upsert_country_coverage(
  p_country_code text,
  p_name text,
  p_currency_code text,
  p_active boolean,
  p_driver_registration_enabled boolean,
  p_didit_enabled boolean,
  p_manual_fallback_enabled boolean default true,
  p_production_workflow_id text default null,
  p_sandbox_workflow_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_code text := upper(trim(coalesce(p_country_code,'')));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_code !~ '^[A-Z]{2}$' then
    raise exception 'Código ISO de país inválido';
  end if;
  if trim(coalesce(p_name,''))='' then
    raise exception 'Nombre de país requerido';
  end if;
  if upper(trim(coalesce(p_currency_code,''))) !~ '^[A-Z]{3}$' then
    raise exception 'Código de moneda inválido';
  end if;

  insert into public.service_countries(
    country_code,name,currency_code,active,
    driver_registration_enabled,updated_at
  )
  values(
    v_code,
    trim(p_name),
    upper(trim(p_currency_code)),
    coalesce(p_active,false),
    coalesce(p_driver_registration_enabled,true),
    now()
  )
  on conflict(country_code) do update set
    name=excluded.name,
    currency_code=excluded.currency_code,
    active=excluded.active,
    driver_registration_enabled=excluded.driver_registration_enabled,
    updated_at=now();

  insert into public.identity_verification_country_settings(
    country_code,didit_enabled,manual_fallback_enabled,
    production_workflow_id,sandbox_workflow_id,updated_at
  )
  values(
    v_code,
    coalesce(p_didit_enabled,false),
    coalesce(p_manual_fallback_enabled,true),
    nullif(trim(coalesce(p_production_workflow_id,'')),''),
    nullif(trim(coalesce(p_sandbox_workflow_id,'')),''),
    now()
  )
  on conflict(country_code) do update set
    didit_enabled=excluded.didit_enabled,
    manual_fallback_enabled=excluded.manual_fallback_enabled,
    production_workflow_id=coalesce(
      nullif(trim(coalesce(p_production_workflow_id,'')),''),
      identity_verification_country_settings.production_workflow_id
    ),
    sandbox_workflow_id=coalesce(
      nullif(trim(coalesce(p_sandbox_workflow_id,'')),''),
      identity_verification_country_settings.sandbox_workflow_id
    ),
    updated_at=now();

  return jsonb_build_object(
    'ok',true,
    'country_code',v_code,
    'active',coalesce(p_active,false),
    'driver_registration_enabled',
      coalesce(p_driver_registration_enabled,true),
    'didit_enabled',coalesce(p_didit_enabled,false)
  );
end;
$$;

revoke all on function public.admin_upsert_country_coverage(
  text,text,text,boolean,boolean,boolean,boolean,text,text
) from public,anon;
grant execute on function public.admin_upsert_country_coverage(
  text,text,text,boolean,boolean,boolean,boolean,text,text
) to authenticated;

create or replace function public.admin_upsert_zone_v3(
  p_id uuid,
  p_name text,
  p_city text,
  p_region_department text,
  p_country_code text,
  p_active boolean,
  p_driver_registration_enabled boolean,
  p_center_latitude numeric,
  p_center_longitude numeric,
  p_radius_km numeric,
  p_zone_key text,
  p_currency_code text
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_key text;
  v_code text := upper(trim(coalesce(p_country_code,'')));
  v_country public.service_countries%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Nombre requerido'; end if;
  if p_radius_km is null or p_radius_km<=0 then
    raise exception 'Radio inválido';
  end if;

  select * into v_country
  from public.service_countries
  where country_code=v_code;

  if v_country.country_code is null then
    raise exception 'Primero crea el país % en Países / cobertura',v_code;
  end if;

  v_key := lower(trim(coalesce(p_zone_key,'')));
  if v_key='' then
    v_key := lower(regexp_replace(
      translate(
        coalesce(nullif(trim(p_city),''),trim(p_name)),
        'ÁÉÍÓÚÜÑáéíóúüñ',
        'AEIOUUNaeiouun'
      ),
      '[^a-zA-Z0-9]+','_','g'
    ));
  end if;
  v_key := trim(both '_' from v_key);
  if v_key !~ '^[a-z0-9_]{2,60}$' then
    raise exception 'Clave de zona inválida';
  end if;

  if p_id is null then
    insert into public.service_zones(
      name,city,region_department,country,country_code,active,
      driver_registration_enabled,center_latitude,center_longitude,
      radius_km,zone_key,currency_code
    )
    values(
      trim(p_name),
      nullif(trim(coalesce(p_city,'')),''),
      nullif(trim(coalesce(p_region_department,'')),''),
      v_country.name,
      v_code,
      coalesce(p_active,true),
      coalesce(p_driver_registration_enabled,true),
      p_center_latitude,
      p_center_longitude,
      p_radius_km,
      v_key,
      upper(coalesce(
        nullif(trim(coalesce(p_currency_code,'')),''),
        v_country.currency_code
      ))
    )
    returning id into v_id;
  else
    update public.service_zones
    set name=trim(p_name),
        city=nullif(trim(coalesce(p_city,'')),''),
        region_department=nullif(trim(coalesce(p_region_department,'')),''),
        country=v_country.name,
        country_code=v_code,
        active=coalesce(p_active,true),
        driver_registration_enabled=
          coalesce(p_driver_registration_enabled,true),
        center_latitude=p_center_latitude,
        center_longitude=p_center_longitude,
        radius_km=p_radius_km,
        zone_key=v_key,
        currency_code=upper(coalesce(
          nullif(trim(coalesce(p_currency_code,'')),''),
          v_country.currency_code
        )),
        updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Zona no encontrada'; end if;
  return v_id;
end;
$$;

revoke all on function public.admin_upsert_zone_v3(
  uuid,text,text,text,text,boolean,boolean,numeric,numeric,numeric,text,text
) from public,anon;
grant execute on function public.admin_upsert_zone_v3(
  uuid,text,text,text,text,boolean,boolean,numeric,numeric,numeric,text,text
) to authenticated;

create or replace function public.admin_zone_list_v2()
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id',z.id,
        'name',z.name,
        'city',z.city,
        'region_department',z.region_department,
        'country',z.country,
        'country_code',z.country_code,
        'country_active',coalesce(c.active,false),
        'active',z.active,
        'driver_registration_enabled',z.driver_registration_enabled,
        'country_driver_registration_enabled',
          coalesce(c.driver_registration_enabled,false),
        'didit_enabled',coalesce(v.didit_enabled,false),
        'center_latitude',z.center_latitude,
        'center_longitude',z.center_longitude,
        'radius_km',z.radius_km,
        'zone_key',z.zone_key,
        'currency_code',z.currency_code,
        'payment_provider',z.payment_provider,
        'payment_enabled',z.payment_enabled,
        'passenger_landing_mode',z.passenger_landing_mode,
        'passenger_default_module',z.passenger_default_module,
        'passenger_landing_title',z.passenger_landing_title,
        'passenger_landing_subtitle',z.passenger_landing_subtitle,
        'passenger_landing_order',z.passenger_landing_order,
        'payment_methods',coalesce((
          select jsonb_agg(jsonb_build_object(
            'provider_key',m.provider_key,
            'display_name',pc.display_name,
            'enabled',m.enabled,
            'use_rides',m.use_rides,
            'use_delivery',m.use_delivery,
            'use_subscriptions',m.use_subscriptions,
            'use_wallet',m.use_wallet,
            'is_primary',m.is_primary,
            'sort_order',m.sort_order
          ) order by m.sort_order,pc.display_name)
          from public.zone_payment_methods m
          join public.payment_method_catalog pc
            on pc.provider_key=m.provider_key
          where m.zone_id=z.id
        ),'[]'::jsonb)
      )
      order by z.country,z.city,z.name
    ),'[]'::jsonb)
    from public.service_zones z
    left join public.service_countries c
      on c.country_code=upper(coalesce(z.country_code,''))
    left join public.identity_verification_country_settings v
      on v.country_code=c.country_code
  );
end;
$$;

create or replace function public.service_zone_id_for_point(
  p_lat numeric,
  p_lng numeric
)
returns uuid
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_id uuid;
begin
  if p_lat is null or p_lng is null then return null; end if;

  select z.id
  into v_id
  from public.service_zones z
  join public.service_countries c
    on c.country_code=upper(coalesce(z.country_code,''))
   and c.active=true
  where z.active=true
    and (
      (
        exists(
          select 1
          from public.service_zone_polygons p
          where p.zone_id=z.id and p.active=true
        )
        and exists(
          select 1
          from public.service_zone_polygons p
          where p.zone_id=z.id
            and p.active=true
            and public.point_in_json_polygon(p_lat,p_lng,p.polygon)
        )
      )
      or
      (
        not exists(
          select 1
          from public.service_zone_polygons p
          where p.zone_id=z.id and p.active=true
        )
        and z.center_latitude is not null
        and z.center_longitude is not null
        and public.geo_distance_km(
          p_lat,p_lng,z.center_latitude,z.center_longitude
        ) <= greatest(coalesce(z.radius_km,20),0.5)
      )
    )
  order by
    case when exists(
      select 1
      from public.service_zone_polygons p
      where p.zone_id=z.id
        and p.active=true
        and public.point_in_json_polygon(p_lat,p_lng,p.polygon)
    ) then 0 else 1 end,
    public.geo_distance_km(
      p_lat,p_lng,z.center_latitude,z.center_longitude
    )
  limit 1;

  return v_id;
end;
$$;

create or replace function public.app_zone_context(
  p_lat numeric,
  p_lng numeric,
  p_for text default 'passenger'::text
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
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
      'availability_code','service_not_available',
      'availability_message',
        'Express todavía no está disponible en esta zona.',
      'zone',null,
      'services','[]'::jsonb,
      'subscription',null,
      'payment',null
    );
  end if;

  select jsonb_build_object(
    'id',z.id,
    'zone_key',z.zone_key,
    'name',z.name,
    'city',z.city,
    'country',z.country,
    'country_code',z.country_code,
    'currency_code',z.currency_code,
    'center_latitude',z.center_latitude,
    'center_longitude',z.center_longitude,
    'radius_km',z.radius_km,
    'payment_provider',z.payment_provider,
    'payment_enabled',z.payment_enabled
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
        'fare_rule',public.effective_fare_rule(
          s.service_key,v_zone_id
        )
      )
      order by zs.sort_order,s.name
    ),
    '[]'::jsonb
  )
  into v_services
  from public.zone_service_catalog zs
  join public.service_catalog s
    on s.service_key=zs.service_key
  where zs.zone_id=v_zone_id
    and zs.enabled=true
    and case
      when lower(coalesce(p_for,'passenger'))='driver'
        then zs.driver_visible
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
  left join public.driver_subscription_settings gs
    on gs.id=true
  where zs.zone_id=v_zone_id;

  return jsonb_build_object(
    'inside_coverage',true,
    'availability_code','available',
    'availability_message',null,
    'zone',v_zone,
    'services',coalesce(v_services,'[]'::jsonb),
    'subscription',v_subscription,
    'payment',jsonb_build_object(
      'provider',v_zone->>'payment_provider',
      'enabled',
        coalesce((v_zone->>'payment_enabled')::boolean,false),
      'method',case
        when v_zone->>'payment_provider'='veripagos_qr'
          then 'pagorut'
        when v_zone->>'payment_provider'='mercado_pago'
          then 'mercado_pago'
        else null
      end,
      'label',case
        when v_zone->>'payment_provider'='veripagos_qr'
          then 'QR Bolivia'
        when v_zone->>'payment_provider'='mercado_pago'
          then 'Mercado Pago'
        else null
      end
    )
  );
end;
$$;

create or replace function public.driver_onboarding_catalog(
  p_country_code text default null,
  p_zone_id uuid default null,
  p_lat numeric default null,
  p_lng numeric default null
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_country text :=
    upper(nullif(trim(coalesce(p_country_code,'')),''));
  v_zone uuid := p_zone_id;
  v_zone_row public.service_zones%rowtype;
  v_didit_enabled boolean := false;
  v_manual_fallback boolean := true;
  v_registration_allowed boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Autenticación requerida';
  end if;

  -- One authoritative coverage resolver for passengers and drivers.
  -- It already honors active country, active zone, polygon and radius.
  if v_zone is null and p_lat is not null and p_lng is not null then
    v_zone := public.service_zone_id_for_point(p_lat,p_lng);
  end if;

  if v_zone is not null then
    select z.* into v_zone_row
    from public.service_zones z
    join public.service_countries c
      on c.country_code=upper(coalesce(z.country_code,''))
     and c.active=true
     and c.driver_registration_enabled=true
    where z.id=v_zone
      and z.active=true
      and z.driver_registration_enabled=true;

    if v_zone_row.id is null then
      v_zone := null;
    end if;
  end if;

  if v_zone_row.id is not null then
    v_country :=
      upper(coalesce(v_zone_row.country_code,v_country));
    v_registration_allowed := true;
  end if;

  select
    coalesce(s.didit_enabled,false),
    coalesce(s.manual_fallback_enabled,true)
  into v_didit_enabled,v_manual_fallback
  from public.identity_verification_country_settings s
  where s.country_code=v_country;

  return jsonb_build_object(
    'registration_allowed',v_registration_allowed,
    'availability_code',
      case
        when v_registration_allowed then 'available'
        else 'service_not_available'
      end,
    'availability_message',
      case
        when v_registration_allowed then null
        else
          'Express todavía no está disponible para conductores en esta zona.'
      end,
    'countries',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'code',c.country_code,
            'name',c.name,
            'currency_code',c.currency_code
          )
          order by c.name
        ),
        '[]'::jsonb
      )
      from public.service_countries c
      where c.active=true
        and c.driver_registration_enabled=true
        and exists(
          select 1
          from public.service_zones z
          where upper(coalesce(z.country_code,''))=c.country_code
            and z.active=true
            and z.driver_registration_enabled=true
        )
    ),
    'zones',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id',z.id,
            'zone_key',z.zone_key,
            'name',z.name,
            'city',z.city,
            'country',z.country,
            'country_code',z.country_code,
            'center_latitude',z.center_latitude,
            'center_longitude',z.center_longitude,
            'radius_km',z.radius_km
          )
          order by z.city,z.name
        ),
        '[]'::jsonb
      )
      from public.service_zones z
      join public.service_countries c
        on c.country_code=upper(coalesce(z.country_code,''))
       and c.active=true
       and c.driver_registration_enabled=true
      where z.active=true
        and z.driver_registration_enabled=true
        and (
          v_country is null
          or upper(coalesce(z.country_code,''))=v_country
        )
    ),
    'suggested_zone_id',v_zone,
    'selected_zone',
      case
        when v_zone_row.id is null then null
        else jsonb_build_object(
          'id',v_zone_row.id,
          'zone_key',v_zone_row.zone_key,
          'name',v_zone_row.name,
          'city',v_zone_row.city,
          'country',v_zone_row.country,
          'country_code',v_zone_row.country_code
        )
      end,
    'services',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'service_key',catalog.service_key,
            'name',catalog.name,
            'description',catalog.description,
            'icon_key',catalog.icon_key,
            'vehicle_type',catalog.vehicle_type,
            'sort_order',zc.sort_order
          )
          order by zc.sort_order,catalog.name
        ),
        '[]'::jsonb
      )
      from public.zone_service_catalog zc
      join public.service_catalog catalog
        on catalog.service_key=zc.service_key
      where v_zone is not null
        and zc.zone_id=v_zone
        and zc.enabled=true
        and zc.driver_visible=true
        and catalog.enabled=true
        and catalog.driver_visible=true
    ),
    'document_requirements',(
      select coalesce(
        jsonb_agg(
          to_jsonb(r)
          order by r.sort_order,r.label
        ),
        '[]'::jsonb
      )
      from public.driver_document_requirements r
      where r.active=true
        and (
          r.country_code is null
          or upper(r.country_code)=v_country
        )
        and (r.zone_id is null or r.zone_id=v_zone)
        and (
          not v_didit_enabled
          or lower(coalesce(r.code,'')) not in (
            'identity_card',
            'national_id',
            'id_card',
            'identity',
            'cedula',
            'carnet'
          )
        )
    ),
    'verification_settings',
      jsonb_build_object(
        'didit_enabled',coalesce(v_didit_enabled,false),
        'manual_fallback_enabled',
          coalesce(v_manual_fallback,true)
      )
  );
end;
$$;

create or replace function public.submit_driver_onboarding_v2(
  p_zone_id uuid,
  p_license_number text,
  p_service_keys text[],
  p_vehicle_type text,
  p_vehicle_brand text,
  p_vehicle_model text,
  p_vehicle_color text,
  p_vehicle_plate text,
  p_vehicle_year integer,
  p_profile_photo_path text,
  p_vehicle_photo_paths text[],
  p_documents jsonb,
  p_lat numeric,
  p_lng numeric
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_detected uuid;
  v_zone public.service_zones%rowtype;
begin
  if v_uid is null then
    raise exception 'Autenticación requerida';
  end if;
  if p_lat is null or p_lng is null then
    raise exception 'Activa el GPS para registrarte como conductor';
  end if;

  v_detected := public.service_zone_id_for_point(p_lat,p_lng);
  if v_detected is null then
    raise exception
      'Express todavía no está disponible para conductores en esta zona';
  end if;
  if v_detected is distinct from p_zone_id then
    raise exception
      'La ciudad seleccionada no coincide con tu ubicación actual';
  end if;

  select z.* into v_zone
  from public.service_zones z
  join public.service_countries c
    on c.country_code=upper(coalesce(z.country_code,''))
   and c.active=true
   and c.driver_registration_enabled=true
  where z.id=p_zone_id
    and z.active=true
    and z.driver_registration_enabled=true;

  if v_zone.id is null then
    raise exception
      'El registro de conductores no está habilitado en esta zona';
  end if;

  return public.submit_driver_onboarding(
    p_zone_id,
    p_license_number,
    p_service_keys,
    p_vehicle_type,
    p_vehicle_brand,
    p_vehicle_model,
    p_vehicle_color,
    p_vehicle_plate,
    p_vehicle_year,
    p_profile_photo_path,
    p_vehicle_photo_paths,
    p_documents
  );
end;
$$;

revoke all on function public.submit_driver_onboarding_v2(
  uuid,text,text[],text,text,text,text,text,integer,text,text[],
  jsonb,numeric,numeric
) from public,anon;
grant execute on function public.submit_driver_onboarding_v2(
  uuid,text,text[],text,text,text,text,text,integer,text,text[],
  jsonb,numeric,numeric
) to authenticated;
