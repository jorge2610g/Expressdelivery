-- Ride payments by zone/channel + verified E.164 phones.
-- Keeps Preview payment configuration isolated from Production.

alter table public.users
  add column if not exists phone_country_code text,
  add column if not exists phone_verified_at timestamptz,
  add column if not exists preferred_payment_method text not null default 'cash';

alter table public.driver_profiles
  add column if not exists accepted_payment_methods text[] not null
    default array['cash','driver_qr']::text[];

insert into public.payment_method_catalog(
  provider_key, display_name, provider_type, active, credential_scope,
  supports_rides, supports_delivery, supports_subscriptions, supports_wallet
)
values (
  'driver_qr', 'QR del conductor', 'transfer', true, 'none',
  true, false, false, false
)
on conflict (provider_key) do update
set display_name=excluded.display_name,
    provider_type=excluded.provider_type,
    active=excluded.active,
    credential_scope=excluded.credential_scope,
    supports_rides=excluded.supports_rides,
    supports_delivery=excluded.supports_delivery,
    supports_subscriptions=excluded.supports_subscriptions,
    supports_wallet=excluded.supports_wallet,
    updated_at=now();

-- Platform gateways are not ride/delivery collectors. They remain available
-- for subscriptions and wallet top-ups only.
update public.payment_method_catalog
set supports_rides=false,
    supports_delivery=false,
    supports_subscriptions=true,
    supports_wallet=true,
    updated_at=now()
where provider_key in ('mercado_pago','veripagos_qr');

-- Chile rides: cash only.
update public.zone_payment_methods m
set use_rides=false,
    use_delivery=false,
    updated_at=now()
from public.service_zones z
where z.id=m.zone_id
  and lower(z.country)='chile'
  and m.provider_key='mercado_pago';

insert into public.zone_payment_methods(
  zone_id,provider_key,enabled,use_rides,use_delivery,use_subscriptions,
  use_wallet,is_primary,sort_order,public_config
)
select z.id,'cash',true,true,true,false,false,false,10,'{}'::jsonb
from public.service_zones z
where lower(z.country)='chile'
on conflict(zone_id,provider_key) do update
set enabled=true,use_rides=true,use_subscriptions=false,use_wallet=false,
    sort_order=least(public.zone_payment_methods.sort_order,10),updated_at=now();

-- Bolivia rides: cash + a direct QR belonging to the driver.
update public.zone_payment_methods m
set use_rides=false,
    use_delivery=false,
    updated_at=now()
from public.service_zones z
where z.id=m.zone_id
  and lower(z.country)='bolivia'
  and m.provider_key='veripagos_qr';

insert into public.zone_payment_methods(
  zone_id,provider_key,enabled,use_rides,use_delivery,use_subscriptions,
  use_wallet,is_primary,sort_order,public_config
)
select z.id,'driver_qr',true,true,false,false,false,false,20,
       jsonb_build_object(
         'collector','driver',
         'off_platform',true,
         'label','QR del conductor'
       )
from public.service_zones z
where lower(z.country)='bolivia'
on conflict(zone_id,provider_key) do update
set enabled=true,use_rides=true,use_delivery=false,use_subscriptions=false,
    use_wallet=false,is_primary=false,sort_order=20,
    public_config=excluded.public_config,updated_at=now();

insert into public.zone_payment_methods(
  zone_id,provider_key,enabled,use_rides,use_delivery,use_subscriptions,
  use_wallet,is_primary,sort_order,public_config
)
select z.id,'cash',true,true,true,false,false,false,10,'{}'::jsonb
from public.service_zones z
where lower(z.country)='bolivia'
on conflict(zone_id,provider_key) do update
set enabled=true,use_rides=true,use_subscriptions=false,use_wallet=false,
    sort_order=least(public.zone_payment_methods.sort_order,10),updated_at=now();

-- Keep Preview's shadow configuration aligned without reading Production rows.
update public.admin_environment_config c
set payload=jsonb_set(
      jsonb_set(c.payload,'{use_rides}','false'::jsonb,true),
      '{use_delivery}','false'::jsonb,true
    ),
    updated_at=now()
where c.environment='preview'
  and c.module='zone_payment_methods'
  and c.payload->>'provider_key' in ('mercado_pago','veripagos_qr');

insert into public.admin_environment_config(
  environment,module,record_key,payload,updated_at
)
select
  'preview',
  'zone_payment_methods',
  'driver_qr:'||(z.payload->>'id'),
  jsonb_build_object(
    'id','driver_qr:'||(z.payload->>'id'),
    'zone_id',z.payload->>'id',
    'provider_key','driver_qr',
    'enabled',true,
    'use_rides',true,
    'use_delivery',false,
    'use_subscriptions',false,
    'use_wallet',false,
    'is_primary',false,
    'sort_order',20,
    'public_config',jsonb_build_object(
      'collector','driver','off_platform',true,'label','QR del conductor'
    )
  ),
  now()
from public.admin_environment_config z
where z.environment='preview'
  and z.module='service_zones'
  and lower(z.payload->>'country')='bolivia'
  and coalesce((z.payload->>'_deleted')::boolean,false)=false
on conflict(environment,module,record_key) do update
set payload=excluded.payload,updated_at=now();

-- Authoritative ride methods for one zone and one runtime channel.
create or replace function public.zone_ride_payment_methods(
  p_zone_id uuid,
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_result jsonb;
begin
  if p_zone_id is null then return '[]'::jsonb; end if;

  if v_channel='preview' then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'provider_key',x.provider_key,
          'display_name',x.display_name,
          'provider_type',x.provider_type,
          'sort_order',x.sort_order,
          'public_config',x.public_config
        )
        order by x.sort_order,x.display_name
      ),
      '[]'::jsonb
    )
    into v_result
    from (
      select
        c.payload->>'provider_key' as provider_key,
        coalesce(cat.display_name,c.payload->>'provider_key') as display_name,
        coalesce(cat.provider_type,'other') as provider_type,
        coalesce((c.payload->>'sort_order')::integer,100) as sort_order,
        coalesce(c.payload->'public_config','{}'::jsonb) as public_config
      from public.admin_environment_config c
      left join public.payment_method_catalog cat
        on cat.provider_key=c.payload->>'provider_key'
      where c.environment='preview'
        and c.module='zone_payment_methods'
        and c.payload->>'zone_id'=p_zone_id::text
        and coalesce((c.payload->>'_deleted')::boolean,false)=false
        and coalesce((c.payload->>'enabled')::boolean,true)=true
        and coalesce((c.payload->>'use_rides')::boolean,false)=true
        and coalesce(cat.active,true)=true
    ) x;
  else
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'provider_key',m.provider_key,
          'display_name',c.display_name,
          'provider_type',c.provider_type,
          'sort_order',m.sort_order,
          'public_config',m.public_config
        )
        order by m.sort_order,c.display_name
      ),
      '[]'::jsonb
    )
    into v_result
    from public.zone_payment_methods m
    join public.payment_method_catalog c on c.provider_key=m.provider_key
    where m.zone_id=p_zone_id
      and m.enabled=true
      and m.use_rides=true
      and c.active=true;
  end if;

  return coalesce(v_result,'[]'::jsonb);
end;
$$;

create or replace function public.app_zone_context_v3(
  p_lat numeric,
  p_lng numeric,
  p_for text default 'passenger',
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_base jsonb;
  v_zone_id uuid;
  v_methods jsonb:='[]'::jsonb;
  v_first jsonb;
begin
  v_base:=public.app_zone_context_v2(p_lat,p_lng,p_for,p_channel);
  if coalesce((v_base->>'inside_coverage')::boolean,false)=false then
    return v_base||jsonb_build_object('payment_methods','[]'::jsonb);
  end if;

  v_zone_id:=nullif(v_base->'zone'->>'id','')::uuid;
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
$$;

create or replace function public.my_ride_payment_methods(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_zone_id uuid;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select coalesce(u.last_zone_id,d.zone_id)
  into v_zone_id
  from public.users u
  left join public.driver_profiles d on d.id=u.id
  where u.id=v_uid;

  return public.zone_ride_payment_methods(v_zone_id,p_channel);
end;
$$;

revoke all on function public.app_zone_context_v3(numeric,numeric,text,text) from public,anon;
grant execute on function public.app_zone_context_v3(numeric,numeric,text,text) to authenticated;
revoke all on function public.my_ride_payment_methods(text) from public,anon;
grant execute on function public.my_ride_payment_methods(text) to authenticated;

-- Accept driver_qr at schema level.
alter table public.ride_requests
  drop constraint if exists ride_requests_payment_method_check;
alter table public.ride_requests
  add constraint ride_requests_payment_method_check
  check(payment_method=any(array[
    'cash'::text,'driver_qr'::text,'pagorut'::text,'mercado_pago'::text,
    'santander'::text,'mach'::text,'tenpo'::text,'card'::text,'wallet'::text
  ]));

alter table public.payment_transactions
  drop constraint if exists payment_transactions_method_check;
alter table public.payment_transactions
  add constraint payment_transactions_method_check
  check(method=any(array[
    'cash'::text,'driver_qr'::text,'pagorut'::text,'mercado_pago'::text,
    'santander'::text,'mach'::text,'tenpo'::text,'card'::text,'wallet'::text
  ]));

-- Enforce the same admin rule on the backend, not only in Flutter.
create or replace function public.validate_ride_payment_method()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_zone_id uuid:=new.zone_id;
  v_methods jsonb;
begin
  if v_zone_id is null
     and new.pickup_latitude is not null
     and new.pickup_longitude is not null then
    v_zone_id:=public.service_zone_id_for_point(
      new.pickup_latitude,new.pickup_longitude
    );
    new.zone_id:=v_zone_id;
  end if;

  if v_zone_id is null then return new; end if;
  v_methods:=public.zone_ride_payment_methods(v_zone_id,new.channel);

  if not exists(
    select 1
    from jsonb_array_elements(v_methods) m
    where m->>'provider_key'=new.payment_method
  ) then
    raise exception 'El método de pago seleccionado no está habilitado para viajes en esta zona';
  end if;
  return new;
end;
$$;

drop trigger if exists ride_requests_validate_payment_method on public.ride_requests;
create trigger ride_requests_validate_payment_method
before insert or update of payment_method,zone_id,pickup_latitude,pickup_longitude,channel
on public.ride_requests
for each row execute function public.validate_ride_payment_method();

-- QR del conductor is direct/off-platform exactly like cash for settlement.
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

-- Preserve the existing trip state machine while marking direct driver QR paid.
create or replace function public.advance_trip(p_trip_id uuid,p_status text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_current text;
  v_driver uuid;
  v_passenger uuid;
  v_fare numeric;
  v_payment_method text;
  v_currency text;
  v_title text;
  v_body text;
  v_direct boolean;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;

  select t.status,t.driver_id,t.passenger_id,t.final_fare,
         r.payment_method,r.currency
  into v_current,v_driver,v_passenger,v_fare,v_payment_method,v_currency
  from public.trips t
  join public.ride_requests r on r.id=t.ride_request_id
  where t.id=p_trip_id
  for update of t;

  if v_driver is distinct from auth.uid() then raise exception 'No autorizado'; end if;
  if not (
    (v_current='driver_assigned' and p_status in ('driver_arriving','driver_waiting')) or
    (v_current='driver_arriving' and p_status='driver_waiting') or
    (v_current='in_progress' and p_status='completed') or
    (p_status='emergency' and v_current<>'completed')
  ) then
    if v_current='driver_waiting' and p_status='in_progress' then
      raise exception 'Debes validar el PIN de abordaje';
    end if;
    raise exception 'Transición de viaje inválida';
  end if;

  v_direct:=v_payment_method in ('cash','driver_qr');

  update public.trips
  set status=p_status,
      completed_at=case when p_status='completed' then now() else completed_at end,
      payment_status=case
        when p_status='completed' and v_direct then 'paid'
        else payment_status end
  where id=p_trip_id;

  insert into public.trip_status_history(trip_id,status,changed_by)
  values(p_trip_id,p_status,auth.uid());

  v_title:=case p_status
    when 'driver_arriving' then 'Tu conductor va en camino'
    when 'driver_waiting' then 'Tu conductor llegó · 5 minutos'
    when 'completed' then 'Llegaste a destino'
    when 'emergency' then 'Alerta de emergencia'
    else 'Actualización de viaje' end;
  v_body:=case p_status
    when 'driver_arriving' then 'Ya va hacia el punto de recogida. Sigue su llegada en el mapa.'
    when 'driver_waiting' then 'Ya está en el punto de recogida. Tienes 5 minutos para bajar y abordar. Abre Express y toca “Ya voy”.'
    when 'completed' then 'Tu viaje finalizó correctamente. Ya puedes calificar al conductor.'
    when 'emergency' then 'El viaje cambió a estado de emergencia.'
    else 'El estado de tu viaje cambió.' end;

  insert into public.notifications(user_id,title,body,type)
  values(v_passenger,v_title,v_body,'trip_status');

  if p_status='completed' then
    insert into public.payment_transactions(
      payer_id,payee_id,trip_id,method,amount,currency,status,paid_at
    ) values(
      v_passenger,v_driver,p_trip_id,v_payment_method,
      coalesce(v_fare,0),coalesce(v_currency,'BOB'),
      case when v_direct then 'paid' else 'pending' end,
      case when v_direct then now() else null end
    )
    on conflict(trip_id) where trip_id is not null do nothing;

    update public.driver_profiles
    set completed_trips=completed_trips+1,
        online_status='online',updated_at=now()
    where id=v_driver;

    insert into public.notifications(user_id,title,body,type)
    values(
      v_driver,'Viaje completado',
      'El viaje quedó registrado correctamente en tus ganancias.',
      'trip_completed'
    );
  end if;
end;
$$;


-- Passenger default and driver acceptance preferences.
create or replace function public.set_my_preferred_ride_payment_method(
  p_method text,
  p_channel text default 'production'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_zone_id uuid;
  v_methods jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  select u.last_zone_id into v_zone_id from public.users u where u.id=v_uid;
  if v_zone_id is null then raise exception 'No se pudo determinar tu zona'; end if;
  v_methods:=public.zone_ride_payment_methods(v_zone_id,p_channel);
  if not exists(
    select 1 from jsonb_array_elements(v_methods) m
    where m->>'provider_key'=p_method
  ) then
    raise exception 'Método no disponible para viajes en tu zona';
  end if;
  update public.users
  set preferred_payment_method=p_method,updated_at=now()
  where id=v_uid;
end;
$$;

create or replace function public.set_my_driver_payment_methods(
  p_methods text[],
  p_channel text default 'production'
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_zone_id uuid;
  v_allowed jsonb;
  v_method text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if p_methods is null or cardinality(p_methods)=0 then
    raise exception 'Selecciona al menos un método de cobro';
  end if;

  select d.zone_id into v_zone_id
  from public.driver_profiles d
  where d.id=v_uid;
  if v_zone_id is null then
    select u.last_zone_id into v_zone_id from public.users u where u.id=v_uid;
  end if;
  if v_zone_id is null then raise exception 'No se pudo determinar tu zona'; end if;

  v_allowed:=public.zone_ride_payment_methods(v_zone_id,p_channel);
  foreach v_method in array p_methods loop
    if not exists(
      select 1 from jsonb_array_elements(v_allowed) m
      where m->>'provider_key'=v_method
    ) then
      raise exception 'Método % no disponible en tu zona',v_method;
    end if;
  end loop;

  update public.driver_profiles
  set accepted_payment_methods=p_methods,updated_at=now()
  where id=v_uid;
end;
$$;

create or replace function public.available_ride_requests_for_driver_v3(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_base jsonb;
  v_accepted text[];
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  v_base:=public.available_ride_requests_for_driver_v2(p_channel);
  select d.accepted_payment_methods
  into v_accepted
  from public.driver_profiles d
  where d.id=v_uid;

  if v_accepted is null or cardinality(v_accepted)=0 then
    return v_base;
  end if;

  select coalesce(jsonb_agg(item),'[]'::jsonb)
  into v_result
  from jsonb_array_elements(coalesce(v_base,'[]'::jsonb)) item
  where item->>'payment_method'=any(v_accepted);

  return coalesce(v_result,'[]'::jsonb);
end;
$$;

revoke all on function public.set_my_preferred_ride_payment_method(text,text)
  from public,anon;
revoke all on function public.set_my_driver_payment_methods(text[],text)
  from public,anon;
revoke all on function public.available_ride_requests_for_driver_v3(text)
  from public,anon;
grant execute on function public.set_my_preferred_ride_payment_method(text,text)
  to authenticated;
grant execute on function public.set_my_driver_payment_methods(text[],text)
  to authenticated;
grant execute on function public.available_ride_requests_for_driver_v3(text)
  to authenticated;
