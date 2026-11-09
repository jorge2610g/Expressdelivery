-- Un QR de suscripción cancelado (o vencido) puede estar pagado en VeriPagos.
-- Antes, service_finalize_driver_subscription_payment solo activaba pagos en
-- estado 'pending', así que un pago confirmado por el banco después de la
-- cancelación quedaba sin plan.
-- Ahora acepta 'cancelled' y 'expired'. Estas funciones solo se llaman después
-- de que VeriPagos confirme el pago (estado completado), así que no activa pagos
-- no confirmados. 'rejected' sigue fuera. El resto de la lógica no cambia.

begin;

create or replace function public.service_finalize_driver_subscription_payment(p_payment_id bigint, p_provider_order_id text DEFAULT NULL::text, p_provider_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment public.driver_subscription_payments%rowtype;
  v_plan public.driver_subscription_plans%rowtype;
  v_zone public.service_zones%rowtype;
  v_current public.driver_zone_subscriptions%rowtype;
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

  select * into v_plan
  from public.driver_subscription_plans
  where id=v_payment.plan_id;
  if not found then raise exception 'Plan no encontrado'; end if;

  select * into v_zone
  from public.service_zones
  where zone_key=v_plan.zone_key
  limit 1;
  if not found then
    raise exception 'La zona del plan no existe';
  end if;

  if v_payment.status='approved' then
    select * into v_current
    from public.driver_zone_subscriptions
    where driver_id=v_payment.driver_id
      and zone_id=v_zone.id;

    return jsonb_build_object(
      'approved',true,
      'already_approved',true,
      'zone_key',v_zone.zone_key,
      'expires_at',v_current.expires_at
    );
  end if;

  if v_payment.status not in ('pending','cancelled','expired') then
    raise exception 'El pago ya no está pendiente';
  end if;

  select * into v_current
  from public.driver_zone_subscriptions
  where driver_id=v_payment.driver_id
    and zone_id=v_zone.id
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
        ||coalesce(p_provider_data,'{}'::jsonb),
      zone_key=v_plan.zone_key,
      updated_at=v_now
  where id=v_payment.id;

  insert into public.driver_zone_subscriptions(
    driver_id,zone_id,plan_id,status,
    started_at,expires_at,last_payment_id,updated_at
  )
  values(
    v_payment.driver_id,
    v_zone.id,
    v_plan.id,
    'active',
    case
      when v_had_current
        and v_current.status='active'
        and v_current.expires_at>v_now
      then v_current.started_at
      else v_now
    end,
    v_exp,
    v_payment.id,
    v_now
  )
  on conflict(driver_id,zone_id) do update set
    plan_id=excluded.plan_id,
    status='active',
    started_at=excluded.started_at,
    expires_at=excluded.expires_at,
    last_payment_id=excluded.last_payment_id,
    updated_at=v_now;

  -- Compatibility mirror only. The trigger above mirrors this back to the
  -- same zone, never deleting other zone rows.
  insert into public.driver_subscriptions(
    driver_id,plan_id,status,started_at,
    expires_at,last_payment_id,updated_at
  )
  values(
    v_payment.driver_id,
    v_plan.id,
    'active',
    case
      when v_had_current
        and v_current.status='active'
        and v_current.expires_at>v_now
      then v_current.started_at
      else v_now
    end,
    v_exp,
    v_payment.id,
    v_now
  )
  on conflict(driver_id) do update set
    plan_id=excluded.plan_id,
    status=excluded.status,
    started_at=excluded.started_at,
    expires_at=excluded.expires_at,
    last_payment_id=excluded.last_payment_id,
    updated_at=excluded.updated_at;

  v_note:=case
    when v_payment.provider='mercado_pago' then 'Mercado Pago'
    when v_payment.provider='veripagos' then 'VeriPagos'
    when v_payment.provider='wallet' then 'Billetera Express'
    else coalesce(v_payment.provider,'Pago')
  end;

  insert into public.driver_subscription_history(
    driver_id,plan_id,payment_id,action,
    previous_expires_at,new_expires_at,amount,
    notes,zone_key
  )
  values(
    v_payment.driver_id,
    v_plan.id,
    v_payment.id,
    'payment_approved',
    case when v_had_current then v_current.expires_at else null end,
    v_exp,
    v_payment.amount,
    v_note,
    v_plan.zone_key
  );

  return jsonb_build_object(
    'approved',true,
    'already_approved',false,
    'driver_id',v_payment.driver_id,
    'plan_id',v_plan.id,
    'plan_name',v_plan.name,
    'provider',v_payment.provider,
    'zone_id',v_zone.id,
    'zone_key',v_zone.zone_key,
    'expires_at',v_exp
  );
end;
$function$;

commit;
