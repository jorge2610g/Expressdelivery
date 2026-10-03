-- Preserve driver subscriptions independently by operating zone.
-- A Bolivia subscription must not overwrite or extend a Chile subscription,
-- and returning to a zone restores the state stored for that zone.

create table if not exists public.driver_zone_subscriptions (
  driver_id uuid not null
    references public.driver_profiles(id) on delete cascade,
  zone_id uuid not null
    references public.service_zones(id) on delete cascade,
  plan_id bigint
    references public.driver_subscription_plans(id),
  status text not null default 'inactive',
  started_at timestamptz,
  expires_at timestamptz,
  last_payment_id bigint
    references public.driver_subscription_payments(id),
  updated_at timestamptz not null default now(),
  primary key(driver_id,zone_id),
  constraint driver_zone_subscriptions_status_check
    check(
      status=any(
        array[
          'inactive'::text,
          'active'::text,
          'expired'::text,
          'suspended'::text
        ]
      )
    )
);

alter table public.driver_zone_subscriptions enable row level security;
revoke all on public.driver_zone_subscriptions
from public,anon,authenticated;
grant select on public.driver_zone_subscriptions
to authenticated;

drop policy if exists driver_zone_subscriptions_select_own
on public.driver_zone_subscriptions;
create policy driver_zone_subscriptions_select_own
on public.driver_zone_subscriptions
for select to authenticated
using ((select auth.uid())=driver_id);

create index if not exists driver_zone_subscriptions_zone_status_idx
  on public.driver_zone_subscriptions(
    zone_id,status,expires_at
  );

-- Backfill the current legacy row into the zone belonging to its plan.
insert into public.driver_zone_subscriptions(
  driver_id,zone_id,plan_id,status,
  started_at,expires_at,last_payment_id,updated_at
)
select
  s.driver_id,
  z.id,
  s.plan_id,
  s.status,
  s.started_at,
  s.expires_at,
  s.last_payment_id,
  s.updated_at
from public.driver_subscriptions s
join public.driver_subscription_plans p on p.id=s.plan_id
join public.service_zones z on z.zone_key=p.zone_key
on conflict(driver_id,zone_id) do update set
  plan_id=excluded.plan_id,
  status=excluded.status,
  started_at=excluded.started_at,
  expires_at=excluded.expires_at,
  last_payment_id=excluded.last_payment_id,
  updated_at=excluded.updated_at;

-- Every legacy/admin subscription write is mirrored into the correct zone.
create or replace function public.sync_driver_zone_subscription()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_zone_id uuid;
begin
  if new.plan_id is null then return new; end if;

  select z.id into v_zone_id
  from public.driver_subscription_plans p
  join public.service_zones z on z.zone_key=p.zone_key
  where p.id=new.plan_id
  limit 1;

  if v_zone_id is null then return new; end if;

  insert into public.driver_zone_subscriptions(
    driver_id,zone_id,plan_id,status,
    started_at,expires_at,last_payment_id,updated_at
  )
  values(
    new.driver_id,v_zone_id,new.plan_id,new.status,
    new.started_at,new.expires_at,new.last_payment_id,new.updated_at
  )
  on conflict(driver_id,zone_id) do update set
    plan_id=excluded.plan_id,
    status=excluded.status,
    started_at=excluded.started_at,
    expires_at=excluded.expires_at,
    last_payment_id=excluded.last_payment_id,
    updated_at=excluded.updated_at;

  return new;
end;
$function$;

drop trigger if exists driver_subscriptions_sync_zone
on public.driver_subscriptions;
create trigger driver_subscriptions_sync_zone
after insert or update on public.driver_subscriptions
for each row execute function public.sync_driver_zone_subscription();

revoke execute on function public.sync_driver_zone_subscription()
from public,anon,authenticated;

-- Finalization now extends only the subscription for the payment's zone.
-- The legacy single row is still updated as a compatibility mirror for the
-- current Production binary, while the zone table remains authoritative.
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

  if v_payment.status<>'pending' then
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

revoke execute on function public.service_finalize_driver_subscription_payment(
  bigint,text,jsonb
) from public,anon,authenticated;
grant execute on function public.service_finalize_driver_subscription_payment(
  bigint,text,jsonb
) to service_role;

create or replace function public.pay_driver_subscription_with_country_wallet(
  p_plan_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
    select 1
    from public.driver_profiles d
    where d.id=v_uid
  ) then
    raise exception 'Perfil de conductor requerido';
  end if;

  select z.* into v_zone
  from public.driver_profiles d
  join public.service_zones z on z.id=d.zone_id
  where d.id=v_uid and z.active=true;

  if not found then
    raise exception 'No se pudo determinar la zona del conductor';
  end if;

  select p.* into v_plan
  from public.driver_subscription_plans p
  where p.id=p_plan_id
    and p.active=true
    and p.zone_key=v_zone.zone_key;

  if not found then
    raise exception 'Plan no disponible en tu zona actual';
  end if;

  select * into v_zone_settings
  from public.driver_subscription_zone_settings
  where zone_id=v_zone.id;

  if not found or not coalesce(v_zone_settings.enabled,false) then
    raise exception 'Las suscripciones no están habilitadas en esta zona';
  end if;

  perform public.ensure_country_wallet();

  select * into v_wallet
  from public.wallet_country_accounts
  where user_id=v_uid
    and country_code=v_zone.country_code
  for update;

  if upper(coalesce(v_wallet.currency,''))<>
     upper(coalesce(v_plan.currency_code,'')) then
    raise exception
      'La billetera del país está en % y este plan se cobra en %.',
      v_wallet.currency,v_plan.currency_code;
  end if;

  if coalesce(v_wallet.balance,0)<v_plan.amount then
    raise exception 'Saldo insuficiente en la billetera';
  end if;

  insert into public.driver_subscription_payments(
    driver_id,plan_id,amount,currency_code,
    provider,status,provider_data,
    paid_at,expires_at,zone_key
  )
  values(
    v_uid,
    v_plan.id,
    v_plan.amount,
    v_plan.currency_code,
    'wallet',
    'pending',
    jsonb_build_object(
      'source','country_wallet',
      'country_code',v_zone.country_code,
      'balance_before',v_wallet.balance
    ),
    now(),
    now()+interval '15 minutes',
    v_plan.zone_key
  )
  returning * into v_payment;

  insert into public.wallet_transactions(
    user_id,amount,type,status,reference,
    country_code,created_at
  )
  values(
    v_uid,
    -v_plan.amount,
    'payment',
    'completed',
    'driver_subscription:'||v_payment.id::text,
    v_zone.country_code,
    now()
  );

  perform public.mirror_legacy_wallet_delta(
    v_uid,
    v_plan.currency_code,
    -v_plan.amount
  );

  v_result:=public.service_finalize_driver_subscription_payment(
    v_payment.id,
    'country-wallet-'||v_payment.id::text,
    jsonb_build_object(
      'source','country_wallet',
      'country_code',v_zone.country_code,
      'balance_before',v_wallet.balance,
      'balance_after',v_wallet.balance-v_plan.amount
    )
  );

  insert into public.notifications(
    user_id,title,body,type,metadata
  )
  values(
    v_uid,
    'Suscripción activada',
    'Tu plan '||v_plan.name||
      ' fue pagado con Billetera Express.',
    'driver_subscription',
    jsonb_build_object(
      'payment_id',v_payment.id,
      'plan_id',v_plan.id,
      'zone_key',v_plan.zone_key,
      'country_code',v_zone.country_code,
      'provider','wallet'
    )
  );

  return v_result||jsonb_build_object(
    'provider','wallet',
    'payment_id',v_payment.id,
    'country_code',v_zone.country_code,
    'balance_before',v_wallet.balance,
    'balance_after',v_wallet.balance-v_plan.amount,
    'currency_code',v_plan.currency_code
  );
end;
$function$;

revoke execute on function public.pay_driver_subscription_with_country_wallet(
  bigint
) from public,anon;
grant execute on function public.pay_driver_subscription_with_country_wallet(
  bigint
) to authenticated;

create or replace function public.my_driver_subscription_state()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_zone_id uuid;
  v_zone_key text;
  v_zone_name text;
  v_zone_enabled boolean:=false;
  v_zone_enforce boolean:=false;
  v_global public.driver_subscription_settings%rowtype;
  v_sub public.driver_zone_subscriptions%rowtype;
  v_plan public.driver_subscription_plans%rowtype;
  v_usable boolean:=false;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;

  select dp.zone_id,z.zone_key,z.name
  into v_zone_id,v_zone_key,v_zone_name
  from public.driver_profiles dp
  left join public.service_zones z on z.id=dp.zone_id
  where dp.id=v_uid;

  select * into v_global
  from public.driver_subscription_settings
  where id=true;

  if v_zone_id is not null then
    select enabled,enforce_access
    into v_zone_enabled,v_zone_enforce
    from public.driver_subscription_zone_settings
    where zone_id=v_zone_id;

    select * into v_sub
    from public.driver_zone_subscriptions
    where driver_id=v_uid
      and zone_id=v_zone_id;
  end if;

  if v_sub.plan_id is not null then
    select * into v_plan
    from public.driver_subscription_plans
    where id=v_sub.plan_id;
  end if;

  v_usable:=coalesce(
    v_sub.status='active'
    and v_sub.expires_at>now()
    and v_plan.zone_key=v_zone_key,
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
    'status',case
      when v_usable then 'active'
      else coalesce(v_sub.status,'inactive')
    end,
    'plan_id',v_sub.plan_id,
    'plan_name',v_plan.name,
    'plan_code',v_plan.code,
    'plan_zone_key',v_plan.zone_key,
    'started_at',v_sub.started_at,
    'expires_at',v_sub.expires_at,
    'remaining_seconds',case
      when v_sub.expires_at is null then 0
      else greatest(
        0,
        extract(epoch from(v_sub.expires_at-now()))::bigint
      )
    end
  );
end;
$function$;

revoke execute on function public.my_driver_subscription_state()
from public,anon;
grant execute on function public.my_driver_subscription_state()
to authenticated;

create or replace function public.driver_subscription_allows_dispatch(
  p_driver_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_zone_id uuid;
  v_enforce boolean:=false;
begin
  if p_driver_id is null then return false; end if;

  -- Synthetic QA identities remain exempt exactly as before.
  if exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=p_driver_id
      and m.enabled=true
      and g.active=true
  ) then
    return true;
  end if;

  select dp.zone_id into v_zone_id
  from public.driver_profiles dp
  where dp.id=p_driver_id;

  if v_zone_id is null then return true; end if;

  select coalesce(s.enforce_access,false)
  into v_enforce
  from public.driver_subscription_zone_settings s
  where s.zone_id=v_zone_id;

  if not coalesce(v_enforce,false) then
    return true;
  end if;

  return exists(
    select 1
    from public.driver_zone_subscriptions s
    join public.driver_subscription_plans p on p.id=s.plan_id
    join public.service_zones z on z.id=s.zone_id
    where s.driver_id=p_driver_id
      and s.zone_id=v_zone_id
      and s.status='active'
      and s.expires_at>now()
      and p.active=true
      and p.zone_key=z.zone_key
  );
end;
$function$;

revoke execute on function public.driver_subscription_allows_dispatch(uuid)
from public,anon;
grant execute on function public.driver_subscription_allows_dispatch(uuid)
to authenticated,service_role;
