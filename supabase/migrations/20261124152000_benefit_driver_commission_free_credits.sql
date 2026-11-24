-- Supports the commission-free credit options configured for loyalty and challenges.
begin;
alter table public.benefit_driver_challenge_awards add column if not exists reward_type text not null default 'wallet' check(reward_type in ('wallet','commission_free'));
alter table public.benefit_driver_challenge_awards add column if not exists commission_free_trips integer not null default 0 check(commission_free_trips>=0);
alter table public.benefit_driver_challenge_awards drop constraint if exists benefit_driver_challenge_awards_amount_check;
alter table public.benefit_driver_challenge_awards add constraint benefit_driver_challenge_awards_amount_check check(amount>=0);
create table if not exists public.benefit_driver_trip_credits(
  id uuid primary key default gen_random_uuid(),program_id uuid not null references public.benefit_programs(id),
  user_id uuid not null references public.users(id),channel text not null check(channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id),credit_count integer not null check(credit_count>0),
  remaining_count integer not null check(remaining_count>=0 and remaining_count<=credit_count),
  valid_from timestamptz not null default now(),expires_at timestamptz not null,
  source_trip_id uuid references public.trips(id),created_at timestamptz not null default now()
);
create index if not exists benefit_driver_trip_credits_available_idx on public.benefit_driver_trip_credits(user_id,channel,zone_id,valid_from,expires_at) where remaining_count>0;
alter table public.benefit_driver_trip_credits enable row level security;
revoke all on public.benefit_driver_trip_credits from public,anon,authenticated;

create or replace function public.admin_benefit_program_list(
  p_zone_id uuid,p_channel text,p_type text default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_context jsonb;
begin
  if auth.uid() is null or not public.is_admin()
    or p_channel not in ('preview','production') or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso a beneficios no autorizado';
  end if;
  v_context:=public.admin_access_context();
  if coalesce(v_context->>'role','') not in ('super_admin','zone_monitor') then
    raise exception 'El módulo de beneficios requiere rol administrativo central';
  end if;
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid<>p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('config',p.config||jsonb_build_object(
      'uses',(select count(*) from public.benefit_redemptions r where r.program_id=p.id and r.benefit_type='ride_coupon' and r.state='approved'),
      'discount_total',(select coalesce(sum(r.amount),0) from public.benefit_redemptions r where r.program_id=p.id and r.benefit_type='ride_coupon' and r.state='approved'),
      'activations',(select count(*) from public.benefit_user_coupons c where c.program_id=p.id and c.source_type='activation'),
      'participants',(select count(distinct c.user_id) from public.benefit_user_coupons c where c.program_id=p.id),
      'awards',(select count(*) from public.benefit_user_coupons c where c.program_id=p.id),
      'redeemed',(select count(*) from public.benefit_user_coupons c where c.program_id=p.id and c.state='redeemed'),
      'driver_credits',(select coalesce(sum(c.credit_count),0) from public.benefit_driver_trip_credits c where c.program_id=p.id),
      'challenge_participants',(select count(distinct a.user_id) from public.benefit_driver_challenge_awards a where a.program_id=p.id),
      'challenge_awards',(select count(*) from public.benefit_driver_challenge_awards a where a.program_id=p.id),
      'challenge_credits',(select coalesce(sum(a.amount),0) from public.benefit_driver_challenge_awards a where a.program_id=p.id)
        + (select coalesce(sum(c.credit_count),0) from public.benefit_driver_trip_credits c where c.program_id=p.id),
      'referrals',(select count(*) from public.benefit_referral_links l where l.program_id=p.id),
      'pending_referrals',(select count(*) from public.benefit_referral_links l where l.program_id=p.id and l.state='pending'),
      'activated_referrals',(select count(*) from public.benefit_referral_links l where l.program_id=p.id and l.state='qualified'),
      'referral_conversion',(select case when count(*)=0 then 0 else round(100.0*count(*) filter(where l.state='qualified')/count(*),1) end from public.benefit_referral_links l where l.program_id=p.id)
    )) order by p.created_at desc),'[]'::jsonb)
    from public.benefit_programs p where p.zone_id=p_zone_id and p.channel=p_channel
      and (p_type is null or p.program_type=p_type));
end $$;
create or replace function public.settle_trip_benefits_for_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trip public.trips%rowtype;
  v_request public.ride_requests%rowtype;
  v_zone public.service_zones%rowtype;
  v_reservation public.benefit_coupon_reservations%rowtype;
  v_program public.benefit_programs%rowtype;
  v_grant public.benefit_user_coupons%rowtype;
  v_fare numeric(12,2);
  v_discount numeric(12,2):=0;
  v_due numeric(12,2);
  v_config jsonb;
  v_trip_count integer;
  v_threshold integer;
  v_award_count integer;
  v_goal integer;
  v_period text;
  v_cycle_start timestamptz;
  v_cycle_end timestamptz;
  v_award_id uuid;
  v_wallet_id uuid;
  v_free_trips integer:=0;
  v_daily_credits integer:=0;
  v_credit_cap integer:=2147483647;
  v_absorber text:='company';
  v_company_credit numeric(12,2):=0;
begin
  v_award_id:=null;
  if tg_op='UPDATE' then
    if old.status='paid' then return new; end if;
  end if;
  if new.status<>'paid' or new.trip_id is null then return new; end if;
  select * into v_trip from public.trips where id=new.trip_id for update;
  if not found or v_trip.status<>'completed' or v_trip.payment_status<>'paid' then return new; end if;
  select * into v_request from public.ride_requests where id=v_trip.ride_request_id for update;
  if not found or v_request.service_mode='parcel' then return new; end if;
  if new.method not in ('cash','driver_qr','wallet') then return new; end if;
  select * into v_zone from public.service_zones where id=v_request.zone_id;
  if not found then return new; end if;
  v_fare:=round(greatest(coalesce(v_trip.final_fare,0),0),2);
  v_due:=v_fare;
  select * into v_reservation from public.benefit_coupon_reservations
    where ride_request_id=v_request.id and state='reserved' for update;
  if found then
    if v_request.benefit_original_fare is not null then
      v_discount:=least(greatest(coalesce(v_request.benefit_discount_amount,0),0),v_fare);
      v_due:=v_fare;
    else
      if v_reservation.program_id is not null then
        select * into v_program from public.benefit_programs where id=v_reservation.program_id for update;
        v_config:=v_program.config;
        v_absorber:=coalesce(v_config->>'discount_absorber','company');
        if v_config->>'discount_type'='percent' then
          v_discount:=round(v_fare*coalesce((v_config->>'value')::numeric,0)/100,2);
        else
          v_discount:=round(coalesce((v_config->>'value')::numeric,0),2);
        end if;
        if nullif(v_config->>'max_discount','') is not null then
          v_discount:=least(v_discount,(v_config->>'max_discount')::numeric);
        end if;
        v_discount:=least(v_discount,v_fare);
      else
        select * into v_grant from public.benefit_user_coupons where id=v_reservation.user_coupon_id for update;
        select coalesce(p.config->>'discount_absorber','company') into v_absorber from public.benefit_programs p where p.id=v_grant.program_id;
        v_absorber:=coalesce(v_absorber,'company');
        if v_grant.discount_type='percent' then v_discount:=round(v_fare*v_grant.value/100,2);
        else v_discount:=round(v_grant.value,2); end if;
        if v_grant.max_discount is not null then v_discount:=least(v_discount,v_grant.max_discount); end if;
        v_discount:=least(v_discount,v_fare);
      end if;
      v_due:=greatest(v_fare-v_discount,0);
    end if;
    v_company_credit:=case v_absorber when 'driver' then 0 when 'split' then round(v_discount/2,2) else v_discount end;
    update public.benefit_coupon_reservations set state='redeemed' where ride_request_id=v_request.id;
    if v_reservation.user_coupon_id is not null then
      update public.benefit_user_coupons set state='redeemed',redeemed_trip_id=v_trip.id where id=v_reservation.user_coupon_id;
    end if;
    perform set_config('app.benefit_coupon_write','on',true);
    update public.ride_requests set benefit_discount_amount=v_discount where id=v_request.id;
    insert into public.benefit_redemptions(program_id,channel,zone_id,user_id,trip_id,benefit_type,amount,currency_code,state,metadata)
    values(coalesce(v_reservation.program_id,v_grant.program_id),v_request.channel,v_request.zone_id,
      v_request.passenger_id,v_trip.id,'ride_coupon',v_discount,v_zone.currency_code,'approved',
      jsonb_build_object('fare',v_fare,'passenger_due',v_due,'driver_credit',v_company_credit,
        'driver_absorbed',greatest(v_discount-v_company_credit,0),'discount_absorber',v_absorber,'code',v_request.benefit_coupon_code))
    on conflict(program_id,user_id,trip_id,benefit_type) do nothing;
    if found and v_company_credit>0 then
      insert into public.wallet_transactions(user_id,amount,type,status,reference,trip_id,country_code,channel)
      values(v_trip.driver_id,v_company_credit,'adjustment','completed',
        'benefit:coupon:'||v_trip.id::text,v_trip.id,v_zone.country_code,v_request.channel);
      if v_request.channel='production' then
        perform public.mirror_legacy_wallet_delta(v_trip.driver_id,v_zone.currency_code,v_company_credit);
      end if;
    end if;
  end if;
  update public.payment_transactions set amount=v_due,commission_percent=0,commission_amount=0,
    driver_net_amount=v_due where id=new.id;
  update public.trips set passenger_due_amount=v_due,promotion_credit_amount=v_company_credit where id=v_trip.id;

  -- Activation rewards issue a personal, non-cash coupon after the passenger's first paid ride.
  perform 1 from public.users where id=v_request.passenger_id for update;
  select count(*)::integer into v_trip_count from public.trips t
    where t.passenger_id=v_request.passenger_id and t.channel=v_request.channel
      and t.status='completed' and t.payment_status='paid'
      and exists(select 1 from public.ride_requests r where r.id=t.ride_request_id and r.service_mode<>'parcel');
  if v_trip_count=1 then
    for v_program in select * from public.benefit_programs p
      where p.zone_id=v_request.zone_id and p.channel=v_request.channel
        and p.program_type='activation' and p.state='active'
        and p.config->>'trigger_type'='first_trip'
        and (p.starts_at is null or p.starts_at<=now()) and (p.ends_at is null or p.ends_at>now())
      for update
    loop
      v_config:=v_program.config;
      if coalesce(nullif(v_config->>'max_activations','')::integer,2147483647)>
        (select count(*) from public.benefit_user_coupons where program_id=v_program.id)
        + (select count(*) from public.benefit_redemptions r where r.program_id=v_program.id and r.benefit_type='activation_wallet') then
        if v_config->>'reward_destination'='wallet' then
          v_discount:=case when v_config->>'reward_type'='percent'
            then round(v_fare*coalesce((v_config->>'value')::numeric,0)/100,2)
            else coalesce((v_config->>'value')::numeric,0) end;
          v_discount:=least(v_discount,v_fare);
          insert into public.benefit_redemptions(program_id,channel,zone_id,user_id,trip_id,benefit_type,amount,currency_code,state,metadata)
          values(v_program.id,v_request.channel,v_request.zone_id,v_request.passenger_id,v_trip.id,
            'activation_wallet',v_discount,v_zone.currency_code,'approved',jsonb_build_object('destination','wallet'))
          on conflict(program_id,user_id,trip_id,benefit_type) do nothing;
          if found and v_discount>0 then
            insert into public.wallet_transactions(user_id,amount,type,status,reference,trip_id,country_code,channel)
            values(v_request.passenger_id,v_discount,'adjustment','completed',
              'benefit:activation:'||v_program.id::text||':'||v_trip.id::text,v_trip.id,v_zone.country_code,v_request.channel);
            if v_request.channel='production' then
              perform public.mirror_legacy_wallet_delta(v_request.passenger_id,v_zone.currency_code,v_discount);
            end if;
          end if;
        elsif v_config->>'reward_type'='percent' then
          perform public.issue_benefit_user_coupon(v_program.id,v_request.passenger_id,v_trip.id,
            v_request.channel,v_request.zone_id,'activation','percent',(v_config->>'value')::numeric,
            nullif(v_config->>'max_discount','')::numeric);
        elsif v_config->>'reward_type'='fixed' then
          perform public.issue_benefit_user_coupon(v_program.id,v_request.passenger_id,v_trip.id,
            v_request.channel,v_request.zone_id,'activation','fixed',(v_config->>'value')::numeric,null);
        else
          perform public.issue_benefit_user_coupon(v_program.id,v_request.passenger_id,v_trip.id,
            v_request.channel,v_request.zone_id,'activation','percent',100,
            nullif(v_config->>'free_trip_cap','')::numeric);
        end if;
      end if;
    end loop;
  end if;

  -- Every Nth paid ride earns a one-use coupon for the passenger's next ride.
  for v_program in select * from public.benefit_programs p
    where p.zone_id=v_request.zone_id and p.channel=v_request.channel
      and p.program_type='loyalty' and p.state='active'
      and (p.starts_at is null or p.starts_at<=now()) and (p.ends_at is null or p.ends_at>now())
    for update
  loop
    v_config:=v_program.config;
    v_threshold:=coalesce(nullif(v_config->>'trip_threshold','')::integer,0);
    select count(*)::integer into v_award_count from public.benefit_user_coupons c where c.program_id=v_program.id;
    if v_threshold>0 and v_trip_count%v_threshold=0
       and v_award_count<coalesce(nullif(v_config->>'max_total_rewards','')::integer,2147483647)
       and (select count(*) from public.benefit_user_coupons c where c.program_id=v_program.id and c.user_id=v_request.passenger_id)
          <coalesce(nullif(v_config->>'max_rewards_per_customer','')::integer,2147483647) then
      perform public.issue_benefit_user_coupon(v_program.id,v_request.passenger_id,v_trip.id,
        v_request.channel,v_request.zone_id,'loyalty','percent',100,
        nullif(v_config->>'free_trip_cap','')::numeric);
      v_free_trips:=coalesce(nullif(v_config->>'driver_no_commission_trips','')::integer,0);
      if v_free_trips>0 then
        select coalesce(sum(c.credit_count),0)::integer into v_daily_credits
        from public.benefit_driver_trip_credits c where c.program_id=v_program.id and c.user_id=v_trip.driver_id
          and c.channel=v_request.channel and c.zone_id=v_request.zone_id and c.created_at>=date_trunc('day',now());
        v_credit_cap:=coalesce(nullif(v_config->>'max_credits_per_driver_day','')::integer,2147483647);
        v_free_trips:=greatest(least(v_free_trips,v_credit_cap-v_daily_credits),0);
        if v_free_trips>0 then
          insert into public.benefit_driver_trip_credits(program_id,user_id,channel,zone_id,credit_count,remaining_count,valid_from,expires_at,source_trip_id)
          values(v_program.id,v_trip.driver_id,v_request.channel,v_request.zone_id,v_free_trips,v_free_trips,
            case when coalesce((v_config->>'commission_start_same_day')::boolean,false) then now() else date_trunc('day',now())+interval '1 day' end,
            case when coalesce((v_config->>'commission_start_same_day')::boolean,false) then date_trunc('day',now())+interval '1 day' else date_trunc('day',now())+interval '2 days' end,v_trip.id);
        end if;
      end if;
    end if;
  end loop;

  -- Driver challenge bonuses are internal-wallet credits, capped to one award per cycle.
  for v_program in select * from public.benefit_programs p
    where (p.zone_id=v_request.zone_id or p.config->>'zone_scope'='all') and p.channel=v_request.channel
      and p.program_type='driver_challenge' and p.state='active'
      and (p.starts_at is null or p.starts_at<=now()) and (p.ends_at is null or p.ends_at>now())
    for update
  loop
    v_config:=v_program.config;
    v_goal:=coalesce(nullif(v_config->>'trip_goal','')::integer,nullif(v_config->>'trip_threshold','')::integer,0);
    v_period:=coalesce(v_config->>'period','weekly');
    v_cycle_start:=greatest(
      case when v_period='daily' then date_trunc('day',now())
        when v_period='monthly' then date_trunc('month',now())
        when v_period='weekly' then date_trunc('week',now())
        else coalesce(v_program.starts_at,date_trunc('week',now())) end,
      coalesce(v_program.starts_at,date_trunc('week',now()))
    );
    v_cycle_end:=least(
      case when v_period='daily' then date_trunc('day',now())+interval '1 day'
        when v_period='monthly' then date_trunc('month',now())+interval '1 month'
        when v_period='weekly' then date_trunc('week',now())+interval '1 week'
        else coalesce(v_program.ends_at,v_cycle_start+interval '1 month') end,
      coalesce(v_program.ends_at,'infinity'::timestamptz)
    );
    if v_goal>0 and coalesce((v_config->>'value')::numeric,0)>0
       and v_cycle_start>=coalesce(v_program.starts_at,v_cycle_start)
       and (v_program.ends_at is null or v_cycle_start<v_program.ends_at)
       and (coalesce(v_config->>'service_type','all') in ('all',v_request.category))
       and (select count(*) from public.benefit_driver_challenge_awards a where a.program_id=v_program.id)
          <coalesce(nullif(v_config->>'max_total_rewards','')::integer,2147483647)
       and (select count(*) from public.benefit_driver_challenge_awards a
          where a.program_id=v_program.id and a.user_id=v_trip.driver_id)
          <coalesce(nullif(v_config->>'max_rewards_per_customer','')::integer,2147483647)
       and (select count(*) from public.trips t join public.ride_requests r on r.id=t.ride_request_id
         where t.driver_id=v_trip.driver_id and t.channel=v_request.channel and t.status='completed'
           and t.payment_status='paid' and t.completed_at>=v_cycle_start and t.completed_at<v_cycle_end
           and (r.zone_id=v_request.zone_id or v_config->>'zone_scope'='all') and r.service_mode<>'parcel'
           and (coalesce(v_config->>'service_type','all') in ('all',r.category)
             or (v_config->>'service_type'='moto' and r.category in ('motorcycle','moto'))))>=v_goal
    then
      v_free_trips:=case when v_config->>'reward_type'='commission_free'
        then coalesce(nullif(v_config->>'commission_free_trips','')::integer,0) else 0 end;
      insert into public.benefit_driver_challenge_awards(program_id,user_id,cycle_start,trip_id,channel,zone_id,amount,currency_code,reward_type,commission_free_trips)
      values(v_program.id,v_trip.driver_id,v_cycle_start,v_trip.id,v_request.channel,v_request.zone_id,
        case when v_free_trips>0 then 0 else (v_config->>'value')::numeric end,v_zone.currency_code,
        case when v_free_trips>0 then 'commission_free' else 'wallet' end,v_free_trips)
      on conflict(program_id,user_id,cycle_start) do nothing
      returning trip_id into v_award_id;
      if v_award_id is not null and v_free_trips>0 then
        insert into public.benefit_driver_trip_credits(program_id,user_id,channel,zone_id,credit_count,remaining_count,valid_from,expires_at,source_trip_id)
        values(v_program.id,v_trip.driver_id,v_request.channel,v_request.zone_id,v_free_trips,v_free_trips,now(),
          coalesce(v_program.ends_at,now()+interval '90 days'),v_trip.id);
      elsif v_award_id is not null then
        insert into public.wallet_transactions(user_id,amount,type,status,reference,trip_id,country_code,channel)
        values(v_trip.driver_id,(v_config->>'value')::numeric,'adjustment','completed',
          'benefit:challenge:'||v_program.id::text||':'||v_cycle_start::date::text,v_trip.id,v_zone.country_code,v_request.channel)
        returning id into v_wallet_id;
        update public.benefit_driver_challenge_awards set wallet_transaction_id=v_wallet_id
          where program_id=v_program.id and user_id=v_trip.driver_id and cycle_start=v_cycle_start;
        if v_request.channel='production' then
          perform public.mirror_legacy_wallet_delta(v_trip.driver_id,v_zone.currency_code,(v_config->>'value')::numeric);
        end if;
      end if;
    end if;
  end loop;
  return new;
end $$;

create or replace function public.consume_benefit_driver_trip_credit()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_trip public.trips%rowtype; v_zone_id uuid; v_service_mode text; v_credit public.benefit_driver_trip_credits%rowtype;
begin
  if new.status<>'paid' or new.trip_id is null or (tg_op='UPDATE' and old.status='paid') then return new; end if;
  select * into v_trip from public.trips where id=new.trip_id;
  if not found or v_trip.driver_id is null then return new; end if;
  select zone_id,service_mode into v_zone_id,v_service_mode from public.ride_requests where id=v_trip.ride_request_id and channel=new.channel;
  if v_zone_id is null or v_service_mode='parcel' then return new; end if;
  select * into v_credit from public.benefit_driver_trip_credits c
    where c.user_id=v_trip.driver_id and c.channel=new.channel and c.zone_id=v_zone_id
      and c.remaining_count>0 and c.valid_from<=now() and c.expires_at>now()
    order by c.valid_from,c.created_at for update skip locked limit 1;
  if found then
    update public.benefit_driver_trip_credits set remaining_count=remaining_count-1 where id=v_credit.id;
    new.commission_percent:=0; new.commission_amount:=0; new.driver_net_amount:=coalesce(new.amount,0);
  end if;
  return new;
end $$;
drop trigger if exists benefit_driver_trip_credit_consume on public.payment_transactions;
create trigger benefit_driver_trip_credit_consume before insert or update of status on public.payment_transactions
for each row execute function public.consume_benefit_driver_trip_credit();
revoke all on function public.consume_benefit_driver_trip_credit() from public,anon,authenticated;
commit;
