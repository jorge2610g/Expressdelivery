-- Resolve driver subscription payment provider from the driver's operational zone.
-- Chile must never fall through to the Bolivia VeriPagos integration.

create or replace function public.driver_subscription_catalog_for_me()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
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
  v_payment_provider_key text;
  v_payment_provider_label text;
  v_provider text;
  v_provider_enabled boolean := false;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;

  select dp.zone_id into v_zone_id
  from public.driver_profiles dp where dp.id=v_uid;

  if v_zone_id is null then
    return jsonb_build_object(
      'zone',null,
      'enabled',false,
      'enforce_access',false,
      'provider',null,
      'provider_enabled',false,
      'payment_provider_key',null,
      'payment_provider_label',null,
      'plans','[]'::jsonb
    );
  end if;

  select zone_key,name,currency_code
  into v_zone_key,v_zone_name,v_currency
  from public.service_zones
  where id=v_zone_id;

  select enabled,enforce_access
  into v_enabled,v_enforce
  from public.driver_subscription_zone_settings
  where zone_id=v_zone_id;

  select * into v_global
  from public.driver_subscription_settings
  where id=true;

  select m.provider_key,c.display_name
  into v_payment_provider_key,v_payment_provider_label
  from public.zone_payment_methods m
  join public.payment_method_catalog c
    on c.provider_key=m.provider_key
  where m.zone_id=v_zone_id
    and m.enabled=true
    and m.use_subscriptions=true
  order by m.is_primary desc,m.sort_order,c.display_name
  limit 1;

  if v_payment_provider_key='veripagos_qr' then
    v_provider := 'veripagos';
    v_provider_enabled := coalesce(v_global.provider_enabled,false);
  elsif v_payment_provider_key='mercado_pago' then
    v_provider := 'mercado_pago';
    v_provider_enabled := false;
  elsif v_payment_provider_key is not null then
    v_provider := v_payment_provider_key;
    v_provider_enabled := false;
  else
    v_provider := null;
    v_provider_enabled := false;
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(p) order by p.sort_order,p.id),
    '[]'::jsonb
  )
  into v_plans
  from public.driver_subscription_plans p
  where p.zone_key=v_zone_key
    and p.active=true;

  return jsonb_build_object(
    'zone',jsonb_build_object(
      'id',v_zone_id,
      'zone_key',v_zone_key,
      'name',v_zone_name,
      'currency_code',v_currency
    ),
    'enabled',coalesce(v_enabled,false),
    'enforce_access',coalesce(v_enforce,false),
    'provider',v_provider,
    'provider_enabled',coalesce(v_provider_enabled,false),
    'payment_provider_key',v_payment_provider_key,
    'payment_provider_label',v_payment_provider_label,
    'qr_validity',coalesce(v_global.qr_validity,'0/00:15'),
    'plans',coalesce(v_plans,'[]'::jsonb)
  );
end;
$function$;

revoke execute on function public.driver_subscription_catalog_for_me() from public, anon;
grant execute on function public.driver_subscription_catalog_for_me() to authenticated;


create or replace function public.admin_zone_subscription_settings(p_zone_key text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_zone public.service_zones%rowtype;
  v_settings public.driver_subscription_zone_settings%rowtype;
  v_global public.driver_subscription_settings%rowtype;
  v_provider_key text;
  v_provider_label text;
  v_provider_enabled boolean := false;
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

  select m.provider_key,c.display_name
  into v_provider_key,v_provider_label
  from public.zone_payment_methods m
  join public.payment_method_catalog c
    on c.provider_key=m.provider_key
  where m.zone_id=v_zone.id
    and m.enabled=true
    and m.use_subscriptions=true
  order by m.is_primary desc,m.sort_order,c.display_name
  limit 1;

  if v_provider_key='veripagos_qr' then
    v_provider_enabled := coalesce(v_global.provider_enabled,false);
  elsif v_provider_key is not null then
    v_provider_enabled := true;
  end if;

  return jsonb_build_object(
    'zone_id',v_zone.id,
    'zone_key',v_zone.zone_key,
    'zone_name',v_zone.name,
    'currency_code',v_zone.currency_code,
    'enabled',coalesce(v_settings.enabled,false),
    'enforce_access',coalesce(v_settings.enforce_access,false),
    'provider',case
      when v_provider_key='veripagos_qr' then 'veripagos'
      else v_provider_key
    end,
    'provider_key',v_provider_key,
    'provider_label',v_provider_label,
    'provider_enabled',coalesce(v_provider_enabled,false),
    'qr_validity',coalesce(v_global.qr_validity,'0/00:15')
  );
end;
$function$;
