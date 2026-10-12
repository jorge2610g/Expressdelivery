-- Campeonato Express rewards: permanent receipts + one-time wallet credits.
-- Existing Preview demo campaigns remain NO-PAYOUT by default.
begin;

alter table public.driver_championships
 add column if not exists first_prize_amount numeric(14,2) not null default 0,
 add column if not exists second_prize_amount numeric(14,2) not null default 0,
 add column if not exists third_prize_amount numeric(14,2) not null default 0,
 add column if not exists auto_credit_enabled boolean not null default false,
 add column if not exists settled_at timestamptz,
 add column if not exists settlement_status text not null default 'pending',
 add column if not exists settlement_error text;
alter table public.driver_championships
 add constraint driver_championships_amounts_valid
 check (first_prize_amount>=0 and second_prize_amount>=0 and third_prize_amount>=0
   and (not auto_credit_enabled or (first_prize_amount>0
     and second_prize_amount>0 and third_prize_amount>0)));
alter table public.driver_championships
 add constraint driver_championships_settlement_status_valid
 check (settlement_status in ('pending','credited','no_eligible','disabled'));
create table if not exists public.driver_championship_rewards (
  id uuid primary key default gen_random_uuid(),
  championship_id uuid not null references public.driver_championships(id),
  channel text not null check(channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id),
  place int not null check(place between 1 and 3),
  driver_id uuid not null references public.users(id),
  driver_name text not null,
  rides integer not null check(rides>0),
  currency_code text not null,
  amount numeric(14,2) not null check(amount>0),
  wallet_transaction_id uuid not null unique references public.wallet_transactions(id),
  credited_at timestamptz not null default now(),
  unique(championship_id,place),
  unique(championship_id,driver_id)
);
create index if not exists driver_championship_rewards_driver
 on public.driver_championship_rewards(driver_id,channel,credited_at desc);
create unique index if not exists wallet_championship_credit_unique
 on public.wallet_transactions(user_id,channel,reference)
 where type='adjustment' and reference like 'campeonato_express:%';
alter table public.driver_championship_rewards enable row level security;
revoke all on public.driver_championship_rewards from public,anon,authenticated;

-- Prevent the prize or eligibility terms changing once the tournament starts
-- and forbid all edits after settlement. Automatic settlement only changes
-- status/settled_at and never modifies rewards or contest eligibility.
create or replace function public.guard_championship_awards_immutable()
returns trigger language plpgsql set search_path=public as $$
begin
 if old.settled_at is not null or old.state='closed' then
   raise exception 'Un campeonato cerrado o liquidado es inmutable';
 end if;
 if old.state='active' and now()>=old.starts_at and (
     new.zone_id is distinct from old.zone_id or
     new.channel is distinct from old.channel or
     new.service_key is distinct from old.service_key or
     new.starts_at is distinct from old.starts_at or
     new.ends_at is distinct from old.ends_at or
     new.first_prize_amount is distinct from old.first_prize_amount or
     new.second_prize_amount is distinct from old.second_prize_amount or
     new.third_prize_amount is distinct from old.third_prize_amount or
     new.auto_credit_enabled is distinct from old.auto_credit_enabled
   ) then
   raise exception 'No se pueden modificar reglas ni premios después del inicio';
 end if;
 if old.state='active' and new.state='closed' and old.ends_at>now() then
   raise exception 'El campeonato solo se cierra al finalizar su plazo';
 end if;
 return new;
end $$;
create trigger trg_guard_championship_awards_immutable
 before update on public.driver_championships
 for each row execute function public.guard_championship_awards_immutable();

-- Atomic creation/update; external amounts are numeric, never parsed from
-- free-form descriptive prize strings. Only an authorized super admin can
-- enable real credits for a new campaign.
create or replace function public.admin_driver_championship_save_v2(
 p_id uuid,p_zone_id uuid,p_channel text,p_service_key text,
 p_title text,p_starts_at timestamptz,p_ends_at timestamptz,p_state text,
 p_first_amount numeric,p_second_amount numeric,p_third_amount numeric,
 p_auto_credit boolean,p_rules text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_access jsonb:=public.admin_access_context();
 v_currency text;
 v_record public.driver_championships%rowtype;
begin
 if auth.uid() is null or not public.is_admin()
 or coalesce(v_access->>'role','')<>'super_admin'
 or p_channel not in ('preview','production')
 or not public.admin_environment_allowed(p_channel) then
   raise exception 'Solo superadministradores autorizados pueden crear premios';
 end if;
 if v_access->>'zone_id' is not null and
 (v_access->>'zone_id')::uuid<>p_zone_id then
   raise exception 'Zona administrativa no autorizada';
 end if;
 select currency_code into v_currency from public.service_zones
   where id=p_zone_id and active=true;
 if v_currency is null then raise exception 'Zona inexistente'; end if;
 if p_service_key is null or p_service_key not in ('*','economy','motorcycle','comfort','xl')
 or (p_service_key<>'*' and not exists(
     select 1 from public.zone_service_catalog
     where zone_id=p_zone_id and service_key=p_service_key
 )) then raise exception 'Servicio no disponible en esta ciudad'; end if;
 if p_state not in ('draft','active','closed')
 or length(trim(coalesce(p_title,''))) not between 4 and 100
 or p_starts_at is null or p_ends_at is null
 or p_ends_at<=p_starts_at or p_ends_at>p_starts_at+interval '366 days'
 or coalesce(p_first_amount,-1)<0 or coalesce(p_second_amount,-1)<0
 or coalesce(p_third_amount,-1)<0
 or greatest(p_first_amount,p_second_amount,p_third_amount)>10000000
 or (coalesce(p_auto_credit,false) and
     (p_first_amount<=0 or p_second_amount<=0 or p_third_amount<=0))
 or (v_currency='CLP' and
     (mod(p_first_amount,1)<>0 or mod(p_second_amount,1)<>0
      or mod(p_third_amount,1)<>0)) then
   raise exception 'Datos o importes de premios inválidos';
 end if;
 if p_state='active' and p_ends_at<=now() then
   raise exception 'No se puede activar un campeonato ya vencido';
 end if;
 -- Serialize concurrent admins at the city/channel level.
 perform pg_advisory_xact_lock(hashtextextended(p_channel||':'||p_zone_id::text,0));
 if p_state='active' and exists(
  select 1 from public.driver_championships c
  where c.channel=p_channel and c.zone_id=p_zone_id and c.state='active'
  and c.id is distinct from p_id
  and (c.service_key='*' or p_service_key='*' or c.service_key=p_service_key)
  and tstzrange(c.starts_at,c.ends_at,'[)') &&
    tstzrange(p_starts_at,p_ends_at,'[)')
 ) then raise exception 'Ya existe un campeonato activo en ese servicio y fecha'; end if;
 if p_id is not null and not exists(
    select 1 from public.driver_championships
    where id=p_id and channel=p_channel and zone_id=p_zone_id
 ) then raise exception 'Campeonato inexistente o sin autorización'; end if;
 insert into public.driver_championships(
    id,channel,zone_id,service_key,title,starts_at,ends_at,state,
    first_prize,second_prize,third_prize,
    first_prize_amount,second_prize_amount,third_prize_amount,
    auto_credit_enabled,rules
 ) values (
    coalesce(p_id,gen_random_uuid()),p_channel,p_zone_id,p_service_key,
    trim(p_title),p_starts_at,p_ends_at,p_state,
    v_currency||' '||p_first_amount::text,
    v_currency||' '||p_second_amount::text,
    v_currency||' '||p_third_amount::text,
    p_first_amount,p_second_amount,p_third_amount,
    coalesce(p_auto_credit,false),coalesce(p_rules,'')
 ) on conflict(id) do update set
    service_key=excluded.service_key,title=excluded.title,
    starts_at=excluded.starts_at,ends_at=excluded.ends_at,state=excluded.state,
    first_prize=excluded.first_prize,
    second_prize=excluded.second_prize,third_prize=excluded.third_prize,
    first_prize_amount=excluded.first_prize_amount,
    second_prize_amount=excluded.second_prize_amount,
    third_prize_amount=excluded.third_prize_amount,
    auto_credit_enabled=excluded.auto_credit_enabled,
    rules=excluded.rules,updated_at=now()
 returning * into v_record;
 perform public.admin_log_action('upsert','driver_championship',v_record.id::text,
   jsonb_build_object('channel',p_channel,'zone_id',p_zone_id,
     'state',p_state,'auto_credit_enabled',coalesce(p_auto_credit,false),
     'first_amount',p_first_amount,'second_amount',p_second_amount,
     'third_amount',p_third_amount,'currency',v_currency));
 return to_jsonb(v_record);
end $$;

revoke all on function public.admin_driver_championship_save_v2(uuid,uuid,text,text,text,timestamptz,timestamptz,text,numeric,numeric,numeric,boolean,text)
 from public,anon;
grant execute on function public.admin_driver_championship_save_v2(uuid,uuid,text,text,text,timestamptz,timestamptz,text,numeric,numeric,numeric,boolean,text)
 to authenticated;

-- Audit history for one city + runtime, no public wallet ledger access.
create or replace function public.admin_driver_championship_rewards(
 p_id uuid,p_zone_id uuid,p_channel text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_context jsonb:=public.admin_access_context();
begin
 if auth.uid() is null or not public.is_admin()
 or not public.admin_environment_allowed(p_channel)
 or (v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid<>p_zone_id)
 then raise exception 'No autorizado'; end if;
 if not exists(select 1 from public.driver_championships
     where id=p_id and zone_id=p_zone_id and channel=p_channel) then
   raise exception 'Campeonato no encontrado'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object(
   'position',r.place,'driver_name',r.driver_name,
   'rides',r.rides,'currency',r.currency_code,
   'amount',r.amount,'credited_at',r.credited_at,
   'receipt_id',r.id,'wallet_transaction_id',r.wallet_transaction_id
 ) order by r.place),'[]'::jsonb)
 from public.driver_championship_rewards r
 where r.championship_id=p_id and r.channel=p_channel and r.zone_id=p_zone_id);
end $$;
revoke all on function public.admin_driver_championship_rewards(uuid,uuid,text) from public,anon;
grant execute on function public.admin_driver_championship_rewards(uuid,uuid,text) to authenticated;

-- A conductor can inspect only his/her own historical credited prizes.
create or replace function public.my_championship_awards(
 p_channel text default 'production'
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_runtime jsonb;
begin
 if auth.uid() is null or not public.is_account_active() then
   raise exception 'No autorizado'; end if;
 v_runtime:=public.resolve_current_runtime_environment();
 if p_channel not in ('preview','production') or
    v_runtime->>'environment' is distinct from p_channel or
    coalesce((v_runtime->>'allowed')::boolean,false)=false then
   raise exception 'Entorno incorrecto'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object(
     'championship',c.title,'place',r.place,'amount',r.amount,
     'currency',r.currency_code,'credited_at',r.credited_at,
     'wallet_transaction_id',r.wallet_transaction_id
   ) order by r.credited_at desc),'[]'::jsonb)
 from public.driver_championship_rewards r
 join public.driver_championships c on c.id=r.championship_id
 where r.driver_id=auth.uid() and r.channel=p_channel);
end $$;
revoke all on function public.my_championship_awards(text) from public,anon;
grant execute on function public.my_championship_awards(text) to authenticated;

-- Trusted internal, scheduled settlement. The *same* eligibility criteria as
-- driver_championships_for_driver are used at close. No client can execute it.
-- A row lock, unique receipts and unique ledger references make it idempotent.
create or replace function public.settle_expired_driver_championships()
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 c public.driver_championships%rowtype;
 z public.service_zones%rowtype;
 winner record;
 v_amount numeric;
 v_wallet_tx uuid;
 v_rank int;
 v_count int;
 v_status text;
 v_done int:=0;
 v_failed int:=0;
begin
 for c in select * from public.driver_championships
  where state='active' and ends_at<=now() and settled_at is null
  order by ends_at,id for update skip locked
 loop
  begin
   select * into strict z from public.service_zones where id=c.zone_id;
   v_count:=0;
   if c.auto_credit_enabled then
     -- Verify completeness and currency before touching any wallet.
     if c.first_prize_amount<=0 or c.second_prize_amount<=0 or c.third_prize_amount<=0
       or z.currency_code not in ('BOB','CLP') then
       raise exception 'Premios o moneda no aptos para abono';
     end if;
     for winner in
       with eligible as(
         select dp.id,coalesce(u.full_name,'Conductor') full_name
         from public.driver_profiles dp
         join public.users u on u.id=dp.id and u.account_status='active'
         join public.account_runtime_bindings arb
           on arb.user_id=dp.id and arb.environment=c.channel
         where dp.zone_id=c.zone_id and dp.approval_status='approved'
           and (c.channel<>'preview' or exists(
             select 1 from public.audit_test_group_members mem
             join public.audit_test_groups grp on grp.id=mem.group_id
             where mem.user_id=dp.id and mem.enabled and grp.active
           ))
       ),counts as(
         select e.id,e.full_name,count(t.id)::integer as rides
         from eligible e left join public.trips t on t.driver_id=e.id
           and t.status='completed' and t.channel=c.channel
           and t.completed_at>=c.starts_at and t.completed_at<c.ends_at
           and exists(select 1 from public.ride_requests r
             where r.id=t.ride_request_id and r.channel=c.channel
               and r.zone_id=c.zone_id
               and (c.service_key='*' or r.category=c.service_key))
         group by e.id,e.full_name
       ),ranking as(
         select id,full_name,rides,
         row_number() over(order by rides desc,full_name asc,id) place
         from counts where rides>0
       )select * from ranking where place<=3 order by place
     loop
       v_rank:=winner.place;
       v_amount:=case v_rank when 1 then c.first_prize_amount
         when 2 then c.second_prize_amount else c.third_prize_amount end;
       -- No manual balance writes. The ledger's AFTER INSERT trigger updates
       -- wallet_country_accounts scoped by user, country AND channel.
       insert into public.wallet_transactions(
         user_id,amount,type,status,reference,country_code,channel
       )values(
         winner.id,v_amount,'adjustment','completed',
         'campeonato_express:'||c.id::text||':puesto_'||v_rank::text,
         z.country_code,c.channel
       ) returning id into v_wallet_tx;
       if c.channel='production' then
         perform public.mirror_legacy_wallet_delta(winner.id,z.currency_code,v_amount);
       end if;
       insert into public.driver_championship_rewards(
         championship_id,channel,zone_id,place,driver_id,driver_name,
         rides,currency_code,amount,wallet_transaction_id
       )values(c.id,c.channel,c.zone_id,v_rank,winner.id,winner.full_name,
         winner.rides,z.currency_code,v_amount,v_wallet_tx);
       insert into public.notifications(user_id,title,body,type,metadata,channel)
       values(winner.id,'¡Premio de Campeonato Express!',
         'Terminaste en el puesto '||v_rank||' de '||c.title||
         '. Recibiste '||z.currency_code||' '||v_amount||' en tu billetera.',
         'championship_reward',
         jsonb_build_object('championship_id',c.id,'place',v_rank,
           'amount',v_amount,'currency',z.currency_code,
           'wallet_transaction_id',v_wallet_tx),
         c.channel);
       v_count:=v_count+1;
     end loop;
   end if;
   v_status:=case
     when not c.auto_credit_enabled then 'disabled'
     when v_count=0 then 'no_eligible' else 'credited' end;
   update public.driver_championships
   set state='closed',settled_at=now(),settlement_status=v_status,
       settlement_error=null,updated_at=now()
   where id=c.id;
   v_done:=v_done+1;
  exception when others then
   -- Each tournament is an atomic subtransaction: failed transfers roll
   -- back ALL wallet credits of that tournament, and remain retryable.
   update public.driver_championships set settlement_error=left(sqlerrm,500),
      updated_at=now() where id=c.id;
   v_failed:=v_failed+1;
  end;
 end loop;
 return jsonb_build_object('settled',v_done,'retry_pending',v_failed);
end $$;

revoke all on function public.settle_expired_driver_championships()
 from public,anon,authenticated;

-- pg_cron executes as the SQL owner, not as any driver/admin token.
-- Every 10 min; no per-device polling, wallet payout is database-atomic.
select cron.schedule('express-championship-settlement',
  '*/10 * * * *',
  'select public.settle_expired_driver_championships()');

commit;