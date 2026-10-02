-- Multizone subscription safeguards and plan lifecycle.
CREATE OR REPLACE FUNCTION public.admin_set_driver_subscription(p_driver_id uuid, p_plan_id bigint, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_notes text DEFAULT NULL::text)
 RETURNS driver_subscriptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_plan public.driver_subscription_plans%rowtype;
  v_current public.driver_subscriptions%rowtype;
  v_result public.driver_subscriptions%rowtype;
  v_driver_zone_key text;
  v_now timestamptz:=now();
  v_exp timestamptz;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select * into v_plan
  from public.driver_subscription_plans
  where id=p_plan_id and active=true;
  if not found then raise exception 'Plan no encontrado'; end if;

  select z.zone_key into v_driver_zone_key
  from public.driver_profiles dp
  left join public.service_zones z on z.id=dp.zone_id
  where dp.id=p_driver_id;

  if v_driver_zone_key is not null and v_plan.zone_key<>v_driver_zone_key then
    raise exception 'El plan no pertenece a la zona actual del conductor';
  end if;

  select * into v_current
  from public.driver_subscriptions where driver_id=p_driver_id;

  v_exp:=coalesce(p_expires_at,v_now+make_interval(days=>v_plan.days));

  insert into public.driver_subscriptions(
    driver_id,plan_id,status,started_at,expires_at,updated_at
  )
  values(p_driver_id,v_plan.id,'active',v_now,v_exp,v_now)
  on conflict(driver_id) do update set
    plan_id=excluded.plan_id,
    status='active',
    started_at=v_now,
    expires_at=v_exp,
    updated_at=v_now
  returning * into v_result;

  insert into public.driver_subscription_history(
    driver_id,plan_id,action,previous_expires_at,new_expires_at,notes,created_by
  )
  values(
    p_driver_id,v_plan.id,'admin_set',v_current.expires_at,v_exp,p_notes,auth.uid()
  );

  return v_result;
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_set_driver_subscription_provider_settings(p_provider_enabled boolean, p_qr_validity text DEFAULT '0/00:15'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.driver_subscription_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  update public.driver_subscription_settings
  set provider_enabled=coalesce(p_provider_enabled,false),
      qr_validity=coalesce(nullif(trim(p_qr_validity),''),'0/00:15'),
      updated_at=now(),
      updated_by=auth.uid()
  where id=true
  returning * into v_row;

  return jsonb_build_object(
    'provider',v_row.provider,
    'provider_enabled',v_row.provider_enabled,
    'qr_validity',v_row.qr_validity
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_upsert_driver_subscription_plan(p_id bigint, p_zone_key text, p_code text, p_name text, p_amount numeric, p_days integer, p_benefits jsonb, p_active boolean, p_sort_order integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id bigint;
  v_zone public.service_zones%rowtype;
  v_code text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select * into v_zone
  from public.service_zones
  where zone_key=lower(trim(p_zone_key))
  limit 1;
  if not found then raise exception 'Zona no encontrada'; end if;

  v_code := lower(trim(coalesce(p_code,'')));
  if v_code !~ '^[a-z][a-z0-9_]{1,39}$' then
    raise exception 'Código de plan inválido';
  end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Nombre requerido'; end if;
  if coalesce(p_amount,-1)<0 then raise exception 'Precio inválido'; end if;
  if coalesce(p_days,0)<1 then raise exception 'Duración inválida'; end if;
  if jsonb_typeof(coalesce(p_benefits,'[]'::jsonb))<>'array' then
    raise exception 'Beneficios inválidos';
  end if;

  if p_id is null then
    insert into public.driver_subscription_plans(
      code,name,amount,days,currency_code,benefits,active,sort_order,zone_key,updated_at
    )
    values(
      v_code,trim(p_name),p_amount,p_days,v_zone.currency_code,
      coalesce(p_benefits,'[]'::jsonb),coalesce(p_active,true),
      coalesce(p_sort_order,100),v_zone.zone_key,now()
    )
    returning id into v_id;
  else
    update public.driver_subscription_plans
    set code=v_code,
        name=trim(p_name),
        amount=p_amount,
        days=p_days,
        currency_code=v_zone.currency_code,
        benefits=coalesce(p_benefits,'[]'::jsonb),
        active=coalesce(p_active,true),
        sort_order=coalesce(p_sort_order,100),
        updated_at=now()
    where id=p_id and zone_key=v_zone.zone_key
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Plan no encontrado en esta zona'; end if;
  return v_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.my_driver_subscription_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_zone_id uuid;
  v_zone_key text;
  v_zone_name text;
  v_zone_enabled boolean := false;
  v_zone_enforce boolean := false;
  v_global public.driver_subscription_settings%rowtype;
  v_sub public.driver_subscriptions%rowtype;
  v_plan public.driver_subscription_plans%rowtype;
  v_usable boolean := false;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;

  select dp.zone_id,z.zone_key,z.name
  into v_zone_id,v_zone_key,v_zone_name
  from public.driver_profiles dp
  left join public.service_zones z on z.id=dp.zone_id
  where dp.id=v_uid;

  select * into v_global
  from public.driver_subscription_settings where id=true;

  if v_zone_id is not null then
    select enabled,enforce_access
    into v_zone_enabled,v_zone_enforce
    from public.driver_subscription_zone_settings
    where zone_id=v_zone_id;
  end if;

  select * into v_sub
  from public.driver_subscriptions where driver_id=v_uid;

  if v_sub.plan_id is not null then
    select * into v_plan
    from public.driver_subscription_plans where id=v_sub.plan_id;
  end if;

  v_usable := coalesce(
    v_sub.status='active'
    and v_sub.expires_at>now()
    and (v_zone_key is null or v_plan.zone_key=v_zone_key),
    false
  );

  return jsonb_build_object(
    'feature_enabled',coalesce(v_zone_enabled,false),
    'enforce_access',coalesce(v_zone_enforce,false),
    'provider',coalesce(v_global.provider,'veripagos'),
    'provider_enabled',coalesce(v_global.provider_enabled,false),
    'qr_validity',coalesce(v_global.qr_validity,'0/00:15'),
    'zone_id',v_zone_id,
    'zone_key',v_zone_key,
    'zone_name',v_zone_name,
    'usable',v_usable,
    'status',case when v_usable then 'active' else coalesce(v_sub.status,'inactive') end,
    'plan_id',v_sub.plan_id,
    'plan_name',v_plan.name,
    'plan_code',v_plan.code,
    'plan_zone_key',v_plan.zone_key,
    'started_at',v_sub.started_at,
    'expires_at',v_sub.expires_at,
    'remaining_seconds',case
      when v_sub.expires_at is null then 0
      else greatest(0,extract(epoch from(v_sub.expires_at-now()))::bigint)
    end
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.seed_zone_subscription_plans()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.driver_subscription_plans(
    code,name,amount,days,currency_code,benefits,active,sort_order,zone_key
  )
  select
    p.code,p.name,p.amount,p.days,new.currency_code,p.benefits,p.active,p.sort_order,new.zone_key
  from public.driver_subscription_plans p
  where p.zone_key='trinidad'
  on conflict(zone_key,code) do nothing;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.service_create_driver_subscription_payment(p_driver_id uuid, p_plan_id bigint, p_provider text DEFAULT 'veripagos'::text, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS driver_subscription_payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_plan public.driver_subscription_plans%rowtype;
  v_existing public.driver_subscription_payments%rowtype;
  v_payment public.driver_subscription_payments%rowtype;
  v_zone_key text;
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
    coalesce(nullif(trim(p_provider),''),'veripagos'),
    'pending',
    coalesce(p_expires_at,now()+interval '15 minutes'),
    v_plan.zone_key
  )
  returning * into v_payment;

  return v_payment;
end;
$function$


drop trigger if exists trg_seed_zone_subscription_plans
  on public.service_zones;
create trigger trg_seed_zone_subscription_plans
after insert on public.service_zones
for each row execute function public.seed_zone_subscription_plans();

grant execute on function public.admin_set_driver_subscription_provider_settings(boolean,text)
  to authenticated;
grant execute on function public.admin_upsert_driver_subscription_plan(bigint,text,text,text,numeric,integer,jsonb,boolean,integer)
  to authenticated;
