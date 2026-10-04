-- Fix financial writers after adding Preview/Production wallet channels.

create or replace function public.ensure_country_wallet()
returns jsonb
language sql
security definer
set search_path=public
as $$
  select public.ensure_country_wallet_v2('production')
$$;

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
begin
  select coalesce(s.commission_percent,0)
  into v_commission_percent
  from public.app_settings s
  limit 1;

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

  if new.method='cash' and new.status='paid' then
    if v_commission>0 then
      insert into public.wallet_transactions(
        user_id,amount,type,status,reference,
        trip_id,delivery_id,country_code,channel
      )
      values(
        new.payee_id,-v_commission,'commission','completed',
        'Comisión Express por servicio en efectivo',
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
        new.payer_id,
        'Saldo insuficiente',
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

create or replace function public.admin_resolve_wallet_topup(
  p_request_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_req public.wallet_topup_requests%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_status not in ('approved','rejected') then raise exception 'Estado inválido'; end if;

  select * into v_req
  from public.wallet_topup_requests
  where id=p_request_id
  for update;

  if not found then raise exception 'Solicitud no encontrada'; end if;
  if v_req.status<>'pending' then raise exception 'La solicitud ya fue resuelta'; end if;

  update public.wallet_topup_requests
  set status=p_status,resolved_at=now(),resolved_by=auth.uid()
  where id=p_request_id;

  perform set_config(
    'app.runtime_channel',
    public.normalize_runtime_channel(v_req.channel),
    true
  );

  if p_status='approved' then
    insert into public.wallet_transactions(
      user_id,amount,type,status,reference,country_code,channel
    )
    values(
      v_req.user_id,v_req.amount,'topup','completed',
      'Recarga aprobada',v_req.country_code,v_req.channel
    );

    if v_req.channel='production' then
      perform public.mirror_legacy_wallet_delta(
        v_req.user_id,v_req.currency,v_req.amount
      );
    end if;

    insert into public.notifications(user_id,title,body,type,metadata)
    values(
      v_req.user_id,'Recarga aprobada',
      'Se acreditaron '||v_req.currency||' '||
        trim(to_char(v_req.amount,'FM999999990.00'))||
        ' a tu billetera.',
      'wallet_topup',
      jsonb_build_object(
        'country_code',v_req.country_code,
        'currency',v_req.currency,
        'channel',v_req.channel
      )
    );
  else
    insert into public.notifications(user_id,title,body,type,metadata)
    values(
      v_req.user_id,'Recarga rechazada',
      'Tu solicitud de recarga no fue aprobada. Contacta a soporte si necesitas ayuda.',
      'wallet_topup',
      jsonb_build_object(
        'country_code',v_req.country_code,
        'currency',v_req.currency,
        'channel',v_req.channel
      )
    );
  end if;
end;
$$;

create or replace function public.pay_driver_subscription_with_country_wallet(
  p_plan_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
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
  if public.is_active_audit_user(v_uid) then
    raise exception 'Las suscripciones de Preview no pueden usar la billetera de Producción';
  end if;

  if not exists(select 1 from public.driver_profiles d where d.id=v_uid) then
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
$$;
