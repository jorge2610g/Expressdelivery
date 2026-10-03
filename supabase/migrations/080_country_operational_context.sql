-- Country-aware operational context for Express accounts.
-- Keeps one global identity while isolating balances, financial movements,
-- trips/deliveries and visible operational progress by country.
-- Existing single-wallet tables remain for backward compatibility until
-- Preview is approved for Production.

alter table public.service_zones
  add column if not exists country_code text;

update public.service_zones
set country_code=case lower(trim(country))
  when 'bolivia' then 'BO'
  when 'chile' then 'CL'
  else country_code
end
where country_code is null;

alter table public.service_zones
  drop constraint if exists service_zones_country_code_check;
alter table public.service_zones
  add constraint service_zones_country_code_check
  check (country_code is null or country_code ~ '^[A-Z]{2}$');

create index if not exists service_zones_country_code_idx
  on public.service_zones(country_code);

create or replace function public.set_service_zone_country_code()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.country_code is null or trim(new.country_code)='' then
    new.country_code:=case lower(trim(coalesce(new.country,'')))
      when 'bolivia' then 'BO'
      when 'chile' then 'CL'
      else null
    end;
  else
    new.country_code:=upper(trim(new.country_code));
  end if;
  return new;
end;
$function$;

drop trigger if exists service_zones_set_country_code on public.service_zones;
create trigger service_zones_set_country_code
before insert or update of country,country_code
on public.service_zones
for each row execute function public.set_service_zone_country_code();

revoke execute on function public.set_service_zone_country_code()
from public,anon,authenticated;

create table if not exists public.wallet_country_accounts (
  user_id uuid not null references public.users(id) on delete cascade,
  country_code text not null,
  currency text not null,
  balance numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(user_id,country_code),
  constraint wallet_country_accounts_country_check
    check(country_code ~ '^[A-Z]{2}$'),
  constraint wallet_country_accounts_currency_check
    check(currency=upper(currency))
);

alter table public.wallet_country_accounts enable row level security;
revoke all on public.wallet_country_accounts from public,anon,authenticated;
grant select on public.wallet_country_accounts to authenticated;

drop policy if exists wallet_country_accounts_select_own
on public.wallet_country_accounts;
create policy wallet_country_accounts_select_own
on public.wallet_country_accounts
for select to authenticated
using ((select auth.uid())=user_id);

alter table public.wallet_transactions
  add column if not exists country_code text;
alter table public.wallet_topup_requests
  add column if not exists country_code text;
alter table public.payment_transactions
  add column if not exists country_code text;
alter table public.delivery_requests
  add column if not exists country_code text;

create index if not exists wallet_transactions_user_country_created_idx
  on public.wallet_transactions(user_id,country_code,created_at desc);
create index if not exists wallet_topup_requests_user_country_created_idx
  on public.wallet_topup_requests(user_id,country_code,created_at desc);
create index if not exists payment_transactions_payee_country_created_idx
  on public.payment_transactions(payee_id,country_code,created_at desc);
create index if not exists payment_transactions_payer_country_created_idx
  on public.payment_transactions(payer_id,country_code,created_at desc);
create index if not exists delivery_requests_country_created_idx
  on public.delivery_requests(country_code,created_at desc);

-- Preserve every legacy non-zero wallet in the country represented by its
-- currency. This is what protects historical BOB when the driver is in Chile.
insert into public.wallet_country_accounts(
  user_id,country_code,currency,balance,updated_at
)
select
  w.user_id,
  z.country_code,
  upper(w.currency),
  w.balance,
  w.updated_at
from public.wallet_accounts w
join lateral (
  select sz.country_code
  from public.service_zones sz
  where sz.country_code is not null
    and upper(sz.currency_code)=upper(w.currency)
  order by sz.zone_key
  limit 1
) z on true
on conflict(user_id,country_code) do update set
  currency=excluded.currency,
  balance=excluded.balance,
  updated_at=excluded.updated_at;

-- Also create a zero wallet for the user's current operating country. No
-- conversion is performed.
insert into public.wallet_country_accounts(
  user_id,country_code,currency,balance
)
select
  u.id,
  z.country_code,
  upper(z.currency_code),
  0
from public.users u
left join public.driver_profiles dp on dp.id=u.id
join public.service_zones z
  on z.id=case
    when u.active_mode='driver' and dp.zone_id is not null then dp.zone_id
    else coalesce(u.last_zone_id,dp.zone_id)
  end
where z.country_code is not null
on conflict(user_id,country_code) do nothing;

-- Delivery country becomes authoritative alongside delivery currency.
update public.delivery_requests d
set country_code=coalesce(
  (
    select z.country_code
    from public.marketplace_orders o
    join public.service_zones z on z.id=o.zone_id
    where o.id=d.marketplace_order_id
    limit 1
  ),
  (
    select z.country_code
    from public.service_zones z
    where upper(z.currency_code)=upper(d.currency)
      and z.country_code is not null
    order by z.zone_key
    limit 1
  )
)
where d.country_code is null;

create or replace function public.set_delivery_currency_from_zone()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_zone_id uuid;
  v_currency text;
  v_country text;
begin
  if new.marketplace_order_id is not null then
    select o.zone_id into v_zone_id
    from public.marketplace_orders o
    where o.id=new.marketplace_order_id;
  end if;

  if v_zone_id is null
     and new.pickup_latitude is not null
     and new.pickup_longitude is not null then
    v_zone_id:=public.service_zone_id_for_point(
      new.pickup_latitude,new.pickup_longitude
    );
  end if;

  if v_zone_id is null and new.customer_id is not null then
    select last_zone_id into v_zone_id
    from public.users
    where id=new.customer_id;
  end if;

  if v_zone_id is not null then
    select currency_code,country_code
    into v_currency,v_country
    from public.service_zones
    where id=v_zone_id and active=true;

    if nullif(trim(coalesce(v_currency,'')),'') is not null then
      new.currency:=upper(trim(v_currency));
    end if;
    if nullif(trim(coalesce(v_country,'')),'') is not null then
      new.country_code:=upper(trim(v_country));
    end if;
  end if;

  if new.country_code is null then
    select z.country_code into v_country
    from public.service_zones z
    where upper(z.currency_code)=upper(new.currency)
      and z.country_code is not null
    order by z.zone_key
    limit 1;
    new.country_code:=v_country;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_set_delivery_currency_from_zone
on public.delivery_requests;
create trigger trg_set_delivery_currency_from_zone
before insert or update of
  pickup_latitude,pickup_longitude,marketplace_order_id,customer_id,currency
on public.delivery_requests
for each row execute function public.set_delivery_currency_from_zone();

revoke execute on function public.set_delivery_currency_from_zone()
from public,anon,authenticated;

-- Historical country tags.
update public.wallet_transactions wt
set country_code=coalesce(
  (
    select z.country_code
    from public.trips t
    join public.ride_requests rr on rr.id=t.ride_request_id
    join public.service_zones z on z.id=rr.zone_id
    where t.id=wt.trip_id
    limit 1
  ),
  (
    select d.country_code
    from public.delivery_requests d
    where d.id=wt.delivery_id
    limit 1
  ),
  (
    select z.country_code
    from public.wallet_accounts w
    join public.service_zones z
      on upper(z.currency_code)=upper(w.currency)
    where w.user_id=wt.user_id
      and z.country_code is not null
    order by z.zone_key
    limit 1
  )
)
where wt.country_code is null;

update public.payment_transactions p
set country_code=coalesce(
  (
    select z.country_code
    from public.trips t
    join public.ride_requests rr on rr.id=t.ride_request_id
    join public.service_zones z on z.id=rr.zone_id
    where t.id=p.trip_id
    limit 1
  ),
  (
    select d.country_code
    from public.delivery_requests d
    where d.id=p.delivery_id
    limit 1
  ),
  (
    select z.country_code
    from public.service_zones z
    where upper(z.currency_code)=upper(p.currency)
      and z.country_code is not null
    order by z.zone_key
    limit 1
  )
)
where p.country_code is null;

update public.wallet_topup_requests r
set country_code=(
  select z.country_code
  from public.service_zones z
  where upper(z.currency_code)=upper(r.currency)
    and z.country_code is not null
  order by z.zone_key
  limit 1
)
where r.country_code is null;

create or replace function public.current_operating_context()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_zone public.service_zones%rowtype;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;

  select z.* into v_zone
  from public.users u
  left join public.driver_profiles dp on dp.id=u.id
  join public.service_zones z
    on z.id=case
      when u.active_mode='driver' and dp.zone_id is not null then dp.zone_id
      else coalesce(u.last_zone_id,dp.zone_id)
    end
  where u.id=v_uid;

  if not found then
    return jsonb_build_object(
      'zone_id',null,
      'zone_key',null,
      'zone_name',null,
      'country',null,
      'country_code',null,
      'currency_code',null
    );
  end if;

  return jsonb_build_object(
    'zone_id',v_zone.id,
    'zone_key',v_zone.zone_key,
    'zone_name',v_zone.name,
    'country',v_zone.country,
    'country_code',v_zone.country_code,
    'currency_code',v_zone.currency_code
  );
end;
$function$;

revoke execute on function public.current_operating_context()
from public,anon;
grant execute on function public.current_operating_context()
to authenticated;

create or replace function public.ensure_country_wallet()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_context jsonb;
  v_country text;
  v_currency text;
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
    user_id,country_code,currency,balance
  )
  values(v_uid,v_country,v_currency,0)
  on conflict(user_id,country_code) do update set
    currency=excluded.currency,
    updated_at=case
      when public.wallet_country_accounts.currency is distinct from excluded.currency
      then now()
      else public.wallet_country_accounts.updated_at
    end;

  select * into v_wallet
  from public.wallet_country_accounts
  where user_id=v_uid and country_code=v_country;

  return to_jsonb(v_wallet)||jsonb_build_object(
    'country',v_context->>'country',
    'zone_id',v_context->>'zone_id',
    'zone_key',v_context->>'zone_key',
    'zone_name',v_context->>'zone_name'
  );
end;
$function$;

revoke execute on function public.ensure_country_wallet()
from public,anon;
grant execute on function public.ensure_country_wallet()
to authenticated;

create or replace function public.my_country_wallet_transactions()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_country text;
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
  );
end;
$function$;

create or replace function public.my_country_payments()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_country text;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';

  return (
    select coalesce(
      jsonb_agg(to_jsonb(p) order by p.created_at desc),
      '[]'::jsonb
    )
    from public.payment_transactions p
    where (p.payer_id=v_uid or p.payee_id=v_uid)
      and p.country_code=v_country
  );
end;
$function$;

create or replace function public.my_country_wallet_topups()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_country text;
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
  );
end;
$function$;

revoke execute on function public.my_country_wallet_transactions()
from public,anon;
revoke execute on function public.my_country_payments()
from public,anon;
revoke execute on function public.my_country_wallet_topups()
from public,anon;
grant execute on function public.my_country_wallet_transactions()
to authenticated;
grant execute on function public.my_country_payments()
to authenticated;
grant execute on function public.my_country_wallet_topups()
to authenticated;

create or replace function public.my_current_country_trips(
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_country text;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';

  return (
    select coalesce(
      jsonb_agg(x.payload order by x.created_at desc),
      '[]'::jsonb
    )
    from (
      select
        to_jsonb(t)||jsonb_build_object(
          'ride_requests',
          case when rr.id is null then null else to_jsonb(rr) end
        ) as payload,
        t.created_at
      from public.trips t
      join public.ride_requests rr on rr.id=t.ride_request_id
      left join public.service_zones z on z.id=rr.zone_id
      where (t.driver_id=v_uid or t.passenger_id=v_uid)
        and (
          z.country_code=v_country
          or (
            z.id is null
            and exists(
              select 1
              from public.service_zones cz
              where cz.country_code=v_country
                and upper(cz.currency_code)=upper(rr.currency)
            )
          )
        )
        and (p_from is null or t.created_at>=p_from)
        and (p_to is null or t.created_at<p_to)
      order by t.created_at desc
      limit case
        when p_limit is null or p_limit<1 then null
        else p_limit
      end
    ) x
  );
end;
$function$;

create or replace function public.my_current_country_deliveries(
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_country text;
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;
  v_country:=public.current_operating_context()->>'country_code';

  return (
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.created_at desc),
      '[]'::jsonb
    )
    from (
      select d.*
      from public.delivery_requests d
      where (d.customer_id=v_uid or d.courier_id=v_uid)
        and d.country_code=v_country
        and (p_from is null or d.created_at>=p_from)
        and (p_to is null or d.created_at<p_to)
      order by d.created_at desc
      limit case
        when p_limit is null or p_limit<1 then null
        else p_limit
      end
    ) x
  );
end;
$function$;

revoke execute on function public.my_current_country_trips(
  timestamptz,timestamptz,integer
) from public,anon;
revoke execute on function public.my_current_country_deliveries(
  timestamptz,timestamptz,integer
) from public,anon;
grant execute on function public.my_current_country_trips(
  timestamptz,timestamptz,integer
) to authenticated;
grant execute on function public.my_current_country_deliveries(
  timestamptz,timestamptz,integer
) to authenticated;

create or replace function public.set_wallet_transaction_country()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_country text;
begin
  if new.country_code is not null then
    new.country_code:=upper(trim(new.country_code));
    return new;
  end if;

  if new.trip_id is not null then
    select z.country_code into v_country
    from public.trips t
    join public.ride_requests rr on rr.id=t.ride_request_id
    join public.service_zones z on z.id=rr.zone_id
    where t.id=new.trip_id;
  end if;

  if v_country is null and new.delivery_id is not null then
    select d.country_code into v_country
    from public.delivery_requests d
    where d.id=new.delivery_id;
  end if;

  if v_country is null
     and new.reference like 'driver_subscription:%' then
    select z.country_code into v_country
    from public.driver_subscription_payments p
    join public.driver_subscription_plans pl on pl.id=p.plan_id
    join public.service_zones z on z.zone_key=pl.zone_key
    where p.id=nullif(split_part(new.reference,':',2),'')::bigint
    limit 1;
  end if;

  if v_country is null then
    select z.country_code into v_country
    from public.users u
    left join public.driver_profiles dp on dp.id=u.id
    join public.service_zones z
      on z.id=case
        when u.active_mode='driver' and dp.zone_id is not null then dp.zone_id
        else coalesce(u.last_zone_id,dp.zone_id)
      end
    where u.id=new.user_id;
  end if;

  new.country_code:=v_country;
  return new;
end;
$function$;

drop trigger if exists wallet_transactions_set_country
on public.wallet_transactions;
create trigger wallet_transactions_set_country
before insert or update of
  trip_id,delivery_id,reference,country_code
on public.wallet_transactions
for each row execute function public.set_wallet_transaction_country();

revoke execute on function public.set_wallet_transaction_country()
from public,anon,authenticated;

create or replace function public.apply_country_wallet_transaction()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_currency text;
begin
  if new.status<>'completed' or new.country_code is null then
    return new;
  end if;

  select z.currency_code into v_currency
  from public.service_zones z
  where z.country_code=new.country_code
  order by z.zone_key
  limit 1;

  if v_currency is null then return new; end if;

  insert into public.wallet_country_accounts(
    user_id,country_code,currency,balance
  )
  values(
    new.user_id,
    new.country_code,
    upper(v_currency),
    new.amount
  )
  on conflict(user_id,country_code) do update set
    balance=public.wallet_country_accounts.balance+excluded.balance,
    currency=excluded.currency,
    updated_at=now();

  return new;
end;
$function$;

drop trigger if exists wallet_transactions_apply_country_wallet
on public.wallet_transactions;
create trigger wallet_transactions_apply_country_wallet
after insert on public.wallet_transactions
for each row execute function public.apply_country_wallet_transaction();

revoke execute on function public.apply_country_wallet_transaction()
from public,anon,authenticated;

create or replace function public.set_payment_country()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_country text;
begin
  if new.country_code is not null then
    new.country_code:=upper(trim(new.country_code));
    return new;
  end if;

  if new.trip_id is not null then
    select z.country_code into v_country
    from public.trips t
    join public.ride_requests rr on rr.id=t.ride_request_id
    left join public.service_zones z on z.id=rr.zone_id
    where t.id=new.trip_id;
  end if;

  if v_country is null and new.delivery_id is not null then
    select d.country_code into v_country
    from public.delivery_requests d
    where d.id=new.delivery_id;
  end if;

  if v_country is null then
    select z.country_code into v_country
    from public.service_zones z
    where upper(z.currency_code)=upper(new.currency)
      and z.country_code is not null
    order by z.zone_key
    limit 1;
  end if;

  new.country_code:=v_country;
  return new;
end;
$function$;

drop trigger if exists payment_transactions_set_country
on public.payment_transactions;
create trigger payment_transactions_set_country
before insert or update of
  trip_id,delivery_id,currency,country_code
on public.payment_transactions
for each row execute function public.set_payment_country();

revoke execute on function public.set_payment_country()
from public,anon,authenticated;

create or replace function public.set_wallet_topup_context()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_zone public.service_zones%rowtype;
begin
  if new.country_code is null then
    select z.* into v_zone
    from public.users u
    left join public.driver_profiles dp on dp.id=u.id
    join public.service_zones z
      on z.id=case
        when u.active_mode='driver' and dp.zone_id is not null then dp.zone_id
        else coalesce(u.last_zone_id,dp.zone_id)
      end
    where u.id=new.user_id;

    if found then
      new.country_code:=v_zone.country_code;
      new.currency:=v_zone.currency_code;
    end if;
  else
    new.country_code:=upper(trim(new.country_code));
    if new.currency is null or trim(new.currency)='' then
      select z.currency_code into new.currency
      from public.service_zones z
      where z.country_code=new.country_code
      order by z.zone_key
      limit 1;
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists wallet_topup_requests_set_context
on public.wallet_topup_requests;
create trigger wallet_topup_requests_set_context
before insert or update of user_id,currency,country_code
on public.wallet_topup_requests
for each row execute function public.set_wallet_topup_context();

revoke execute on function public.set_wallet_topup_context()
from public,anon,authenticated;

create or replace function public.request_country_wallet_topup(
  p_amount numeric
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_context jsonb;
  v_id uuid;
  v_currency text;
  v_country text;
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
      and country_code=v_country
      and status='pending'
      and created_at>now()-interval '10 minutes'
  ) then
    raise exception 'Ya tienes una recarga pendiente reciente en este país';
  end if;

  insert into public.wallet_topup_requests(
    user_id,amount,currency,country_code
  )
  values(
    v_uid,round(p_amount,2),v_currency,v_country
  )
  returning id into v_id;

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
      'request_id',v_id
    )
  from public.admin_users a
  left join public.users u on u.id=v_uid;

  return v_id;
end;
$function$;

revoke execute on function public.request_country_wallet_topup(numeric)
from public,anon;
grant execute on function public.request_country_wallet_topup(numeric)
to authenticated;

create or replace function public.mirror_legacy_wallet_delta(
  p_user_id uuid,
  p_currency text,
  p_delta numeric
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_wallet public.wallet_accounts%rowtype;
begin
  if p_user_id is null
     or nullif(trim(coalesce(p_currency,'')),'') is null
     or p_delta is null
     or p_delta=0 then
    return;
  end if;

  select * into v_wallet
  from public.wallet_accounts
  where user_id=p_user_id
  for update;

  if not found then
    insert into public.wallet_accounts(
      user_id,balance,currency,updated_at
    )
    values(
      p_user_id,p_delta,upper(p_currency),now()
    );
    return;
  end if;

  if upper(v_wallet.currency)=upper(p_currency) then
    update public.wallet_accounts
    set balance=balance+p_delta,
        updated_at=now()
    where user_id=p_user_id;
  elsif coalesce(v_wallet.balance,0)=0 then
    update public.wallet_accounts
    set balance=p_delta,
        currency=upper(p_currency),
        updated_at=now()
    where user_id=p_user_id;
  end if;
  -- If a non-zero legacy wallet belongs to another currency, leave it intact.
end;
$function$;

revoke execute on function public.mirror_legacy_wallet_delta(
  uuid,text,numeric
) from public,anon,authenticated;

create or replace function public.admin_resolve_wallet_topup(
  p_request_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_req public.wallet_topup_requests%rowtype;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_status not in ('approved','rejected') then
    raise exception 'Estado inválido';
  end if;

  select * into v_req
  from public.wallet_topup_requests
  where id=p_request_id
  for update;

  if not found then raise exception 'Solicitud no encontrada'; end if;
  if v_req.status<>'pending' then
    raise exception 'La solicitud ya fue resuelta';
  end if;

  update public.wallet_topup_requests
  set status=p_status,
      resolved_at=now(),
      resolved_by=auth.uid()
  where id=p_request_id;

  if p_status='approved' then
    insert into public.wallet_transactions(
      user_id,amount,type,status,reference,country_code
    )
    values(
      v_req.user_id,
      v_req.amount,
      'topup',
      'completed',
      'Recarga aprobada',
      v_req.country_code
    );

    perform public.mirror_legacy_wallet_delta(
      v_req.user_id,
      v_req.currency,
      v_req.amount
    );

    insert into public.notifications(
      user_id,title,body,type,metadata
    )
    values(
      v_req.user_id,
      'Recarga aprobada',
      'Se acreditaron '||v_req.currency||' '||
        trim(to_char(v_req.amount,'FM999999990.00'))||
        ' a tu billetera.',
      'wallet_topup',
      jsonb_build_object(
        'country_code',v_req.country_code,
        'currency',v_req.currency
      )
    );
  else
    insert into public.notifications(
      user_id,title,body,type,metadata
    )
    values(
      v_req.user_id,
      'Recarga rechazada',
      'Tu solicitud de recarga no fue aprobada. Contacta a soporte si necesitas ayuda.',
      'wallet_topup',
      jsonb_build_object(
        'country_code',v_req.country_code,
        'currency',v_req.currency
      )
    );
  end if;
end;
$function$;

revoke execute on function public.admin_resolve_wallet_topup(uuid,text)
from public,anon;
grant execute on function public.admin_resolve_wallet_topup(uuid,text)
to authenticated,service_role;

create or replace function public.wallet_demo_topup(p_amount numeric)
returns numeric
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_wallet jsonb;
  v_country text;
  v_currency text;
  v_balance numeric;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if p_amount<=0 or p_amount>5000000 then
    raise exception 'Monto inválido';
  end if;

  v_wallet:=public.ensure_country_wallet();
  v_country:=v_wallet->>'country_code';
  v_currency:=v_wallet->>'currency';

  insert into public.wallet_transactions(
    user_id,amount,type,status,reference,country_code
  )
  values(
    v_uid,
    p_amount,
    'topup',
    'completed',
    'Recarga de prueba',
    v_country
  );

  perform public.mirror_legacy_wallet_delta(
    v_uid,v_currency,p_amount
  );

  select balance into v_balance
  from public.wallet_country_accounts
  where user_id=v_uid and country_code=v_country;

  return v_balance;
end;
$function$;

-- Country-safe settlement. The country wallet is authoritative; the old
-- single wallet is mirrored only when its currency matches, preventing
-- CLP and BOB from ever being mathematically mixed.
create or replace function public.settle_wallet_payment()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_balance numeric;
  v_commission_percent numeric:=0;
  v_commission numeric:=0;
  v_net numeric:=0;
  v_country text:=new.country_code;
begin
  select coalesce(s.commission_percent,0)
  into v_commission_percent
  from public.app_settings s
  limit 1;

  v_commission:=round(
    coalesce(new.amount,0)*v_commission_percent/100.0,
    2
  );
  v_net:=coalesce(new.amount,0)-v_commission;

  update public.payment_transactions
  set commission_percent=v_commission_percent,
      commission_amount=v_commission,
      driver_net_amount=case
        when new.payee_id is null then null
        else v_net
      end
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
        trip_id,delivery_id,country_code
      )
      values(
        new.payee_id,
        -v_commission,
        'commission',
        'completed',
        'Comisión Express por servicio en efectivo',
        new.trip_id,
        new.delivery_id,
        v_country
      );

      perform public.mirror_legacy_wallet_delta(
        new.payee_id,new.currency,-v_commission
      );
    end if;
    return new;
  end if;

  if new.method='wallet' and new.status='pending' then
    insert into public.wallet_country_accounts(
      user_id,country_code,currency,balance
    )
    values(
      new.payer_id,v_country,upper(new.currency),0
    )
    on conflict(user_id,country_code) do nothing;

    select balance into v_balance
    from public.wallet_country_accounts
    where user_id=new.payer_id
      and country_code=v_country
    for update;

    if coalesce(v_balance,0)<new.amount then
      insert into public.notifications(
        user_id,title,body,type,metadata
      )
      values(
        new.payer_id,
        'Saldo insuficiente',
        'Tu pago con Billetera Express quedó pendiente porque no tienes saldo suficiente.',
        'wallet_insufficient',
        jsonb_build_object(
          'country_code',v_country,
          'currency',new.currency
        )
      );
      return new;
    end if;

    insert into public.wallet_transactions(
      user_id,amount,type,status,reference,
      trip_id,delivery_id,country_code
    )
    values(
      new.payer_id,
      -new.amount,
      'payment',
      'completed',
      'Pago de servicio Express',
      new.trip_id,
      new.delivery_id,
      v_country
    );

    perform public.mirror_legacy_wallet_delta(
      new.payer_id,new.currency,-new.amount
    );

    insert into public.wallet_transactions(
      user_id,amount,type,status,reference,
      trip_id,delivery_id,country_code
    )
    values(
      new.payee_id,
      new.amount,
      'earning',
      'completed',
      'Ingreso bruto por servicio Express',
      new.trip_id,
      new.delivery_id,
      v_country
    );

    if v_commission>0 then
      insert into public.wallet_transactions(
        user_id,amount,type,status,reference,
        trip_id,delivery_id,country_code
      )
      values(
        new.payee_id,
        -v_commission,
        'commission',
        'completed',
        'Comisión Express',
        new.trip_id,
        new.delivery_id,
        v_country
      );
    end if;

    perform public.mirror_legacy_wallet_delta(
      new.payee_id,new.currency,v_net
    );

    update public.payment_transactions
    set status='paid',
        paid_at=now()
    where id=new.id;

    insert into public.notifications(
      user_id,title,body,type,metadata
    )
    values(
      new.payer_id,
      'Pago completado',
      'El pago con Billetera Express fue procesado correctamente.',
      'wallet_paid',
      jsonb_build_object(
        'country_code',v_country,
        'currency',new.currency
      )
    );

    insert into public.notifications(
      user_id,title,body,type,metadata
    )
    values(
      new.payee_id,
      'Ganancia acreditada',
      'El importe neto del servicio fue acreditado en tu Billetera Express.',
      'wallet_earning',
      jsonb_build_object(
        'country_code',v_country,
        'currency',new.currency
      )
    );
  end if;

  return new;
end;
$function$;

revoke execute on function public.settle_wallet_payment()
from public,anon,authenticated;
grant execute on function public.settle_wallet_payment()
to service_role;

-- Keep legacy ensure_wallet intact for the current Production binary. Preview
-- will use ensure_country_wallet. This is the rollback-safe compatibility seam.
