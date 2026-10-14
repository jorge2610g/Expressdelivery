-- Migración: cobros_pendientes_cuentas_prueba_reales
-- Fecha: 2026-10-15
-- Reproduce el estado aplicado en producción bajo órdenes explícitas del propietario (chat del 14-15 oct 2026). Copias de seguridad: schemas backup.funciones_cobros_20261014, backup.funciones_pagos_20261015, backup.funciones_recargas_20261015, backup.funciones_lecturas_monedero_20261015.

-- Funciones: definiciones tal como están en producción (pg_get_functiondef), sin cambios.
-- Solo se añade el ';' final a cada sentencia.

CREATE OR REPLACE FUNCTION public.request_country_wallet_topup_v2(p_amount numeric, p_channel text DEFAULT 'production'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_context jsonb;
  v_id uuid;
  v_currency text;
  v_country text;
  v_channel text:='production';
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if p_amount is null or p_amount<1 or p_amount>5000000 then
    raise exception 'Monto inválido';
  end if;

  v_context:=public.current_operating_context();
  v_currency:=v_context->>'currency_code';
  v_country:=v_context->>'country_code';

  if v_currency is null or v_country is null then
    raise exception 'No se pudo determinar la moneda de tu país actual';
  end if;

  if exists(
    select 1
    from public.wallet_topup_requests
    where user_id=v_uid
      and status='pending'
  ) then
    raise exception 'Ya tienes una recarga pendiente. Cancélala antes de generar otra';
  end if;

  insert into public.wallet_topup_requests(
    user_id,amount,currency,country_code,channel
  )
  values(
    v_uid,round(p_amount,2),v_currency,v_country,v_channel
  )
  returning id into v_id;

  perform set_config('app.runtime_channel',v_channel,true);

  insert into public.notifications(
    user_id,title,body,type,metadata
  )
  select
    a.user_id,
    'Nueva recarga pendiente',
    coalesce(nullif(trim(u.full_name),''),'Usuario Express')||
      ' solicitó una recarga de '||
      v_currency||' '||
      trim(to_char(p_amount,'FM999999990.00')),
    'wallet_topup_pending',
    jsonb_build_object(
      'country_code',v_country,
      'currency',v_currency,
      'request_id',v_id,
      'channel',v_channel
    )
  from public.admin_users a
  left join public.users u on u.id=v_uid;

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_country_wallet_v2(p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_context jsonb;
  v_country text;
  v_currency text;
  v_channel text:='production';
  v_wallet public.wallet_country_accounts%rowtype;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;


  v_context:=public.current_operating_context();
  v_country:=v_context->>'country_code';
  v_currency:=upper(coalesce(v_context->>'currency_code',''));

  if nullif(v_country,'') is null or nullif(v_currency,'') is null then
    raise exception 'No se pudo determinar país y moneda de la zona actual';
  end if;

  insert into public.wallet_country_accounts(
    user_id,country_code,channel,currency,balance
  )
  values(v_uid,v_country,v_channel,v_currency,0)
  on conflict(user_id,country_code,channel) do update set
    currency=excluded.currency,
    updated_at=case
      when public.wallet_country_accounts.currency is distinct from excluded.currency
      then now()
      else public.wallet_country_accounts.updated_at
    end;

  select * into v_wallet
  from public.wallet_country_accounts
  where user_id=v_uid
    and country_code=v_country
    and channel=v_channel;

  return to_jsonb(v_wallet)||jsonb_build_object(
    'country',v_context->>'country',
    'zone_id',v_context->>'zone_id',
    'zone_key',v_context->>'zone_key',
    'zone_name',v_context->>'zone_name'
  );
end;
$function$;

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
$function$;

CREATE OR REPLACE FUNCTION public.service_finalize_verified_wallet_gateway(p_checkout_id uuid, p_provider_order_id text, p_verified_amount numeric, p_verified_currency text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item public.wallet_gateway_checkouts%rowtype;
  v_topup_id uuid;
begin
  if coalesce(auth.role(),'')<>'service_role' then
    raise exception 'Solo disponible para el servicio de pagos';
  end if;
  select * into v_item from public.wallet_gateway_checkouts
  where id=p_checkout_id for update;
  if not found then raise exception 'Operación no encontrada'; end if;
  if v_item.status='paid' then
    return jsonb_build_object('paid',true,'already_processed',true);
  end if;
  if v_item.status<>'pending' then
    raise exception 'Recarga no pendiente';
  end if;
  if v_item.provider_order_id is null
     or v_item.provider_order_id<>p_provider_order_id
     or v_item.amount<>round(p_verified_amount,2)
     or v_item.currency_code<>upper(trim(p_verified_currency)) then
    raise exception 'No coinciden referencia, monto o moneda verificados';
  end if;
  if v_item.channel<>'production' then
    raise exception 'Recarga fuera de Producción';
  end if;
  update public.wallet_gateway_checkouts
  set status='paid',paid_at=now() where id=v_item.id;

  insert into public.wallet_topup_requests(
    user_id,amount,currency,country_code,channel,method,
    provider_reference,status,resolved_at
  ) values(
    v_item.user_id,v_item.amount,v_item.currency_code,v_item.country_code,
    v_item.channel,v_item.provider,v_item.provider_order_id,'approved',now()
  ) returning id into v_topup_id;

  perform set_config('app.runtime_channel','production',true);
  insert into public.wallet_transactions(
    user_id,amount,type,status,reference,country_code,channel
  ) values(
    v_item.user_id,v_item.amount,'topup','completed',
    'Recarga pasarela:'||v_item.id::text,v_item.country_code,'production'
  );
  -- The wallet_transactions AFTER INSERT trigger updates the country wallet.
  -- The legacy wallet mirror is needed only in Production.
  perform public.mirror_legacy_wallet_delta(
    v_item.user_id,v_item.currency_code,v_item.amount
  );
  insert into public.notifications(user_id,title,body,type,metadata,channel)
  values(
    v_item.user_id,'Recarga confirmada',
    'Se acreditaron '||v_item.currency_code||' '||
       trim(to_char(v_item.amount,'FM999999990.00'))||' en tu billetera.',
    'wallet_topup',jsonb_build_object(
      'checkout_id',v_item.id,'provider',v_item.provider,
      'country_code',v_item.country_code,'channel','production'
    ),'production'
  );
  return jsonb_build_object(
    'paid',true,'already_processed',false,
    'topup_id',v_topup_id,'checkout_id',v_item.id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.driver_kyc_bolivia_state(p_country_code text DEFAULT 'BO'::text, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid:=auth.uid();
  v_channel text:='production';
  v_country text:=upper(trim(coalesce(p_country_code,'')));
  v_month date:=(date_trunc('month',now() at time zone 'America/La_Paz'))::date;
  v_settings public.driver_kyc_method_settings%rowtype;
  v_used integer;
  v_latest text;
  v_has_verified boolean:=false;
  v_manual_active boolean:=false;
  v_didit_enabled boolean:=false;
  v_method text;
begin
  if v_user is null then raise exception 'Autenticación requerida'; end if;
  if v_channel not in ('preview','production') then raise exception 'Canal inválido'; end if;
  if v_channel='preview' and not (public.is_admin() or public.is_active_audit_user(v_user))
    then raise exception 'Preview reservado a QA'; end if;
  if v_country <> 'BO' then
    return jsonb_build_object('configured',false,'country_code',v_country);
  end if;
  select * into v_settings from public.driver_kyc_method_settings
  where country_code=v_country and channel=v_channel;
  select coalesce(s.didit_enabled,false) into v_didit_enabled
  from public.identity_verification_country_settings s
  where s.country_code=v_country;
  select coalesce(q.used_count, (
      select count(*)::integer from public.identity_verifications i
      where i.provider='didit' and i.document_type='driver_identity'
        and i.country_code='BO'
        and i.provider_environment=case when v_channel='preview' then 'sandbox' else 'production' end
        and (i.created_at at time zone 'America/La_Paz')::date>=v_month
        and (i.created_at at time zone 'America/La_Paz')::date<(v_month+interval '1 month')::date
    )) into v_used
  from (select 1) base left join public.driver_kyc_didit_monthly_usage q
   on q.country_code=v_country and q.channel=v_channel and q.month_start=v_month;

  select status into v_latest from public.identity_verifications i
  where i.user_id=v_user and i.provider='didit'
    and i.subject_role='driver' and i.document_type='driver_identity'
    and i.country_code=v_country
    and i.provider_environment=case when v_channel='preview' then 'sandbox' else 'production' end
  order by i.created_at desc,i.id desc limit 1;
  v_has_verified:=v_latest='verified';
  select exists(
    select 1 from public.driver_documents d
    join public.driver_document_requirements r on r.id=d.requirement_id
    where d.driver_id=v_user and d.verification_method='manual'
      and d.status in('pending','verified','rejected')
      and lower(r.code) in ('identity_card','national_id','id_card',
        'identity','carnet','cedula','cédula')
  ) into v_manual_active;
  v_method:=case
    when v_manual_active then 'manual'
    when v_has_verified or v_latest in ('pending','processing','review') then 'didit'
    when coalesce(v_settings.preferred_method,'automatic')='manual' then 'manual'
    when not coalesce(v_didit_enabled,false) then 'manual'
    when v_used>=30 then 'manual'
    else 'didit'
  end;

  return jsonb_build_object(
    'configured',true,'country_code','BO','channel',v_channel,
    'preferred_method',coalesce(v_settings.preferred_method,'automatic'),
    'effective_method',v_method,
    'didit_enabled',coalesce(v_didit_enabled,false),
    'month_start',v_month,
    'used',v_used,'limit',30,'remaining',greatest(0,30-v_used),
    'previous_didit_status',v_latest,
    'manual_existing',v_manual_active
  );
end; $function$;

CREATE OR REPLACE FUNCTION public.driver_kyc_bolivia_reserve_didit(p_user_id uuid, p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid:=p_user_id;
  v_channel text:='production';
  v_month date:=(date_trunc('month',now() at time zone 'America/La_Paz'))::date;
  v_used integer;
  v_latest text;
  v_mode text;
  v_didit_enabled boolean;
  v_claim uuid;
begin
  -- Never let arbitrary authenticated clients exhaust everyone's free quota.
  if auth.role() <> 'service_role' then raise exception 'Solo servidor'; end if;
  if v_user is null then raise exception 'Usuario requerido'; end if;
  if v_channel not in('preview','production') then raise exception 'Canal inválido'; end if;
  perform pg_advisory_xact_lock(hashtext('express_kyc_BO_'||v_channel||v_month::text));

  select preferred_method into v_mode from public.driver_kyc_method_settings
    where country_code='BO' and channel=v_channel;
  select didit_enabled into v_didit_enabled
  from public.identity_verification_country_settings where country_code='BO';
  if coalesce(v_mode,'automatic')='manual' or not coalesce(v_didit_enabled,false) then
    return jsonb_build_object('ok',false,'code','manual_kyc_required');
  end if;

  select status into v_latest from public.identity_verifications i
  where i.user_id=v_user and i.provider='didit' and i.subject_role='driver'
    and i.document_type='driver_identity' and i.country_code='BO'
    and i.provider_environment=case when v_channel='preview'
      then 'sandbox' else 'production' end
  order by i.created_at desc,i.id desc limit 1;
  if v_latest='verified' then
    return jsonb_build_object('ok',false,'code','already_verified');
  end if;
  if exists(
    select 1 from public.driver_documents d
    join public.driver_document_requirements r on r.id=d.requirement_id
    where d.driver_id=v_user and d.verification_method='manual'
      and d.status in('pending','verified','rejected')
      and lower(r.code) in('identity_card','national_id','id_card',
        'identity','carnet','cedula','cédula')
  ) then
    return jsonb_build_object('ok',false,'code','manual_kyc_in_progress');
  end if;

  -- Reuse a fresh reservation for the same user to avoid double-charging
  -- rapid taps; other users still get at most the remaining global slots.
  select id into v_claim from public.driver_kyc_didit_claims c
  where c.user_id=v_user and c.country_code='BO' and c.channel=v_channel
    and c.month_start=v_month and c.status='reserved'
    and c.created_at>=now()-interval '3 minutes'
  order by created_at desc limit 1;
  if v_claim is not null then
    return jsonb_build_object('ok',true,'claim_id',v_claim,'reused',true);
  end if;

  select coalesce(q.used_count, (
    select count(*)::integer from public.identity_verifications i
    where i.provider='didit' and i.document_type='driver_identity'
      and i.country_code='BO'
      and i.provider_environment=case when v_channel='preview'
        then 'sandbox' else 'production' end
      and (i.created_at at time zone 'America/La_Paz')::date>=v_month
      and (i.created_at at time zone 'America/La_Paz')::date<(v_month+interval '1 month')::date
  )) into v_used from (select 1) b
    left join public.driver_kyc_didit_monthly_usage q
    on q.country_code='BO' and q.channel=v_channel and q.month_start=v_month;
  if v_used>=30 then
    return jsonb_build_object('ok',false,'code','quota_exhausted',
      'used',v_used,'limit',30,'method','manual');
  end if;
  insert into public.driver_kyc_didit_monthly_usage(
    country_code,channel,month_start,used_count
  ) values('BO',v_channel,v_month,v_used+1)
    on conflict(country_code,channel,month_start)
    do update set used_count=excluded.used_count,updated_at=now();
  insert into public.driver_kyc_didit_claims(user_id,country_code,channel,month_start)
    values(v_user,'BO',v_channel,v_month) returning id into v_claim;
  return jsonb_build_object('ok',true,'claim_id',v_claim,'reused',false,
    'used',v_used+1,'limit',30);
end; $function$;

CREATE OR REPLACE FUNCTION public.my_country_wallet_topups_v2(p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';

  return (
    select coalesce(
      jsonb_agg(to_jsonb(r) order by r.created_at desc),
      '[]'::jsonb
    )
    from public.wallet_topup_requests r
    where r.user_id=v_uid
      and r.country_code=v_country
      and r.channel='production'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.my_country_wallet_transactions_v2(p_channel text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';

  return (
    select coalesce(
      jsonb_agg(to_jsonb(wt) order by wt.created_at desc),
      '[]'::jsonb
    )
    from public.wallet_transactions wt
    where wt.user_id=v_uid
      and wt.country_code=v_country
      and wt.channel='production'
  );
end;
$function$;

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

  -- Un conductor solo puede tener un pago pendiente vigente a la vez (cualquier plan o proveedor).
  select * into v_existing
  from public.driver_subscription_payments
  where driver_id=p_driver_id
    and status='pending'
    and (expires_at is null or expires_at>now())
  order by created_at desc
  limit 1;
  if found then
    if v_existing.plan_id=p_plan_id and v_existing.provider=v_provider then
      return v_existing;
    end if;
    raise exception 'Tienes un pago pendiente. Cancélalo antes de generar otro.';
  end if;

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

CREATE OR REPLACE FUNCTION public.service_expire_pending_driver_subscription_payments()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count integer;
begin
  update public.driver_subscription_payments
  set status='expired', updated_at=now()
  where status='pending' and expires_at is not null and expires_at<=now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.driver_cancel_my_pending_subscription_payment(p_payment_id bigint)
 RETURNS driver_subscription_payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_payment public.driver_subscription_payments%rowtype;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  update public.driver_subscription_payments
  set status='cancelled', cancelled_at=now(), updated_at=now()
  where id=p_payment_id and driver_id=v_uid and status='pending'
  returning * into v_payment;
  if v_payment.id is null then
    raise exception 'No hay un pago pendiente tuyo con ese número';
  end if;
  return v_payment;
end;
$function$;

CREATE OR REPLACE FUNCTION public.driver_cancel_my_pending_topup(p_request_id uuid)
 RETURNS wallet_topup_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_row public.wallet_topup_requests%rowtype;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  update public.wallet_topup_requests
  set status='cancelled', resolved_at=now()
  where id=p_request_id and user_id=v_uid and status='pending'
  returning * into v_row;
  if v_row.id is null then
    raise exception 'No hay una recarga pendiente tuya con ese número';
  end if;
  return v_row;
end;
$function$;

-- Permisos.
-- Estado verificado por SELECT en producción antes de escribir este archivo:
--   wallet_demo_topup(numeric): postgres, service_role (sin PUBLIC, anon ni authenticated).
--   driver_cancel_my_pending_subscription_payment(bigint) y driver_cancel_my_pending_topup(uuid):
--   authenticated, postgres, service_role (sin PUBLIC ni anon).

REVOKE ALL ON FUNCTION public.wallet_demo_topup(numeric) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.driver_cancel_my_pending_subscription_payment(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_cancel_my_pending_subscription_payment(bigint) TO authenticated;

REVOKE ALL ON FUNCTION public.driver_cancel_my_pending_topup(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_cancel_my_pending_topup(uuid) TO authenticated;

-- Programador de caducidad de suscripciones pendientes (pg_cron, cada 5 minutos).
-- Se desprograma solo si el job ya existe y después se vuelve a programar.
DO $$
BEGIN
  IF (select count(*) from cron.job where jobname='driver-subscription-pending-expiry') > 0 THEN
    PERFORM cron.unschedule('driver-subscription-pending-expiry');
  END IF;
END
$$;

select cron.schedule('driver-subscription-pending-expiry', '*/5 * * * *', 'select public.service_expire_pending_driver_subscription_payments()');
