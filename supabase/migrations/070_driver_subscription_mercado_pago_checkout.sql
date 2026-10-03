-- Mercado Pago Checkout Pro for driver subscriptions in Chile.

create or replace function public.service_create_driver_subscription_payment(
  p_driver_id uuid,
  p_plan_id bigint,
  p_provider text default 'veripagos'::text,
  p_expires_at timestamptz default null
)
returns public.driver_subscription_payments
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_plan public.driver_subscription_plans%rowtype;
  v_existing public.driver_subscription_payments%rowtype;
  v_payment public.driver_subscription_payments%rowtype;
  v_zone_key text;
  v_provider text := coalesce(nullif(trim(p_provider),''),'veripagos');
begin
  select * into v_plan
  from public.driver_subscription_plans
  where id=p_plan_id and active=true;
  if not found then raise exception 'Plan no disponible'; end if;

  select z.zone_key into v_zone_key
  from public.driver_profiles dp
  join public.service_zones z on z.id=dp.zone_id
  where dp.id=p_driver_id;

  if v_zone_key is null then
    raise exception 'No se pudo determinar la zona del conductor';
  end if;
  if v_plan.zone_key<>v_zone_key then
    raise exception 'El plan no está disponible en tu zona actual';
  end if;

  select * into v_existing
  from public.driver_subscription_payments
  where driver_id=p_driver_id
    and plan_id=p_plan_id
    and provider=v_provider
    and status='pending'
    and (expires_at is null or expires_at>now())
  order by created_at desc
  limit 1;
  if found then return v_existing; end if;

  insert into public.driver_subscription_payments(
    driver_id,plan_id,amount,currency_code,provider,status,expires_at,zone_key
  )
  values(
    p_driver_id,v_plan.id,v_plan.amount,v_plan.currency_code,
    v_provider,'pending',
    coalesce(p_expires_at,now()+interval '30 minutes'),
    v_plan.zone_key
  )
  returning * into v_payment;

  return v_payment;
end;
$function$;

create or replace function public.service_finalize_driver_subscription_payment(
  p_payment_id bigint,
  p_provider_order_id text default null,
  p_provider_data jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_payment public.driver_subscription_payments%rowtype;
  v_plan public.driver_subscription_plans%rowtype;
  v_current public.driver_subscriptions%rowtype;
  v_now timestamptz:=now();
  v_base timestamptz;
  v_exp timestamptz;
  v_had_current boolean:=false;
  v_note text;
begin
  select * into v_payment
  from public.driver_subscription_payments
  where id=p_payment_id
  for update;

  if not found then raise exception 'Pago no encontrado'; end if;

  if v_payment.status='approved' then
    select * into v_current
    from public.driver_subscriptions
    where driver_id=v_payment.driver_id;
    return jsonb_build_object(
      'approved',true,
      'already_approved',true,
      'expires_at',v_current.expires_at
    );
  end if;

  if v_payment.status<>'pending' then
    raise exception 'El pago ya no está pendiente';
  end if;

  select * into v_plan
  from public.driver_subscription_plans
  where id=v_payment.plan_id;
  if not found then raise exception 'Plan no encontrado'; end if;

  select * into v_current
  from public.driver_subscriptions
  where driver_id=v_payment.driver_id
  for update;
  v_had_current:=found;

  v_base:=case
    when v_had_current
      and v_current.status='active'
      and v_current.expires_at>v_now
    then v_current.expires_at
    else v_now
  end;
  v_exp:=v_base+make_interval(days=>v_plan.days);

  update public.driver_subscription_payments
  set status='approved',
      paid_at=coalesce(paid_at,v_now),
      provider_order_id=coalesce(
        nullif(trim(p_provider_order_id),''),
        provider_order_id
      ),
      provider_data=coalesce(provider_data,'{}'::jsonb)
        || coalesce(p_provider_data,'{}'::jsonb),
      updated_at=v_now
  where id=v_payment.id;

  insert into public.driver_subscriptions(
    driver_id,plan_id,status,started_at,expires_at,last_payment_id,updated_at
  )
  values(
    v_payment.driver_id,v_plan.id,'active',v_now,v_exp,v_payment.id,v_now
  )
  on conflict(driver_id) do update set
    plan_id=excluded.plan_id,
    status='active',
    started_at=case
      when public.driver_subscriptions.status='active'
        and public.driver_subscriptions.expires_at>v_now
      then public.driver_subscriptions.started_at
      else v_now
    end,
    expires_at=v_exp,
    last_payment_id=v_payment.id,
    updated_at=v_now;

  v_note:=case
    when v_payment.provider='mercado_pago' then 'Mercado Pago'
    when v_payment.provider='veripagos' then 'VeriPagos'
    else coalesce(v_payment.provider,'Pago')
  end;

  insert into public.driver_subscription_history(
    driver_id,plan_id,payment_id,action,
    previous_expires_at,new_expires_at,amount,notes
  )
  values(
    v_payment.driver_id,v_plan.id,v_payment.id,'payment_approved',
    case when v_had_current then v_current.expires_at else null end,
    v_exp,v_payment.amount,v_note
  );

  return jsonb_build_object(
    'approved',true,
    'already_approved',false,
    'driver_id',v_payment.driver_id,
    'plan_id',v_plan.id,
    'plan_name',v_plan.name,
    'provider',v_payment.provider,
    'expires_at',v_exp
  );
end;
$function$;

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
  v_provider_configured boolean := false;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;

  select dp.zone_id into v_zone_id
  from public.driver_profiles dp where dp.id=v_uid;

  if v_zone_id is null then
    return jsonb_build_object(
      'zone',null,'enabled',false,'enforce_access',false,
      'provider',null,'provider_enabled',false,'provider_configured',false,
      'payment_provider_key',null,'payment_provider_label',null,
      'plans','[]'::jsonb
    );
  end if;

  select zone_key,name,currency_code
  into v_zone_key,v_zone_name,v_currency
  from public.service_zones where id=v_zone_id;

  select enabled,enforce_access
  into v_enabled,v_enforce
  from public.driver_subscription_zone_settings where zone_id=v_zone_id;

  select * into v_global
  from public.driver_subscription_settings where id=true;

  select m.provider_key,c.display_name
  into v_payment_provider_key,v_payment_provider_label
  from public.zone_payment_methods m
  join public.payment_method_catalog c on c.provider_key=m.provider_key
  where m.zone_id=v_zone_id
    and m.enabled=true
    and m.use_subscriptions=true
  order by m.is_primary desc,m.sort_order,c.display_name
  limit 1;

  if v_payment_provider_key='veripagos_qr' then
    v_provider := 'veripagos';
    v_provider_configured := coalesce(v_global.provider_enabled,false);
    v_provider_enabled := coalesce(v_global.provider_enabled,false);
  elsif v_payment_provider_key='mercado_pago' then
    v_provider := 'mercado_pago';
    select exists(
      select 1
      from private.zone_payment_provider_settings p
      where p.zone_id=v_zone_id
        and p.provider='mercado_pago'
        and nullif(trim(p.access_token),'') is not null
        and nullif(trim(p.public_key),'') is not null
        and nullif(p.extra_config->>'verified_at','') is not null
        and p.extra_config->>'site_id'='MLC'
    ) into v_provider_configured;
    v_provider_enabled := v_provider_configured;
  elsif v_payment_provider_key is not null then
    v_provider := v_payment_provider_key;
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(p) order by p.sort_order,p.id),
    '[]'::jsonb
  )
  into v_plans
  from public.driver_subscription_plans p
  where p.zone_key=v_zone_key and p.active=true;

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
    'provider_configured',coalesce(v_provider_configured,false),
    'payment_provider_key',v_payment_provider_key,
    'payment_provider_label',v_payment_provider_label,
    'qr_validity',coalesce(v_global.qr_validity,'0/00:15'),
    'plans',coalesce(v_plans,'[]'::jsonb)
  );
end;
$function$;

revoke execute on function public.driver_subscription_catalog_for_me()
  from public, anon;
grant execute on function public.driver_subscription_catalog_for_me()
  to authenticated;
