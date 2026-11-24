-- Driver challenge signup is explicit and checked against exclusivity/compatibility rules.
begin;
create table if not exists public.benefit_driver_challenge_enrollments(
  program_id uuid not null references public.benefit_programs(id),user_id uuid not null references public.users(id),
  channel text not null check(channel in ('preview','production')),zone_id uuid not null references public.service_zones(id),
  cycle_start timestamptz not null,enrolled_at timestamptz not null default now(),
  primary key(program_id,user_id,cycle_start)
);
create index if not exists benefit_driver_challenge_enrollments_user_idx
  on public.benefit_driver_challenge_enrollments(user_id,channel,zone_id,cycle_start);
alter table public.benefit_driver_challenge_enrollments enable row level security;
revoke all on public.benefit_driver_challenge_enrollments from public,anon,authenticated;

create or replace function public.benefit_challenge_cycle_start(p_program_id uuid,p_at timestamptz default now())
returns timestamptz language plpgsql stable security definer set search_path=public as $$
declare v_program public.benefit_programs%rowtype;v_period text;
begin
  select * into v_program from public.benefit_programs where id=p_program_id;
  if not found then return null; end if;
  v_period:=coalesce(v_program.config->>'period','weekly');
  return greatest(case when v_period='daily' then date_trunc('day',p_at)
    when v_period='monthly' then date_trunc('month',p_at)
    when v_period='weekly' then date_trunc('week',p_at)
    else coalesce(v_program.starts_at,date_trunc('week',p_at)) end,
    coalesce(v_program.starts_at,date_trunc('week',p_at)));
end $$;
revoke all on function public.benefit_challenge_cycle_start(uuid,timestamptz) from public,anon;
grant execute on function public.benefit_challenge_cycle_start(uuid,timestamptz) to authenticated;

create or replace function public.driver_join_benefit_challenge(p_program_id uuid,p_channel text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid();v_runtime jsonb;v_zone uuid;v_program public.benefit_programs%rowtype;
  v_cycle timestamptz;v_other record;v_compatible boolean;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false or v_runtime->>'environment' is distinct from p_channel
    or p_channel not in ('preview','production') then raise exception 'Entorno de datos no autorizado'; end if;
  -- Serialize a driver's enrollments so concurrent requests cannot bypass
  -- exclusive/compatible challenge rules.
  select dp.zone_id into v_zone from public.driver_profiles dp join public.service_zones z on z.id=dp.zone_id and z.active where dp.id=v_uid for update of dp;
  if v_zone is null then raise exception 'Solo conductores con zona activa pueden inscribirse'; end if;
  select * into v_program from public.benefit_programs p where p.id=p_program_id and p.channel=p_channel
    and p.state='active' and (p.zone_id=v_zone or p.config->>'zone_scope'='all')
    and (p.starts_at is null or p.starts_at<=now()) and (p.ends_at is null or p.ends_at>now())
    and p.program_type='driver_challenge' and coalesce(p.config->>'audience','drivers') in ('drivers','all')
  for update;
  if not found then raise exception 'Este reto no está disponible en tu zona o entorno'; end if;
  v_cycle:=public.benefit_challenge_cycle_start(v_program.id,now());
  for v_other in select e.program_id,p.config from public.benefit_driver_challenge_enrollments e
    join public.benefit_programs p on p.id=e.program_id where e.user_id=v_uid and e.channel=p_channel
      and e.cycle_start=public.benefit_challenge_cycle_start(e.program_id,now())
  loop
    if v_other.program_id=v_program.id then return jsonb_build_object('enrolled',true,'cycle_start',v_cycle); end if;
    if coalesce((v_program.config->>'exclusive')::boolean,false) or coalesce((v_other.config->>'exclusive')::boolean,false) then
      raise exception 'Este reto es exclusivo y no se puede combinar con otros retos';
    end if;
    v_compatible:=coalesce(v_program.config->'compatible_programs','[]'::jsonb) @> jsonb_build_array(v_other.program_id::text)
      or coalesce(v_other.config->'compatible_programs','[]'::jsonb) @> jsonb_build_array(v_program.id::text);
    if not v_compatible then raise exception 'Este reto no está configurado como compatible con tu inscripción actual'; end if;
  end loop;
  insert into public.benefit_driver_challenge_enrollments(program_id,user_id,channel,zone_id,cycle_start)
    values(v_program.id,v_uid,p_channel,v_zone,v_cycle) on conflict do nothing;
  return jsonb_build_object('enrolled',true,'cycle_start',v_cycle,'program_id',v_program.id);
end $$;
revoke all on function public.driver_join_benefit_challenge(uuid,text) from public,anon;
grant execute on function public.driver_join_benefit_challenge(uuid,text) to authenticated;

create or replace function public.my_benefits_overview(
  p_channel text default 'production'::text,
  p_role text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_runtime jsonb;
  v_zone uuid;
  v_currency text;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  v_runtime := public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean, false) = false
     or (v_runtime->>'environment') is distinct from p_channel
     or p_channel not in ('preview', 'production') then
    raise exception 'Entorno de datos no autorizado';
  end if;
  select z.id, z.currency_code into v_zone, v_currency
  from public.users u
  left join public.driver_profiles dp on dp.id = u.id
  join public.service_zones z on z.id = coalesce(u.last_zone_id, dp.zone_id)
  where u.id = v_uid and z.active;
  if v_zone is null then
    return jsonb_build_object('available', false, 'items', '[]'::jsonb, 'coupons', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'available', true,
    'currency', v_currency,
    'zone_id', v_zone,
    'items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'type', p.program_type,
        'name', p.name,
        'description', p.description,
        'config', p.config,
        'currency', v_currency,
        'starts_at', p.starts_at,
        'ends_at', p.ends_at,
        'challenge', case when p.program_type='driver_challenge' and p_role='driver' then jsonb_build_object(
          'cycle_start', public.benefit_challenge_cycle_start(p.id,now()),
          'goal', coalesce(nullif(p.config->>'trip_goal','')::integer,nullif(p.config->>'trip_threshold','')::integer,0),
          'enrolled', exists(select 1 from public.benefit_driver_challenge_enrollments e where e.program_id=p.id and e.user_id=v_uid and e.channel=p_channel and e.cycle_start=public.benefit_challenge_cycle_start(p.id,now())),
          'completed_trips',(select count(*) from public.trips t join public.ride_requests r on r.id=t.ride_request_id
            where t.driver_id=v_uid and t.channel=p_channel and t.status='completed' and t.payment_status='paid'
              and t.completed_at>=coalesce((select e.enrolled_at from public.benefit_driver_challenge_enrollments e
                where e.program_id=p.id and e.user_id=v_uid and e.channel=p_channel
                  and e.cycle_start=public.benefit_challenge_cycle_start(p.id,now())),public.benefit_challenge_cycle_start(p.id,now()))
              and t.completed_at<case when coalesce(p.config->>'period','weekly')='daily' then date_trunc('day',now())+interval '1 day'
                when coalesce(p.config->>'period','weekly')='monthly' then date_trunc('month',now())+interval '1 month'
                when coalesce(p.config->>'period','weekly')='weekly' then date_trunc('week',now())+interval '1 week'
                else coalesce(p.ends_at,public.benefit_challenge_cycle_start(p.id,now())+interval '1 month') end
              and (r.zone_id=v_zone or p.config->>'zone_scope'='all') and r.service_mode<>'parcel'
              and (coalesce(p.config->>'service_type','all') in ('all',r.category) or (p.config->>'service_type'='moto' and r.category in ('motorcycle','moto'))))
        ) else null end
      ) order by p.created_at desc), '[]'::jsonb)
      from public.benefit_programs p
      where (p.zone_id = v_zone or (p.program_type='driver_challenge' and p.config->>'zone_scope'='all'))
        and p.channel = p_channel
        and p.state = 'active'
        and (p.starts_at is null or p.starts_at <= now())
        and (p.ends_at is null or p.ends_at > now())
        and (p.program_type in ('coupon', 'activation', 'loyalty', 'referral')
             or (p.program_type = 'driver_challenge'
                 and exists (select 1 from public.driver_profiles dp where dp.id = v_uid)))
        and (
          p_role is null
          or coalesce(p.config->>'audience', 'all') in (
            'all',
            case when p_role = 'driver' then 'drivers' else 'passengers' end,
            case when p_role = 'passenger' then 'clients' else 'passengers' end
          )
        )
    ),
    'coupons', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id,
        'code', c.code,
        'name', p.name,
        'discount_type', c.discount_type,
        'value', c.value,
        'max_discount', c.max_discount,
        'currency', v_currency,
        'expires_at', c.expires_at,
        'state', c.state
      ) order by c.created_at desc), '[]'::jsonb)
      from public.benefit_user_coupons c
      join public.benefit_programs p on p.id = c.program_id
      where c.user_id = v_uid
        and c.zone_id = v_zone
        and c.channel = p_channel
        and c.state = 'available'
        and c.expires_at > now()
    ),
    'history', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb)
      from public.benefit_redemptions r
      where r.user_id = v_uid
        and r.zone_id = v_zone
        and r.channel = p_channel
    )
  );
end;
$function$;
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
      'uses',(select count(*) from public.benefit_redemptions r where r.program_id=p.id and r.benefit_type='ride_coupon' and r.state='approved')
        + (select count(*) from public.marketplace_coupon_redemptions r join public.marketplace_coupons c on c.id=r.coupon_id where c.benefit_program_id=p.id),
      'discount_total',(select coalesce(sum(r.amount),0) from public.benefit_redemptions r where r.program_id=p.id and r.benefit_type='ride_coupon' and r.state='approved')
        + (select coalesce(sum(r.discount_amount),0) from public.marketplace_coupon_redemptions r join public.marketplace_coupons c on c.id=r.coupon_id where c.benefit_program_id=p.id),
      'activations',(select count(*) from public.benefit_user_coupons c where c.program_id=p.id and c.source_type='activation')
        + (select count(*) from public.benefit_redemptions r where r.program_id=p.id and r.benefit_type='activation_wallet'),
      'participants',(select count(distinct c.user_id) from public.benefit_user_coupons c where c.program_id=p.id),
      'awards',(select count(*) from public.benefit_user_coupons c where c.program_id=p.id),
      'redeemed',(select count(*) from public.benefit_user_coupons c where c.program_id=p.id and c.state='redeemed'),
      'driver_credits',(select coalesce(sum(c.credit_count),0) from public.benefit_driver_trip_credits c where c.program_id=p.id),
      'challenge_participants',(select count(distinct e.user_id) from public.benefit_driver_challenge_enrollments e
        where e.program_id=p.id and e.cycle_start=public.benefit_challenge_cycle_start(p.id,now())),
      'challenge_awards',(select count(*) from public.benefit_driver_challenge_awards a
        where a.program_id=p.id and a.cycle_start=public.benefit_challenge_cycle_start(p.id,now())),
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
  v_enrolled_at timestamptz;
  v_award_id uuid;
  v_wallet_id uuid;
  v_free_trips integer:=0;
  v_daily_credits integer:=0;
  v_credit_cap integer:=2147483647;
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
        if v_grant.discount_type='percent' then v_discount:=round(v_fare*v_grant.value/100,2);
        else v_discount:=round(v_grant.value,2); end if;
        if v_grant.max_discount is not null then v_discount:=least(v_discount,v_grant.max_discount); end if;
        v_discount:=least(v_discount,v_fare);
      end if;
      v_due:=greatest(v_fare-v_discount,0);
    end if;
    update public.benefit_coupon_reservations set state='redeemed' where ride_request_id=v_request.id;
    if v_reservation.user_coupon_id is not null then
      update public.benefit_user_coupons set state='redeemed',redeemed_trip_id=v_trip.id where id=v_reservation.user_coupon_id;
    end if;
    perform set_config('app.benefit_coupon_write','on',true);
    update public.ride_requests set benefit_discount_amount=v_discount where id=v_request.id;
    insert into public.benefit_redemptions(program_id,channel,zone_id,user_id,trip_id,benefit_type,amount,currency_code,state,metadata)
    values(coalesce(v_reservation.program_id,v_grant.program_id),v_request.channel,v_request.zone_id,
      v_request.passenger_id,v_trip.id,'ride_coupon',v_discount,v_zone.currency_code,'approved',
      jsonb_build_object('fare',v_fare,'passenger_due',v_due,'driver_credit',v_discount,'code',v_request.benefit_coupon_code))
    on conflict(program_id,user_id,trip_id,benefit_type) do nothing;
    if found and v_discount>0 then
      insert into public.wallet_transactions(user_id,amount,type,status,reference,trip_id,country_code,channel)
      values(v_trip.driver_id,v_discount,'adjustment','completed',
        'benefit:coupon:'||v_trip.id::text,v_trip.id,v_zone.country_code,v_request.channel);
      if v_request.channel='production' then
        perform public.mirror_legacy_wallet_delta(v_trip.driver_id,v_zone.currency_code,v_discount);
      end if;
    end if;
  end if;
  update public.payment_transactions set amount=v_due,commission_percent=0,commission_amount=0,
    driver_net_amount=v_due where id=new.id;
  update public.trips set passenger_due_amount=v_due,promotion_credit_amount=v_discount where id=v_trip.id;

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
        from public.benefit_driver_trip_credits c where c.user_id=v_trip.driver_id and c.channel=v_request.channel
          and c.zone_id=v_request.zone_id and c.created_at>=date_trunc('day',now());
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
    select e.enrolled_at into v_enrolled_at from public.benefit_driver_challenge_enrollments e
      where e.program_id=v_program.id and e.user_id=v_trip.driver_id
        and e.channel=v_request.channel and e.cycle_start=v_cycle_start;
    if v_goal>0 and coalesce((v_config->>'value')::numeric,0)>0
       and v_enrolled_at is not null
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
           and t.payment_status='paid' and t.completed_at>=greatest(v_cycle_start,v_enrolled_at) and t.completed_at<v_cycle_end
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
commit;
