-- One administrative session can inspect both data channels when the
-- authenticated admin has been granted both. The channel remains a filter on
-- channel-tagged records; operators and zone monitors stay Production-only.

create or replace function public.admin_environment_allowed(p_channel text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_channel text := lower(trim(coalesce(p_channel, '')));
  v_allowed boolean;
begin
  if v_channel not in ('preview', 'production') then
    return false;
  end if;

  select case
           when v_channel = 'preview' then
             a.allow_preview and a.access_role = 'super_admin'
           else a.allow_production
         end
    into v_allowed
  from public.admin_users a
  join public.users u on u.id = a.user_id
  where a.user_id = auth.uid()
    and a.active = true
    and u.account_status = 'active'
  limit 1;

  return coalesce(v_allowed, false);
end;
$$;

create or replace function public.admin_access_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_admin public.admin_users%rowtype;
  v_runtime text := public.admin_current_runtime_environment();
  v_zone public.service_zones%rowtype;
  v_envs jsonb;
  v_allowed_modules jsonb;
begin
  select a.* into v_admin
  from public.admin_users a
  join public.users u on u.id = a.user_id
  where a.user_id = auth.uid()
    and a.active = true
    and u.account_status = 'active'
  limit 1;
  if not found then
    return jsonb_build_object('allowed', false, 'allowed_modules', '[]'::jsonb);
  end if;

  if v_admin.access_role = 'super_admin' then
    v_envs := jsonb_build_array(
      case when v_admin.allow_preview then 'preview' end,
      case when v_admin.allow_production then 'production' end
    );
    select coalesce(jsonb_agg(value), '[]'::jsonb) into v_envs
    from jsonb_array_elements(v_envs) x(value)
    where value <> 'null'::jsonb;
  else
    v_envs := case when v_admin.allow_production
      then '["production"]'::jsonb else '[]'::jsonb end;
  end if;

  if not (v_envs ? v_runtime) then
    v_runtime := case when v_envs ? 'production' then 'production'
                      when v_envs ? 'preview' then 'preview'
                      else null end;
  end if;

  if v_admin.access_role = 'operator' then
    select to_jsonb(array(
      select distinct t.module_key
      from unnest(coalesce(v_admin.allowed_modules, array['users']::text[])) as t(module_key)
      join public.admin_operator_module_capabilities c on c.module_key = t.module_key
      where c.runtime_ready = true
      order by t.module_key
    )) into v_allowed_modules;
  elsif v_admin.allowed_modules is not null then
    v_allowed_modules := to_jsonb(v_admin.allowed_modules);
  elsif v_admin.access_role = 'super_admin' then
    v_allowed_modules := '["*"]'::jsonb;
  elsif v_admin.access_role = 'zone_monitor' then
    v_allowed_modules := '["dashboard","live_operations","trips","delivery","drivers","users","safety_sos","delivery_orders"]'::jsonb;
  else
    v_allowed_modules := '[]'::jsonb;
  end if;

  if v_admin.zone_id is not null then
    select * into v_zone from public.service_zones z where z.id = v_admin.zone_id;
  end if;

  return jsonb_build_object(
    'allowed', v_runtime is not null,
    'role', v_admin.access_role,
    'read_only', v_admin.access_role = 'zone_monitor',
    'zone_id', v_admin.zone_id,
    'zone_key', v_zone.zone_key,
    'zone_name', v_zone.name,
    'city', v_zone.city,
    'region_department', v_zone.region_department,
    'country', v_zone.country,
    'country_code', v_zone.country_code,
    'allow_preview', v_admin.allow_preview and v_admin.access_role = 'super_admin',
    'allow_production', v_admin.allow_production,
    'runtime_environment', v_runtime,
    'can_switch_environment', jsonb_array_length(v_envs) > 1,
    'default_environment', v_runtime,
    'allowed_environments', v_envs,
    'allowed_modules', v_allowed_modules,
    'assigned_modules', case when v_admin.access_role = 'operator'
      then to_jsonb(coalesce(v_admin.allowed_modules, array['users']::text[]))
      else '[]'::jsonb end
  );
end;
$$;


-- Shared configuration: all account channels resolve zone/service visibility
-- through canonical configuration tables. Channel tags remain on
-- accounts, permissions, orders, trips, and payments.

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

  select coalesce(production_enabled, false)
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
        and zs.service_key not in ('delivery','parcel')
        and zs.enabled
        and zs.passenger_visible
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
      where zs.zone_id=v_zone_id and zs.service_key='delivery'
        and zs.enabled and zs.passenger_visible
    )
    -- Envíos requires the real parcel trip engine too, not only the
    -- legacy delivery landing key. Otherwise the card opens a disabled flow.
    and exists(
      select 1
      from public.zone_service_catalog zs
      where zs.zone_id=v_zone_id and zs.service_key='parcel'
        and zs.enabled and zs.passenger_visible
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
          and m.production_visible
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
$function$;

CREATE OR REPLACE FUNCTION public.app_zone_context_v3(
  p_lat numeric,
  p_lng numeric,
  p_for text DEFAULT 'passenger'::text,
  p_channel text DEFAULT 'production'::text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_base jsonb;
  v_zone_id uuid;
  v_methods jsonb := '[]'::jsonb;
  v_first jsonb;
begin
  -- Zone, coverage and service visibility are shared. Payment methods retain
  -- channel-specific provider configuration for safe Preview payment testing.
  v_base := public.app_zone_context_v2(p_lat, p_lng, p_for, p_channel);
  if coalesce((v_base->>'inside_coverage')::boolean, false) = false then
    return v_base || jsonb_build_object('payment_methods', '[]'::jsonb);
  end if;

  v_zone_id := nullif(v_base->'zone'->>'id', '')::uuid;
  v_methods := public.zone_ride_payment_methods(v_zone_id, p_channel);
  v_first := case
    when jsonb_array_length(v_methods) > 0 then v_methods->0
    else null
  end;

  return v_base || jsonb_build_object(
    'payment_methods', v_methods,
    'payment', case when v_first is null then null else jsonb_build_object(
      'provider', v_first->>'provider_key',
      'method', v_first->>'provider_key',
      'label', v_first->>'display_name',
      'enabled', true
    ) end
  );
end;
$function$;

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
         where dp.id=p_driver_id
           and cat.enabled and cat.driver_visible
           and zc.enabled and zc.driver_visible
       ) end;
$$;

CREATE OR REPLACE FUNCTION public.express_parcel_zone_available(
 p_zone_id uuid,p_channel text,p_audience text
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public AS $$
 SELECT EXISTS(
  SELECT 1 FROM public.zone_service_catalog zc
  JOIN public.service_catalog c ON c.service_key=zc.service_key
  WHERE zc.zone_id=p_zone_id AND zc.service_key='parcel' AND c.enabled
   AND zc.enabled
   AND CASE WHEN p_audience='driver'
      THEN zc.driver_visible
      ELSE zc.passenger_visible END);
$$;

-- Global driver behavior is shared across account channels. The channel still
-- scopes the driver's records and dispatch operations, but does not fork these
-- switches or scoring rules.
create or replace function public.driver_priority_settings_for(p_channel text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  if lower(trim(coalesce(p_channel, ''))) not in ('preview', 'production') then
    return '{}'::jsonb;
  end if;

  select (to_jsonb(s) - 'id') || jsonb_build_object(
    'preview_enabled', s.production_enabled,
    'preview_enforcement_enabled', s.production_enforcement_enabled
  )
  into v_payload
  from public.driver_priority_settings s
  where s.id = true;

  return coalesce(v_payload, '{}'::jsonb);
end;
$$;

create or replace function public.driver_floating_offer_config(
  p_channel text default 'production'
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_channel text := lower(trim(coalesce(p_channel, '')));
  v_enabled boolean;
begin
  if v_channel not in ('preview', 'production') then
    return false;
  end if;
  if auth.uid() is not null
     and public.admin_user_runtime_environment(auth.uid()) <> v_channel then
    return false;
  end if;

  select coalesce(s.driver_floating_offer_enabled, false)
  into v_enabled
  from public.app_settings s
  where s.id = true
  limit 1;

  return coalesce(v_enabled, false);
end;
$$;


-- Shared fare and commission configuration; channel remains on ledger data.
create or replace function public.settle_wallet_payment()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_balance numeric;
  v_commission_percent numeric:=0;
  v_commission numeric:=0;
  v_net numeric:=0;
  v_country text:=new.country_code;
  v_channel text:=public.normalize_runtime_channel(new.channel);
  v_direct boolean:=new.method in ('cash','driver_qr');
  v_zone_id uuid;
  v_service_key text;
  v_fare_rule jsonb;
  v_settings jsonb;
begin
  -- Resolve the actual ride service and zone before choosing its rate.
  if new.trip_id is not null then
    select r.zone_id,
           case when r.service_mode='parcel' then 'delivery'
                else coalesce(nullif(trim(r.category),''),'economy') end
    into v_zone_id,v_service_key
    from public.trips t
    join public.ride_requests r on r.id=t.ride_request_id
    where t.id=new.trip_id;
  elsif new.delivery_id is not null then
    select public.service_zone_id_for_point(
             d.pickup_latitude,
             d.pickup_longitude
           ),
           'delivery'
    into v_zone_id,v_service_key
    from public.delivery_requests d
    where d.id=new.delivery_id;
  end if;

  -- Commission and fare rules use the same canonical configuration for both
  -- account channels. Ledger rows below still keep new.channel for isolation.
  if v_zone_id is not null and v_service_key is not null then
    v_fare_rule:=public.effective_fare_rule(v_service_key,v_zone_id);
  end if;

  if v_fare_rule is not null then
    v_commission_percent:=least(
      greatest(coalesce((v_fare_rule->>'commission_percent')::numeric,0),0),
      100
    );
  else
    select coalesce(s.commission_percent,0)
    into v_commission_percent
    from public.app_settings s
    where s.id=true
    limit 1;
    v_commission_percent:=least(greatest(coalesce(v_commission_percent,0),0),100);
  end if;

  v_commission:=round(coalesce(new.amount,0)*v_commission_percent/100.0,2);
  v_net:=coalesce(new.amount,0)-v_commission;

  update public.payment_transactions
  set commission_percent=v_commission_percent,
      commission_amount=v_commission,
      driver_net_amount=case when new.payee_id is null then null else v_net end
  where id=new.id;

  if new.payee_id is null then return new; end if;

  if v_country is null then
    select country_code into v_country
    from public.payment_transactions
    where id=new.id;
  end if;

  if v_direct and new.status='paid' then
    if v_commission>0 then
      insert into public.wallet_transactions(
        user_id,amount,type,status,reference,
        trip_id,delivery_id,country_code,channel
      )
      values(
        new.payee_id,-v_commission,'commission','completed',
        case when new.method='driver_qr'
          then 'Comisión Express por servicio cobrado con QR del conductor'
          else 'Comisión Express por servicio en efectivo' end,
        new.trip_id,new.delivery_id,v_country,v_channel
      );
      if v_channel='production' then
        perform public.mirror_legacy_wallet_delta(
          new.payee_id,new.currency,-v_commission
        );
      end if;
    end if;
    return new;
  end if;

  if new.method='wallet' and new.status='pending' then
    insert into public.wallet_country_accounts(
      user_id,country_code,channel,currency,balance
    )
    values(new.payer_id,v_country,v_channel,upper(new.currency),0)
    on conflict(user_id,country_code,channel) do nothing;

    select balance into v_balance
    from public.wallet_country_accounts
    where user_id=new.payer_id
      and country_code=v_country
      and channel=v_channel
    for update;

    if coalesce(v_balance,0)<new.amount then
      perform set_config('app.runtime_channel',v_channel,true);
      insert into public.notifications(user_id,title,body,type,metadata)
      values(
        new.payer_id,'Saldo insuficiente',
        'Tu pago con Billetera Express quedó pendiente porque no tienes saldo suficiente.',
        'wallet_insufficient',
        jsonb_build_object(
          'country_code',v_country,'currency',new.currency,'channel',v_channel
        )
      );
      return new;
    end if;

    insert into public.wallet_transactions(
      user_id,amount,type,status,reference,
      trip_id,delivery_id,country_code,channel
    )
    values(
      new.payer_id,-new.amount,'payment','completed',
      'Pago de servicio Express',
      new.trip_id,new.delivery_id,v_country,v_channel
    );
    if v_channel='production' then
      perform public.mirror_legacy_wallet_delta(
        new.payer_id,new.currency,-new.amount
      );
    end if;

    insert into public.wallet_transactions(
      user_id,amount,type,status,reference,
      trip_id,delivery_id,country_code,channel
    )
    values(
      new.payee_id,new.amount,'earning','completed',
      'Ingreso bruto por servicio Express',
      new.trip_id,new.delivery_id,v_country,v_channel
    );

    if v_commission>0 then
      insert into public.wallet_transactions(
        user_id,amount,type,status,reference,
        trip_id,delivery_id,country_code,channel
      )
      values(
        new.payee_id,-v_commission,'commission','completed',
        'Comisión Express',
        new.trip_id,new.delivery_id,v_country,v_channel
      );
    end if;

    if v_channel='production' then
      perform public.mirror_legacy_wallet_delta(
        new.payee_id,new.currency,v_net
      );
    end if;

    update public.payment_transactions
    set status='paid',paid_at=now()
    where id=new.id;

    perform set_config('app.runtime_channel',v_channel,true);
    insert into public.notifications(user_id,title,body,type,metadata)
    values(
      new.payer_id,'Pago completado',
      'El pago con Billetera Express fue procesado correctamente.',
      'wallet_paid',
      jsonb_build_object(
        'country_code',v_country,'currency',new.currency,'channel',v_channel
      )
    );
    insert into public.notifications(user_id,title,body,type,metadata)
    values(
      new.payee_id,'Ganancia acreditada',
      'El importe neto del servicio fue acreditado en tu Billetera Express.',
      'wallet_earning',
      jsonb_build_object(
        'country_code',v_country,'currency',new.currency,'channel',v_channel
      )
    );
  end if;
  return new;
end;
$$;

-- Driver coverage enforcement was already globally evaluated, but its switch
-- lived in Preview storage. Move the effective value into the shared settings
-- row so both account channels use one policy.
alter table public.app_settings
  add column if not exists driver_zone_policy_enabled boolean not null default false;

update public.app_settings s
set driver_zone_policy_enabled = coalesce((
  select (c.payload->>'zone_follow_enabled')::boolean
  from public.admin_environment_config c
  where c.environment = 'preview'
    and c.module = 'driver_zone_policy'
    and c.record_key = 'default'
), false)
where s.id = true;

create or replace function public.driver_zone_policy_enabled()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(s.driver_zone_policy_enabled, false)
  from public.app_settings s
  where s.id = true;
$$;

create or replace function public.admin_driver_zone_policy_get()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_enabled boolean;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  select coalesce(s.driver_zone_policy_enabled, false)
  into v_enabled
  from public.app_settings s
  where s.id = true;
  return jsonb_build_object(
    'preview_zone_follow_enabled', v_enabled,
    'production_zone_follow_enabled', v_enabled,
    'shared_zone_follow_enabled', v_enabled
  );
end;
$$;

create or replace function public.admin_driver_zone_policy_set(
  p_preview_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  update public.app_settings
  set driver_zone_policy_enabled = coalesce(p_preview_enabled, false),
      updated_at = now()
  where id = true;
  return public.admin_driver_zone_policy_get();
end;
$$;

-- Marketplace catalogs and availability are shared. Preserve production's
-- existing configuration as canonical, sync legacy Preview columns once,
-- then keep the two compatibility columns aligned for older clients/RPCs.
update public.marketplace_settings
set preview_enabled = production_enabled
where preview_enabled is distinct from production_enabled;

update public.marketplace_zone_settings
set preview_enabled = production_enabled
where preview_enabled is distinct from production_enabled;

create or replace function public.sync_shared_marketplace_visibility()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.preview_visible := coalesce(new.production_visible, false);
  return new;
end;
$$;

create or replace function public.sync_shared_marketplace_availability()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.preview_enabled := coalesce(new.production_enabled, false);
  return new;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'marketplace_banners',
    'marketplace_categories',
    'marketplace_coupons',
    'marketplace_home_sections',
    'marketplace_menu_sections',
    'marketplace_merchants',
    'marketplace_plus_plans'
  ] loop
    execute format('drop trigger if exists sync_shared_environment_visibility on public.%I', v_table);
    execute format(
      'create trigger sync_shared_environment_visibility before insert or update on public.%I for each row execute function public.sync_shared_marketplace_visibility()',
      v_table
    );
  end loop;
end;
$$;

drop trigger if exists sync_shared_environment_availability on public.marketplace_settings;
create trigger sync_shared_environment_availability
before insert or update on public.marketplace_settings
for each row execute function public.sync_shared_marketplace_availability();

drop trigger if exists sync_shared_environment_availability on public.marketplace_zone_settings;
create trigger sync_shared_environment_availability
before insert or update on public.marketplace_zone_settings
for each row execute function public.sync_shared_marketplace_availability();

-- Phone verification rules are operational policy, not an environment
-- setting. Both account channels read the one canonical rule and provider
-- readiness state; the user's account channel remains attached to requests.
create or replace function public.phone_verification_required_for_user(
  p_user_id uuid,
  p_role text,
  p_channel text default 'production'
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := lower(coalesce(trim(p_role), 'passenger'));
  v_channel text := public.normalize_runtime_channel(p_channel);
  v_settings jsonb;
  v_requested boolean := false;
  v_provider_ready boolean := false;
  v_rollout_at timestamptz;
  v_created_at timestamptz;
  v_verified_at timestamptz;
begin
  if p_user_id is null or v_channel not in ('preview', 'production') then
    return false;
  end if;

  select to_jsonb(s) into v_settings
  from public.app_settings s
  where s.id = true
  limit 1;

  v_requested := case when v_role = 'driver'
    then coalesce((v_settings->>'sms_verification_driver_enabled')::boolean, false)
    else coalesce((v_settings->>'sms_verification_passenger_enabled')::boolean, false)
  end;
  if not v_requested then return false; end if;

  select s.sms_provider_verified_at is not null
  into v_provider_ready
  from public.app_settings s
  where s.id = true;
  if not coalesce(v_provider_ready, false) then return false; end if;

  begin
    v_rollout_at := nullif(v_settings->>'sms_verification_rollout_at', '')::timestamptz;
  exception when others then
    v_rollout_at := null;
  end;
  if v_rollout_at is null then return false; end if;

  select u.created_at, u.phone_verified_at
  into v_created_at, v_verified_at
  from public.users u
  where u.id = p_user_id;

  if v_created_at is null then return false; end if;
  return v_created_at >= v_rollout_at or v_verified_at is not null;
end;
$$;

-- Subscription plans and zone rules use their canonical tables in both
-- channels. Driver assignments and payment history are filtered by the
-- account's server-side environment binding, never by email naming patterns.
create or replace function public.admin_driver_subscriptions_channel_v1(
  p_search text,
  p_zone_key text,
  p_channel text
)
returns table(
  driver_id uuid,
  full_name text,
  email text,
  phone text,
  approval_status text,
  online_status text,
  subscription_status text,
  plan_id bigint,
  plan_name text,
  started_at timestamptz,
  expires_at timestamptz,
  remaining_seconds bigint
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_zone_id uuid;
  v_channel text := lower(trim(coalesce(p_channel, '')));
begin
  if not public.admin_environment_allowed(v_channel) then
    raise exception 'No autorizado para consultar este entorno';
  end if;
  if coalesce(trim(p_zone_key), '') <> '' then
    select z.id into v_zone_id
    from public.service_zones z
    where z.zone_key = lower(trim(p_zone_key))
    limit 1;
  end if;

  return query
  select
    dp.id::uuid,
    coalesce(u.full_name, '')::text,
    coalesce(au.email, '')::text,
    coalesce(u.phone, '')::text,
    coalesce(dp.approval_status, '')::text,
    coalesce(dp.online_status, '')::text,
    coalesce(ds.status, 'inactive')::text,
    ds.plan_id::bigint,
    dsp.name::text,
    ds.started_at::timestamptz,
    ds.expires_at::timestamptz,
    case when ds.expires_at is null then 0::bigint
      else greatest(0::bigint, extract(epoch from (ds.expires_at - now()))::bigint)
    end::bigint
  from public.driver_profiles dp
  left join public.users u on u.id = dp.id
  left join auth.users au on au.id = dp.id
  left join public.driver_subscriptions ds on ds.driver_id = dp.id
  left join public.driver_subscription_plans dsp on dsp.id = ds.plan_id
  where (v_zone_id is null or dp.zone_id = v_zone_id)
    and public.admin_user_runtime_environment(dp.id) = v_channel
    and (
      coalesce(trim(p_search), '') = ''
      or coalesce(u.full_name, '') ilike '%' || trim(p_search) || '%'
      or coalesce(au.email, '') ilike '%' || trim(p_search) || '%'
      or coalesce(u.phone, '') ilike '%' || trim(p_search) || '%'
    )
  order by coalesce(ds.expires_at, 'epoch'::timestamptz) desc,
    coalesce(u.full_name, au.email::text, '');
end;
$$;

create or replace function public.admin_subscription_payment_list_channel_v1(
  p_zone_key text,
  p_from timestamptz,
  p_to timestamptz,
  p_status text,
  p_limit integer,
  p_offset integer,
  p_channel text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_channel text := lower(trim(coalesce(p_channel, '')));
begin
  if not public.admin_environment_allowed(v_channel) then
    raise exception 'No autorizado para consultar este entorno';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (
      select p.*
      from public.driver_subscription_payments p
      where (trim(coalesce(p_zone_key, '')) = '' or p.zone_key = p_zone_key)
        and (p_from is null or p.created_at >= p_from)
        and (p_to is null or p.created_at < p_to)
        and (trim(coalesce(p_status, '')) = '' or p.status = p_status)
        and public.admin_user_runtime_environment(p.driver_id) = v_channel
      order by p.created_at desc
      limit greatest(1, least(coalesce(p_limit, 100), 500))
      offset greatest(0, coalesce(p_offset, 0))
    ) x
  );
end;
$$;

create or replace function public.admin_set_driver_subscription_channel_v1(
  p_driver_id uuid,
  p_plan_id bigint,
  p_expires_at timestamptz,
  p_notes text,
  p_channel text
)
returns public.driver_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel text := lower(trim(coalesce(p_channel, '')));
  v_result public.driver_subscriptions%rowtype;
begin
  if not public.admin_environment_allowed(v_channel)
     or public.admin_user_runtime_environment(p_driver_id) <> v_channel then
    raise exception 'La cuenta de conductor no pertenece al entorno seleccionado';
  end if;
  select * into v_result
  from public.admin_set_driver_subscription(
    p_driver_id, p_plan_id, p_expires_at, p_notes
  );
  return v_result;
end;
$$;

revoke all on function public.admin_driver_subscriptions_channel_v1(text, text, text)
  from public, anon;
revoke all on function public.admin_subscription_payment_list_channel_v1(text, timestamptz, timestamptz, text, integer, integer, text)
  from public, anon;
revoke all on function public.admin_set_driver_subscription_channel_v1(uuid, bigint, timestamptz, text, text)
  from public, anon;
grant execute on function public.admin_driver_subscriptions_channel_v1(text, text, text)
  to authenticated;
grant execute on function public.admin_subscription_payment_list_channel_v1(text, timestamptz, timestamptz, text, integer, integer, text)
  to authenticated;
grant execute on function public.admin_set_driver_subscription_channel_v1(uuid, bigint, timestamptz, text, text)
  to authenticated;
