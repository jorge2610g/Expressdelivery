-- Brand the customer marketplace experience as Express Delivery.
-- This migration is additive/compatible: visibility flags are intentionally
-- unchanged, so Marketplace remains disabled in Production until approved.

update public.marketplace_settings
set module_name='Express Delivery',
    hero_title='Pide lo que quieras con Express Delivery',
    hero_subtitle='Restaurantes, supermercados, farmacia y más.',
    search_placeholder='Busca restaurantes, tiendas o productos',
    updated_at=now()
where id=true;

create or replace function public.admin_marketplace_update_settings(
  p_preview_enabled boolean,
  p_production_enabled boolean,
  p_module_name text,
  p_search_placeholder text,
  p_hero_title text,
  p_hero_subtitle text
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.marketplace_settings
  set preview_enabled=coalesce(p_preview_enabled,false),
      production_enabled=coalesce(p_production_enabled,false),
      module_name=coalesce(
        nullif(trim(p_module_name),''),
        'Express Delivery'
      ),
      search_placeholder=coalesce(
        nullif(trim(p_search_placeholder),''),
        'Busca restaurantes, tiendas o productos'
      ),
      hero_title=coalesce(
        nullif(trim(p_hero_title),''),
        'Pide lo que quieras con Express Delivery'
      ),
      hero_subtitle=coalesce(
        nullif(trim(p_hero_subtitle),''),
        'Restaurantes, supermercados, farmacia y más.'
      ),
      updated_at=now()
  where id=true;

  perform public.admin_log_action(
    'update',
    'marketplace_settings',
    'global',
    jsonb_build_object(
      'preview_enabled',p_preview_enabled,
      'production_enabled',p_production_enabled
    )
  );

  return public.admin_marketplace_state();
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
stable
security definer
set search_path='public'
as $function$
declare
  v_base jsonb;
  v_zone_id uuid;
  v_mode text:='direct';
  v_default text:='ride';
  v_title text:='¿Qué necesitas hoy?';
  v_subtitle text:='Elige un servicio de Express';
  v_order jsonb:='["ride","delivery","market"]'::jsonb;
  v_modules jsonb:='[]'::jsonb;
  v_market_enabled boolean:=false;
  v_preview boolean:=
    lower(coalesce(p_channel,'production'))='preview';
begin
  v_base:=public.app_zone_context(p_lat,p_lng,p_for);

  if coalesce((v_base->>'inside_coverage')::boolean,false)=false then
    return v_base||jsonb_build_object(
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

  v_zone_id:=nullif(v_base->'zone'->>'id','')::uuid;

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
    case
      when v_preview then preview_enabled
      else production_enabled
    end,
    false
  )
  into v_market_enabled
  from public.marketplace_settings
  where id=true;

  with candidates as (
    select
      'ride'::text as module_key,
      'Viajes'::text as title,
      'Pide un viaje con las categorías disponibles en tu zona.'::text
        as subtitle,
      'local_taxi'::text as icon_key,
      10 as fallback_order
    where exists(
      select 1
      from public.zone_service_catalog zs
      where zs.zone_id=v_zone_id
        and zs.service_key<>'delivery'
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
      'Express Delivery',
      'Pide comida, supermercado, farmacia y más.',
      'storefront',
      30
    where v_market_enabled
      and exists(
        select 1
        from public.marketplace_merchants m
        where m.active=true
          and (m.zone_id is null or m.zone_id=v_zone_id)
          and case
            when v_preview then m.preview_visible
            else m.production_visible
          end
      )
  ),
  ordered as (
    select
      c.*,
      coalesce(
        (
          select o.ord::int
          from jsonb_array_elements_text(
            coalesce(v_order,'[]'::jsonb)
          ) with ordinality as o(value,ord)
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

  return v_base||jsonb_build_object(
    'landing',
    jsonb_build_object(
      'mode',coalesce(v_mode,'direct'),
      'default_module',coalesce(v_default,'ride'),
      'title',coalesce(v_title,'¿Qué necesitas hoy?'),
      'subtitle',coalesce(
        v_subtitle,
        'Elige un servicio de Express'
      ),
      'modules',coalesce(v_modules,'[]'::jsonb)
    )
  );
end;
$function$;
