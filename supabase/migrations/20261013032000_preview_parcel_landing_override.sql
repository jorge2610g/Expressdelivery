-- Use per-zone Preview parcel permission, never unlock Production.
-- Server decides account environment, not a client request parameter.
CREATE OR REPLACE FUNCTION public.app_zone_context_v2(p_lat numeric, p_lng numeric, p_for text DEFAULT 'passenger'::text, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_preview boolean:=false;
  v_runtime text;
  v_preview_zone jsonb;
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

  -- A request parameter cannot grant access to Preview. Resolve the
  -- authenticated account binding on the server, even for shared Web builds.
  select b.environment into v_runtime
    from public.account_runtime_bindings b
   where b.user_id=auth.uid();

  if v_runtime is null then
    select case when exists (
      select 1
        from public.audit_test_group_members m
        join public.audit_test_groups g on g.id=m.group_id
       where m.user_id=auth.uid() and m.enabled=true and g.active=true
    ) then 'preview' else 'production' end into v_runtime;
  end if;
  v_preview := v_runtime='preview';

  -- Adminexpress persists Preview zone settings in a shadow store.
  -- Only a Preview identity may receive these settings. Production remains
  -- sourced from service_zones and is never overwritten by this overlay.
  if v_preview then
    select c.payload into v_preview_zone
      from public.admin_environment_config c
     where c.environment='preview'
       and c.module='service_zones'
       and c.record_key=v_zone_id::text;
    if v_preview_zone is not null
       and coalesce((v_preview_zone->>'_deleted')::boolean,false)=false then
      v_mode := coalesce(nullif(v_preview_zone->>'passenger_landing_mode',''),v_mode);
      v_default := coalesce(nullif(v_preview_zone->>'passenger_default_module',''),v_default);
      v_title := coalesce(nullif(v_preview_zone->>'passenger_landing_title',''),v_title);
      v_subtitle := coalesce(nullif(v_preview_zone->>'passenger_landing_subtitle',''),v_subtitle);
      if jsonb_typeof(v_preview_zone->'passenger_landing_order')='array'
         and jsonb_array_length(v_preview_zone->'passenger_landing_order') between 1 and 3 then
        v_order := v_preview_zone->'passenger_landing_order';
      end if;
    end if;
  end if;

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
      left join public.admin_environment_config parcel_preview
        on v_preview and parcel_preview.environment='preview'
       and parcel_preview.module='zone_services'
       and parcel_preview.record_key=v_zone_id::text || ':delivery'
      where zs.zone_id=v_zone_id and zs.service_key='delivery'
        and (case when v_preview
          then coalesce((parcel_preview.payload->>'enabled')::boolean,zs.enabled)
          else zs.enabled end)
        and (case when v_preview
          then coalesce((parcel_preview.payload->>'passenger_visible')::boolean,zs.passenger_visible)
          else zs.passenger_visible end)
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
    -- The ordered set is now also the independent per-zone visibility set.
    -- An older zone listing all three keeps exactly its previous behavior.
    where exists (
      select 1
      from jsonb_array_elements_text(coalesce(v_order,
        '["ride","delivery","market"]'::jsonb)) visible(module_key)
      where visible.module_key=c.module_key
    )
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
$function$
