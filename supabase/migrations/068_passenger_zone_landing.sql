-- Passenger landing screen per operational zone.
-- Existing zones keep direct entry unless explicitly enabled; new zones default to auto.

alter table public.service_zones
  add column if not exists passenger_landing_mode text,
  add column if not exists passenger_default_module text,
  add column if not exists passenger_landing_title text,
  add column if not exists passenger_landing_subtitle text,
  add column if not exists passenger_landing_order jsonb;

update public.service_zones
set passenger_landing_mode = coalesce(passenger_landing_mode, 'direct'),
    passenger_default_module = coalesce(passenger_default_module, 'ride'),
    passenger_landing_title = coalesce(passenger_landing_title, '¿Qué necesitas hoy?'),
    passenger_landing_subtitle = coalesce(passenger_landing_subtitle, 'Elige un servicio de Express'),
    passenger_landing_order = coalesce(passenger_landing_order, '["ride","delivery","market"]'::jsonb);

alter table public.service_zones
  alter column passenger_landing_mode set default 'auto',
  alter column passenger_landing_mode set not null,
  alter column passenger_default_module set default 'ride',
  alter column passenger_default_module set not null,
  alter column passenger_landing_title set default '¿Qué necesitas hoy?',
  alter column passenger_landing_title set not null,
  alter column passenger_landing_subtitle set default 'Elige un servicio de Express',
  alter column passenger_landing_subtitle set not null,
  alter column passenger_landing_order set default '["ride","delivery","market"]'::jsonb,
  alter column passenger_landing_order set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='service_zones_passenger_landing_mode_check'
  ) then
    alter table public.service_zones
      add constraint service_zones_passenger_landing_mode_check
      check (passenger_landing_mode in ('auto','always','direct'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname='service_zones_passenger_default_module_check'
  ) then
    alter table public.service_zones
      add constraint service_zones_passenger_default_module_check
      check (passenger_default_module in ('ride','delivery','market'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname='service_zones_passenger_landing_order_check'
  ) then
    alter table public.service_zones
      add constraint service_zones_passenger_landing_order_check
      check (jsonb_typeof(passenger_landing_order)='array');
  end if;
end $$;

create or replace function public.admin_update_zone_landing(
  p_zone_id uuid,
  p_mode text,
  p_default_module text,
  p_title text,
  p_subtitle text,
  p_order jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_mode text := lower(trim(coalesce(p_mode,'auto')));
  v_default text := lower(trim(coalesce(p_default_module,'ride')));
  v_order jsonb := coalesce(p_order,'["ride","delivery","market"]'::jsonb);
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_mode not in ('auto','always','direct') then
    raise exception 'Modo de pantalla inicial inválido';
  end if;
  if v_default not in ('ride','delivery','market') then
    raise exception 'Módulo predeterminado inválido';
  end if;
  if jsonb_typeof(v_order) <> 'array' then
    raise exception 'Orden de módulos inválido';
  end if;
  if not exists(select 1 from public.service_zones where id=p_zone_id) then
    raise exception 'Zona no encontrada';
  end if;

  update public.service_zones
  set passenger_landing_mode=v_mode,
      passenger_default_module=v_default,
      passenger_landing_title=coalesce(nullif(trim(coalesce(p_title,'')),''),'¿Qué necesitas hoy?'),
      passenger_landing_subtitle=coalesce(nullif(trim(coalesce(p_subtitle,'')),''),'Elige un servicio de Express'),
      passenger_landing_order=v_order,
      updated_at=now()
  where id=p_zone_id;

  perform public.admin_log_action(
    'update_zone_landing',
    'service_zone',
    p_zone_id::text,
    jsonb_build_object(
      'mode',v_mode,
      'default_module',v_default,
      'order',v_order
    )
  );
end;
$function$;

create or replace function public.app_zone_context_v2(
  p_lat numeric,
  p_lng numeric,
  p_for text default 'passenger'::text,
  p_channel text default 'production'::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_base jsonb;
  v_zone_id uuid;
  v_mode text := 'direct';
  v_default text := 'ride';
  v_title text := '¿Qué necesitas hoy?';
  v_subtitle text := 'Elige un servicio de Express';
  v_order jsonb := '["ride","delivery","market"]'::jsonb;
  v_modules jsonb := '[]'::jsonb;
  v_market_enabled boolean := false;
  v_preview boolean := lower(coalesce(p_channel,'production'))='preview';
begin
  v_base := public.app_zone_context(p_lat,p_lng,p_for);

  if coalesce((v_base->>'inside_coverage')::boolean,false) is false then
    return v_base || jsonb_build_object(
      'landing',
      jsonb_build_object(
        'mode','direct',
        'default_module','ride',
        'title',v_title,
        'subtitle',v_subtitle,
        'modules','[]'::jsonb
      )
    );
  end if;

  v_zone_id := nullif(v_base->'zone'->>'id','')::uuid;

  select
    z.passenger_landing_mode,
    z.passenger_default_module,
    z.passenger_landing_title,
    z.passenger_landing_subtitle,
    z.passenger_landing_order
  into v_mode,v_default,v_title,v_subtitle,v_order
  from public.service_zones z
  where z.id=v_zone_id;

  select coalesce(
    case when v_preview then preview_enabled else production_enabled end,
    false
  )
  into v_market_enabled
  from public.marketplace_settings
  where id=true;

  with candidates as (
    select
      'ride'::text as module_key,
      'Viajes'::text as title,
      'Pide un viaje con las categorías disponibles en tu zona.'::text as subtitle,
      'local_taxi'::text as icon_key,
      10 as fallback_order
    where exists(
      select 1
      from public.zone_service_catalog zs
      where zs.zone_id=v_zone_id
        and zs.service_key <> 'delivery'
        and zs.enabled=true
        and zs.passenger_visible=true
    )
    union all
    select
      'delivery',
      'Envíos',
      'Envía paquetes y entregas con Express.',
      'local_shipping',
      20
    where exists(
      select 1
      from public.zone_service_catalog zs
      where zs.zone_id=v_zone_id
        and zs.service_key='delivery'
        and zs.enabled=true
        and zs.passenger_visible=true
    )
    union all
    select
      'market',
      'Express Market',
      'Comida, tiendas y productos cerca de ti.',
      'storefront',
      30
    where v_market_enabled
      and exists(
        select 1
        from public.marketplace_merchants m
        where m.active=true
          and (m.zone_id is null or m.zone_id=v_zone_id)
          and case when v_preview then m.preview_visible else m.production_visible end
      )
  ),
  ordered as (
    select
      c.*,
      coalesce(
        (
          select o.ord::int
          from jsonb_array_elements_text(coalesce(v_order,'[]'::jsonb))
               with ordinality as o(value,ord)
          where o.value=c.module_key
          limit 1
        ),
        100+c.fallback_order
      ) as sort_order
    from candidates c
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'module_key',module_key,
        'title',title,
        'subtitle',subtitle,
        'icon_key',icon_key,
        'sort_order',sort_order
      )
      order by sort_order,fallback_order
    ),
    '[]'::jsonb
  )
  into v_modules
  from ordered;

  return v_base || jsonb_build_object(
    'landing',
    jsonb_build_object(
      'mode',coalesce(v_mode,'direct'),
      'default_module',coalesce(v_default,'ride'),
      'title',coalesce(v_title,'¿Qué necesitas hoy?'),
      'subtitle',coalesce(v_subtitle,'Elige un servicio de Express'),
      'modules',coalesce(v_modules,'[]'::jsonb)
    )
  );
end;
$function$;

create or replace function public.admin_zone_list_v2()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id',z.id,'name',z.name,'city',z.city,'region_department',z.region_department,
        'country',z.country,'active',z.active,'center_latitude',z.center_latitude,
        'center_longitude',z.center_longitude,'radius_km',z.radius_km,
        'zone_key',z.zone_key,'currency_code',z.currency_code,
        'payment_provider',z.payment_provider,'payment_enabled',z.payment_enabled,
        'passenger_landing_mode',z.passenger_landing_mode,
        'passenger_default_module',z.passenger_default_module,
        'passenger_landing_title',z.passenger_landing_title,
        'passenger_landing_subtitle',z.passenger_landing_subtitle,
        'passenger_landing_order',z.passenger_landing_order,
        'payment_methods',coalesce((
          select jsonb_agg(jsonb_build_object(
            'provider_key',m.provider_key,'display_name',c.display_name,'enabled',m.enabled,
            'use_rides',m.use_rides,'use_delivery',m.use_delivery,
            'use_subscriptions',m.use_subscriptions,'use_wallet',m.use_wallet,
            'is_primary',m.is_primary,'sort_order',m.sort_order
          ) order by m.sort_order,c.display_name)
          from public.zone_payment_methods m
          join public.payment_method_catalog c on c.provider_key=m.provider_key
          where m.zone_id=z.id
        ),'[]'::jsonb)
      )
      order by z.country,z.city,z.name
    ),'[]'::jsonb)
    from public.service_zones z
  );
end;
$function$;

update public.service_zones
set passenger_landing_mode='auto',
    passenger_default_module='ride',
    passenger_landing_title='¿Qué necesitas hoy?',
    passenger_landing_subtitle='Elige una opción para comenzar',
    passenger_landing_order='["ride","delivery","market"]'::jsonb,
    updated_at=now()
where zone_key='iquique';


-- Explicit API permissions: both RPCs require a signed-in user.
revoke execute on function public.admin_update_zone_landing(uuid,text,text,text,text,jsonb) from public, anon;
grant execute on function public.admin_update_zone_landing(uuid,text,text,text,text,jsonb) to authenticated;

revoke execute on function public.app_zone_context_v2(numeric,numeric,text,text) from public, anon;
grant execute on function public.app_zone_context_v2(numeric,numeric,text,text) to authenticated;
