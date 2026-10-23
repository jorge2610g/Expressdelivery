-- Charge the commission configured by the effective zone/service fare rule.
-- Preview reads its account-scoped shadow configuration and never falls through to Production.

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

  if v_channel='preview' then
    -- Preview tariffs and settings live in the account-scoped shadow store;
    -- never read Production fare rules for a Preview payment.
    if v_zone_id is not null and v_service_key is not null then
      select c.payload into v_fare_rule
      from public.admin_environment_config c
      where c.environment='preview'
        and c.module='fare_rules'
        and coalesce(c.payload->>'_deleted','false')<>'true'
        and coalesce(c.payload->>'active','true')='true'
        and (
          (c.payload->>'scope_type'='zone_service'
            and c.payload->>'zone_id'=v_zone_id::text
            and c.payload->>'service_key'=v_service_key)
          or (c.payload->>'scope_type'='service'
            and c.payload->>'service_key'=v_service_key)
          or c.payload->>'scope_type'='global'
        )
      order by case c.payload->>'scope_type'
        when 'zone_service' then 3
        when 'service' then 2
        else 1 end desc
      limit 1;
    end if;

    if v_fare_rule is not null then
      if coalesce(v_fare_rule->>'commission_percent','') ~ '^-?[0-9]+([.][0-9]+)?$' then
        v_commission_percent:=
          least(greatest((v_fare_rule->>'commission_percent')::numeric,0),100);
      end if;
    else
      select c.payload into v_settings
      from public.admin_environment_config c
      where c.environment='preview'
        and c.module='app_settings'
        and coalesce(c.payload->>'_deleted','false')<>'true'
      order by case when c.payload->>'id'='true' then 0 else 1 end,
               c.updated_at desc
      limit 1;
      if coalesce(v_settings->>'commission_percent','') ~ '^-?[0-9]+([.][0-9]+)?$' then
        v_commission_percent:=
          least(greatest((v_settings->>'commission_percent')::numeric,0),100);
      end if;
    end if;
  else
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

