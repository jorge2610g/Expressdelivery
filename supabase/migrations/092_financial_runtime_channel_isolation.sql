-- Isolate financial data between Preview and Production.

alter table public.payment_transactions
  add column if not exists channel text not null default 'production';
alter table public.wallet_transactions
  add column if not exists channel text not null default 'production';
alter table public.wallet_topup_requests
  add column if not exists channel text not null default 'production';
alter table public.wallet_country_accounts
  add column if not exists channel text not null default 'production';

do $$
begin
  if not exists (select 1 from pg_constraint where conname='payment_transactions_channel_check') then
    alter table public.payment_transactions add constraint payment_transactions_channel_check check (channel in ('preview','production'));
  end if;
  if not exists (select 1 from pg_constraint where conname='wallet_transactions_channel_check') then
    alter table public.wallet_transactions add constraint wallet_transactions_channel_check check (channel in ('preview','production'));
  end if;
  if not exists (select 1 from pg_constraint where conname='wallet_topup_requests_channel_check') then
    alter table public.wallet_topup_requests add constraint wallet_topup_requests_channel_check check (channel in ('preview','production'));
  end if;
  if not exists (select 1 from pg_constraint where conname='wallet_country_accounts_channel_check') then
    alter table public.wallet_country_accounts add constraint wallet_country_accounts_channel_check check (channel in ('preview','production'));
  end if;
end $$;

update public.payment_transactions p
set channel=coalesce(
  (select t.channel from public.trips t where t.id=p.trip_id),
  (select d.channel from public.delivery_requests d where d.id=p.delivery_id),
  'production'
);

update public.wallet_transactions w
set channel=coalesce(
  (select t.channel from public.trips t where t.id=w.trip_id),
  (select d.channel from public.delivery_requests d where d.id=w.delivery_id),
  'production'
);

update public.wallet_topup_requests set channel='production' where channel is distinct from 'production';
update public.wallet_country_accounts set channel='production' where channel is distinct from 'production';

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid='public.wallet_country_accounts'::regclass
      and conname='wallet_country_accounts_pkey'
  ) then
    alter table public.wallet_country_accounts drop constraint wallet_country_accounts_pkey;
  end if;
end $$;

alter table public.wallet_country_accounts
  add constraint wallet_country_accounts_pkey
  primary key(user_id,country_code,channel);

create index if not exists payment_transactions_user_channel_country_created_idx
  on public.payment_transactions(payer_id,payee_id,channel,country_code,created_at desc);
create index if not exists wallet_transactions_user_channel_country_created_idx
  on public.wallet_transactions(user_id,channel,country_code,created_at desc);
create index if not exists wallet_topup_requests_user_channel_country_created_idx
  on public.wallet_topup_requests(user_id,channel,country_code,created_at desc);

create or replace function public.sync_payment_runtime_channel()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_channel text;
begin
  if new.trip_id is not null then
    select t.channel into v_channel from public.trips t where t.id=new.trip_id;
  elsif new.delivery_id is not null then
    select d.channel into v_channel from public.delivery_requests d where d.id=new.delivery_id;
  end if;
  new.channel:=public.normalize_runtime_channel(coalesce(v_channel,new.channel));
  return new;
end;
$$;

drop trigger if exists trg_sync_payment_runtime_channel on public.payment_transactions;
create trigger trg_sync_payment_runtime_channel
before insert or update of trip_id,delivery_id,channel
on public.payment_transactions
for each row execute function public.sync_payment_runtime_channel();

create or replace function public.sync_wallet_transaction_runtime_channel()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_channel text;
begin
  if new.trip_id is not null then
    select t.channel into v_channel from public.trips t where t.id=new.trip_id;
  elsif new.delivery_id is not null then
    select d.channel into v_channel from public.delivery_requests d where d.id=new.delivery_id;
  end if;
  new.channel:=public.normalize_runtime_channel(coalesce(v_channel,new.channel));
  return new;
end;
$$;

drop trigger if exists trg_sync_wallet_transaction_runtime_channel on public.wallet_transactions;
create trigger trg_sync_wallet_transaction_runtime_channel
before insert or update of trip_id,delivery_id,channel
on public.wallet_transactions
for each row execute function public.sync_wallet_transaction_runtime_channel();

create or replace function public.ensure_country_wallet_v2(p_channel text default 'production')
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_context jsonb;
  v_country text;
  v_currency text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_wallet public.wallet_country_accounts%rowtype;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if v_channel='preview' and not public.is_active_audit_user(v_uid) then raise exception 'Preview requiere una cuenta QA/sandbox activa'; end if;
  if v_channel='production' and public.is_active_audit_user(v_uid) then raise exception 'Una cuenta QA/Preview no puede usar la billetera de Producción'; end if;

  v_context:=public.current_operating_context();
  v_country:=v_context->>'country_code';
  v_currency:=upper(coalesce(v_context->>'currency_code',''));
  if nullif(v_country,'') is null or nullif(v_currency,'') is null then
    raise exception 'No se pudo determinar país y moneda de la zona actual';
  end if;

  insert into public.wallet_country_accounts(user_id,country_code,channel,currency,balance)
  values(v_uid,v_country,v_channel,v_currency,0)
  on conflict(user_id,country_code,channel) do update set
    currency=excluded.currency,
    updated_at=case
      when public.wallet_country_accounts.currency is distinct from excluded.currency then now()
      else public.wallet_country_accounts.updated_at
    end;

  select * into v_wallet
  from public.wallet_country_accounts
  where user_id=v_uid and country_code=v_country and channel=v_channel;

  return to_jsonb(v_wallet)||jsonb_build_object(
    'country',v_context->>'country',
    'zone_id',v_context->>'zone_id',
    'zone_key',v_context->>'zone_key',
    'zone_name',v_context->>'zone_name'
  );
end;
$$;

create or replace function public.my_country_payments_v2(p_channel text default 'production')
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';
  return (
    select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]'::jsonb)
    from public.payment_transactions p
    where (p.payer_id=v_uid or p.payee_id=v_uid)
      and p.country_code=v_country
      and p.channel=v_channel
  );
end;
$$;

create or replace function public.my_country_wallet_transactions_v2(p_channel text default 'production')
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';
  return (
    select coalesce(jsonb_agg(to_jsonb(wt) order by wt.created_at desc),'[]'::jsonb)
    from public.wallet_transactions wt
    where wt.user_id=v_uid and wt.country_code=v_country and wt.channel=v_channel
  );
end;
$$;

create or replace function public.my_country_wallet_topups_v2(p_channel text default 'production')
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_country text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';
  return (
    select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc),'[]'::jsonb)
    from public.wallet_topup_requests r
    where r.user_id=v_uid and r.country_code=v_country and r.channel=v_channel
  );
end;
$$;

create or replace function public.request_country_wallet_topup_v2(
  p_amount numeric,
  p_channel text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_context jsonb;
  v_id uuid;
  v_currency text;
  v_country text;
  v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if v_channel='preview' and not public.is_active_audit_user(v_uid) then raise exception 'Preview requiere una cuenta QA/sandbox activa'; end if;
  if v_channel='production' and public.is_active_audit_user(v_uid) then raise exception 'Una cuenta QA/Preview no puede recargar Producción'; end if;
  if p_amount is null or p_amount<1 or p_amount>5000000 then raise exception 'Monto inválido'; end if;

  v_context:=public.current_operating_context();
  v_currency:=v_context->>'currency_code';
  v_country:=v_context->>'country_code';
  if v_currency is null or v_country is null then raise exception 'No se pudo determinar la moneda de tu país actual'; end if;

  if exists(
    select 1 from public.wallet_topup_requests
    where user_id=v_uid and country_code=v_country and channel=v_channel
      and status='pending' and created_at>now()-interval '10 minutes'
  ) then
    raise exception 'Ya tienes una recarga pendiente reciente en este entorno';
  end if;

  insert into public.wallet_topup_requests(user_id,amount,currency,country_code,channel)
  values(v_uid,round(p_amount,2),v_currency,v_country,v_channel)
  returning id into v_id;

  perform set_config('app.runtime_channel',v_channel,true);
  insert into public.notifications(user_id,title,body,type,metadata)
  select
    a.user_id,
    'Nueva recarga pendiente',
    coalesce(nullif(trim(u.full_name),''),'Usuario Express')||
      ' solicitó una recarga de '||v_currency||' '||
      trim(to_char(p_amount,'FM999999990.00')),
    'wallet_topup_pending',
    jsonb_build_object(
      'country_code',v_country,'currency',v_currency,
      'request_id',v_id,'channel',v_channel
    )
  from public.admin_users a
  left join public.users u on u.id=v_uid;

  return v_id;
end;
$$;

create or replace function public.apply_country_wallet_transaction()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_currency text;
begin
  if new.status<>'completed' or new.country_code is null then return new; end if;
  select z.currency_code into v_currency
  from public.service_zones z
  where z.country_code=new.country_code
  order by z.zone_key
  limit 1;
  if v_currency is null then return new; end if;

  insert into public.wallet_country_accounts(user_id,country_code,channel,currency,balance)
  values(
    new.user_id,new.country_code,
    public.normalize_runtime_channel(new.channel),
    upper(v_currency),new.amount
  )
  on conflict(user_id,country_code,channel) do update set
    balance=public.wallet_country_accounts.balance+excluded.balance,
    currency=excluded.currency,
    updated_at=now();
  return new;
end;
$$;

revoke all on function public.ensure_country_wallet_v2(text) from public,anon;
grant execute on function public.ensure_country_wallet_v2(text) to authenticated;
revoke all on function public.my_country_payments_v2(text) from public,anon;
grant execute on function public.my_country_payments_v2(text) to authenticated;
revoke all on function public.my_country_wallet_transactions_v2(text) from public,anon;
grant execute on function public.my_country_wallet_transactions_v2(text) to authenticated;
revoke all on function public.my_country_wallet_topups_v2(text) from public,anon;
grant execute on function public.my_country_wallet_topups_v2(text) to authenticated;
revoke all on function public.request_country_wallet_topup_v2(numeric,text) from public,anon;
grant execute on function public.request_country_wallet_topup_v2(numeric,text) to authenticated;
