-- One-level driver referrals in Bolivia. Each successful plan payment credits
-- the referrer once, using the configured percentage and the same internal
-- country wallet. No trip commission or cash withdrawal is involved.
begin;

alter table public.driver_subscription_payments
  add column if not exists channel text not null default 'production';
do $$ begin
  if not exists(select 1 from pg_constraint where conname='driver_subscription_payments_channel_check') then
    alter table public.driver_subscription_payments
      add constraint driver_subscription_payments_channel_check
      check(channel in ('preview','production'));
  end if;
end $$;

create table if not exists public.driver_referral_codes(
  driver_id uuid not null references public.driver_profiles(id) on delete cascade,
  channel text not null check(channel in ('preview','production')),
  code text not null unique check(code ~ '^[A-F0-9]{10}$'),
  created_at timestamptz not null default now(),
  primary key(driver_id,channel)
);
alter table public.driver_referral_codes enable row level security;
revoke all on public.driver_referral_codes from public,anon,authenticated;

alter table public.benefit_referral_links
  add column if not exists plan_payment_percent numeric(7,4)
    check(plan_payment_percent between 0 and 100);

create unique index if not exists benefit_program_one_active_driver_referral_idx
  on public.benefit_programs(channel,zone_id)
  where program_type='referral_commission' and state='active';

create table if not exists public.benefit_subscription_commissions(
  payment_id bigint primary key references public.driver_subscription_payments(id),
  program_id uuid not null references public.benefit_programs(id),
  referral_id uuid not null references public.benefit_referral_links(id),
  referrer_id uuid not null references public.users(id),
  referred_driver_id uuid not null references public.users(id),
  channel text not null check(channel in ('preview','production')),
  country_code text not null check(country_code='BO'),
  currency_code text not null check(currency_code='BOB'),
  plan_amount numeric(12,2) not null check(plan_amount>=0),
  commission_percent numeric(7,4) not null check(commission_percent between 0 and 100),
  commission_amount numeric(12,2) not null check(commission_amount>=0),
  wallet_transaction_id uuid references public.wallet_transactions(id),
  created_at timestamptz not null default now()
);
alter table public.benefit_subscription_commissions enable row level security;
revoke all on public.benefit_subscription_commissions from public,anon,authenticated;
create index if not exists benefit_subscription_commissions_referrer_idx
  on public.benefit_subscription_commissions(referrer_id,channel,created_at desc);

create or replace function public.sync_driver_subscription_payment_channel()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_channel text;
begin
  v_channel:=public.admin_user_runtime_environment(new.driver_id);
  if v_channel not in ('preview','production') then
    raise exception 'El entorno del conductor no está disponible';
  end if;
  new.channel:=v_channel;
  return new;
end $$;
drop trigger if exists driver_subscription_payment_runtime_channel
  on public.driver_subscription_payments;
create trigger driver_subscription_payment_runtime_channel
before insert or update of driver_id,channel on public.driver_subscription_payments
for each row execute function public.sync_driver_subscription_payment_channel();
revoke all on function public.sync_driver_subscription_payment_channel() from public,anon,authenticated;

create or replace function public.my_driver_referral_status(p_channel text default 'production')
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();v_runtime jsonb;v_zone uuid;v_country text;v_code text;
  v_program uuid;v_percent numeric;v_total numeric;v_has_referrer boolean;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false
    or (v_runtime->>'environment') is distinct from p_channel
    or p_channel not in ('preview','production') then raise exception 'Entorno de datos no autorizado'; end if;
  select dp.zone_id,z.country_code into v_zone,v_country
    from public.driver_profiles dp join public.service_zones z on z.id=dp.zone_id
    where dp.id=v_uid and z.active;
  if v_zone is null then raise exception 'Se requiere perfil de conductor y zona activa'; end if;
  if v_country<>'BO' then
    return jsonb_build_object('eligible',false,'country_code',v_country,'currency','BOB');
  end if;
  insert into public.driver_referral_codes(driver_id,channel,code)
    values(v_uid,p_channel,upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)))
    on conflict(driver_id,channel) do nothing;
  select code into v_code from public.driver_referral_codes
    where driver_id=v_uid and channel=p_channel;
  select id,(config->>'plan_payment_percent')::numeric into v_program,v_percent
    from public.benefit_programs where program_type='referral_commission'
      and state='active' and zone_id=v_zone and channel=p_channel
      and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now())
    order by created_at desc limit 1;
  select coalesce(sum(commission_amount),0) into v_total
    from public.benefit_subscription_commissions where referrer_id=v_uid and channel=p_channel;
  select exists(select 1 from public.benefit_referral_links
    l join public.benefit_programs p on p.id=l.program_id
    where l.referee_id=v_uid and l.channel=p_channel
      and p.program_type='referral_commission') into v_has_referrer;
  return jsonb_build_object('eligible',true,'code',v_code,'zone_id',v_zone,'country_code',v_country,
    'program_active',v_program is not null,'percent',v_percent,
    'referrals',(select count(*) from public.benefit_referral_links l
      join public.benefit_programs p on p.id=l.program_id
      where l.referrer_id=v_uid and l.channel=p_channel and p.program_type='referral_commission'),
    'credited_total',v_total,'has_referrer',v_has_referrer,'currency','BOB');
end $$;

create or replace function public.apply_driver_referral_code(p_code text,p_channel text default 'production')
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();v_runtime jsonb;v_zone uuid;v_country text;
  v_referrer uuid;v_program uuid;v_percent numeric;v_link uuid;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false
    or (v_runtime->>'environment') is distinct from p_channel
    or p_channel not in ('preview','production') then raise exception 'Entorno de datos no autorizado'; end if;
  select dp.zone_id,z.country_code into v_zone,v_country
    from public.driver_profiles dp join public.service_zones z on z.id=dp.zone_id
    where dp.id=v_uid and z.active;
  if v_zone is null or v_country<>'BO' then raise exception 'Los referidos de pagos de plan están disponibles en Bolivia'; end if;
  select driver_id into v_referrer from public.driver_referral_codes
    where code=upper(trim(coalesce(p_code,''))) and channel=p_channel;
  if v_referrer is null or v_referrer=v_uid then raise exception 'Código de referido inválido'; end if;
  if not exists(select 1 from public.driver_profiles where id=v_referrer) then
    raise exception 'El código no pertenece a un conductor'; end if;
  select id,(config->>'plan_payment_percent')::numeric into v_program,v_percent
    from public.benefit_programs where program_type='referral_commission'
      and state='active' and zone_id=v_zone and channel=p_channel
      and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now())
    order by created_at desc limit 1;
  if v_program is null or coalesce(v_percent,0)<=0 then
    raise exception 'El programa de referidos no está activo en tu zona'; end if;
  insert into public.benefit_referral_links(channel,zone_id,referrer_id,referee_id,
    program_id,state,plan_payment_percent)
  values(p_channel,v_zone,v_referrer,v_uid,v_program,'pending',v_percent)
  on conflict(channel,referee_id) do nothing returning id into v_link;
  if v_link is null then raise exception 'Este conductor ya tiene un código de referido registrado'; end if;
  return jsonb_build_object('linked',true,'percent',v_percent,'currency','BOB');
end $$;

create or replace function public.credit_driver_plan_referral()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_plan public.driver_subscription_plans%rowtype;v_zone public.service_zones%rowtype;
  v_link public.benefit_referral_links%rowtype;v_amount numeric(12,2);v_commission numeric(12,2);
  v_ledger uuid;
begin
  if new.status<>'approved' or old.status='approved' then return new; end if;
  select * into v_plan from public.driver_subscription_plans where id=new.plan_id;
  if not found then return new; end if;
  select * into v_zone from public.service_zones where zone_key=v_plan.zone_key and active limit 1;
  if not found or v_zone.country_code<>'BO' or upper(v_plan.currency_code)<>'BOB' then return new; end if;
  select * into v_link from public.benefit_referral_links
    where referee_id=new.driver_id and channel=new.channel and state in ('pending','qualified') for update;
  if not found or coalesce(v_link.plan_payment_percent,0)<=0 then return new; end if;
  v_amount:=round(coalesce(new.amount,0),2);
  v_commission:=round(v_amount*v_link.plan_payment_percent/100,2);
  if v_commission<=0 then return new; end if;
  insert into public.benefit_subscription_commissions(payment_id,program_id,referral_id,
    referrer_id,referred_driver_id,channel,country_code,currency_code,plan_amount,
    commission_percent,commission_amount)
  values(new.id,v_link.program_id,v_link.id,v_link.referrer_id,new.driver_id,
    new.channel,'BO','BOB',v_amount,v_link.plan_payment_percent,v_commission)
  on conflict(payment_id) do nothing;
  if not found then return new; end if;
  -- The existing completed wallet-ledger trigger updates the country wallet;
  -- inserting a second direct balance update here would double-credit it.
  insert into public.wallet_transactions(user_id,amount,type,status,reference,country_code,channel)
  values(v_link.referrer_id,v_commission,'adjustment','completed',
    'Referido: porcentaje de pago de plan '||new.id::text,'BO',new.channel)
  returning id into v_ledger;
  update public.benefit_subscription_commissions set wallet_transaction_id=v_ledger
    where payment_id=new.id;
  update public.benefit_referral_links set state='qualified',qualified_at=coalesce(qualified_at,now())
    where id=v_link.id;
  if new.channel='production' then
    perform public.mirror_legacy_wallet_delta(v_link.referrer_id,'BOB',v_commission);
  end if;
  return new;
end $$;
drop trigger if exists driver_plan_referral_credit on public.driver_subscription_payments;
create trigger driver_plan_referral_credit after update of status
on public.driver_subscription_payments for each row execute function public.credit_driver_plan_referral();
revoke all on function public.credit_driver_plan_referral() from public,anon,authenticated;

revoke all on function public.my_driver_referral_status(text) from public,anon;
revoke all on function public.apply_driver_referral_code(text,text) from public,anon;
grant execute on function public.my_driver_referral_status(text) to authenticated;
grant execute on function public.apply_driver_referral_code(text,text) to authenticated;
commit;
