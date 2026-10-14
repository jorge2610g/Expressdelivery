-- Preserve Preview/Production separation while deriving all three
-- passenger modules from the one selected set in Admin Express.
-- No existing zone settings, fares, subscriptions, account bindings or
-- driver grants are modified by this migration.
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
      left join public.admin_environment_config ride_preview
        on v_preview and ride_preview.environment='preview'
       and ride_preview.module='zone_services'
       and ride_preview.record_key=v_zone_id::text || ':' || zs.service_key
      where zs.zone_id=v_zone_id
        and zs.service_key not in ('delivery','parcel')
        and (case when v_preview
          then coalesce((ride_preview.payload->>'enabled')::boolean,zs.enabled)
          else zs.enabled end)
        and (case when v_preview
          then coalesce((ride_preview.payload->>'passenger_visible')::boolean,zs.passenger_visible)
          else zs.passenger_visible end)
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
    -- Envíos requires the real parcel trip engine too, not only the
    -- legacy delivery landing key. Otherwise the card opens a disabled flow.
    and exists(
      select 1
      from public.zone_service_catalog zs
      left join public.admin_environment_config parcel_preview
        on v_preview and parcel_preview.environment='preview'
       and parcel_preview.module='zone_services'
       and parcel_preview.record_key=v_zone_id::text || ':parcel'
      where zs.zone_id=v_zone_id and zs.service_key='parcel'
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

CREATE OR REPLACE FUNCTION public.app_zone_context_v3(p_lat numeric, p_lng numeric, p_for text DEFAULT 'passenger'::text, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_base jsonb;
  v_zone_id uuid;
  v_methods jsonb:='[]'::jsonb;
  v_preview_services jsonb:='[]'::jsonb;
  v_first jsonb;
begin
  v_base:=public.app_zone_context_v2(p_lat,p_lng,p_for,p_channel);
  if coalesce((v_base->>'inside_coverage')::boolean,false)=false then
    return v_base||jsonb_build_object('payment_methods','[]'::jsonb);
  end if;

  v_zone_id:=nullif(v_base->'zone'->>'id','')::uuid;
  -- Preview identity may use isolated per-zone flags for BOTH Taxi and
  -- Envíos. Production keeps its authoritative zone_service_catalog rows.
  -- Never trust the caller-provided channel to grant Preview access.
  if public.admin_user_runtime_environment(auth.uid())='preview' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'service_key',s.service_key,
      'name',s.name,
      'description',s.description,
      'icon_key',s.icon_key,
      'vehicle_type',coalesce(s.vehicle_type,'car'),
      'enabled',coalesce((o.payload->>'enabled')::boolean,zs.enabled),
      'passenger_visible',
        coalesce((o.payload->>'passenger_visible')::boolean,zs.passenger_visible),
      'driver_visible',
        coalesce((o.payload->>'driver_visible')::boolean,zs.driver_visible),
      'allow_bidding',
        coalesce((o.payload->>'allow_bidding')::boolean,zs.allow_bidding),
      'allow_fixed_price',
        coalesce((o.payload->>'allow_fixed_price')::boolean,zs.allow_fixed_price),
      'scheduled_enabled',
        coalesce((o.payload->>'scheduled_enabled')::boolean,zs.scheduled_enabled),
      'sort_order',coalesce((o.payload->>'sort_order')::integer,zs.sort_order),
      'fare_rule',public.effective_fare_rule(s.service_key,v_zone_id)
    ) order by zs.sort_order,s.name),'[]'::jsonb)
    into v_preview_services
    from public.zone_service_catalog zs
    join public.service_catalog s on s.service_key=zs.service_key
    left join public.admin_environment_config o
      on o.environment='preview' and o.module='zone_services'
     and o.record_key=v_zone_id::text || ':' || zs.service_key
    where zs.zone_id=v_zone_id and s.enabled=true
      and coalesce((o.payload->>'enabled')::boolean,zs.enabled)
      and case when lower(coalesce(p_for,'passenger'))='driver'
         then coalesce((o.payload->>'driver_visible')::boolean,zs.driver_visible)
         else coalesce((o.payload->>'passenger_visible')::boolean,zs.passenger_visible)
      end;
    v_base:=v_base||jsonb_build_object('services',v_preview_services);
  end if;

  v_methods:=public.zone_ride_payment_methods(v_zone_id,p_channel);
  v_first:=case
    when jsonb_array_length(v_methods)>0 then v_methods->0
    else null
  end;

  return v_base||jsonb_build_object(
    'payment_methods',v_methods,
    'payment',case when v_first is null then null else jsonb_build_object(
      'provider',v_first->>'provider_key',
      'method',v_first->>'provider_key',
      'label',v_first->>'display_name',
      'enabled',true
    ) end
  );
end;
$function$

