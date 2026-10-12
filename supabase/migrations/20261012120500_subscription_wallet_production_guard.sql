-- Isolation guard for wallet-funded subscriptions; no balances or subscriptions are modified by applying this migration.
CREATE OR REPLACE FUNCTION public.pay_driver_subscription_with_country_wallet(p_plan_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_plan public.driver_subscription_plans%rowtype;
  v_zone public.service_zones%rowtype;
  v_zone_settings public.driver_subscription_zone_settings%rowtype;
  v_wallet public.wallet_country_accounts%rowtype;
  v_payment public.driver_subscription_payments%rowtype;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Sesión requerida';
  end if;
  if public.is_active_audit_user(v_uid)
     or not public.is_production_runtime_user(v_uid) then
    raise exception 'La billetera de Producción no está disponible para cuentas Preview';
  end if;

  if not exists(
    select 1 from public.driver_profiles d where d.id=v_uid
  ) then
    raise exception 'Perfil de conductor requerido';
  end if;

  select z.* into v_zone
  from public.driver_profiles d
  join public.service_zones z on z.id=d.zone_id
  where d.id=v_uid and z.active=true;

  if not found then raise exception 'No se pudo determinar la zona del conductor'; end if;

  select p.* into v_plan
  from public.driver_subscription_plans p
  where p.id=p_plan_id and p.active=true and p.zone_key=v_zone.zone_key;

  if not found then raise exception 'Plan no disponible en tu zona actual'; end if;

  select * into v_zone_settings
  from public.driver_subscription_zone_settings
  where zone_id=v_zone.id;

  if not found or not coalesce(v_zone_settings.enabled,false) then
    raise exception 'Las suscripciones no están habilitadas en esta zona';
  end if;

  perform public.ensure_country_wallet_v2('production');

  select * into v_wallet
  from public.wallet_country_accounts
  where user_id=v_uid
    and country_code=v_zone.country_code
    and channel='production'
  for update;

  if upper(coalesce(v_wallet.currency,''))<>upper(coalesce(v_plan.currency_code,'')) then
    raise exception 'La billetera del país está en % y este plan se cobra en %.',
      v_wallet.currency,v_plan.currency_code;
  end if;
  if coalesce(v_wallet.balance,0)<v_plan.amount then
    raise exception 'Saldo insuficiente en la billetera';
  end if;

  insert into public.driver_subscription_payments(
    driver_id,plan_id,amount,currency_code,
    provider,status,provider_data,paid_at,expires_at,zone_key
  )
  values(
    v_uid,v_plan.id,v_plan.amount,v_plan.currency_code,
    'wallet','pending',
    jsonb_build_object(
      'source','country_wallet','country_code',v_zone.country_code,
      'channel','production','balance_before',v_wallet.balance
    ),
    now(),now()+interval '15 minutes',v_plan.zone_key
  )
  returning * into v_payment;

  insert into public.wallet_transactions(
    user_id,amount,type,status,reference,country_code,channel,created_at
  )
  values(
    v_uid,-v_plan.amount,'payment','completed',
    'driver_subscription:'||v_payment.id::text,
    v_zone.country_code,'production',now()
  );

  perform public.mirror_legacy_wallet_delta(
    v_uid,v_plan.currency_code,-v_plan.amount
  );

  v_result:=public.service_finalize_driver_subscription_payment(
    v_payment.id,
    'country-wallet-'||v_payment.id::text,
    jsonb_build_object(
      'source','country_wallet','country_code',v_zone.country_code,
      'channel','production','balance_before',v_wallet.balance,
      'balance_after',v_wallet.balance-v_plan.amount
    )
  );

  return v_result||jsonb_build_object(
    'provider','wallet','payment_id',v_payment.id,
    'country_code',v_zone.country_code,'channel','production',
    'balance_before',v_wallet.balance,
    'balance_after',v_wallet.balance-v_plan.amount,
    'currency_code',v_plan.currency_code
  );
end;
$function$
;
