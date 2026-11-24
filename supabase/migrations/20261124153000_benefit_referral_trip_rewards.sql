-- Supports multi-country driver referrals, trip-based MLM, and the referral form shown in Adminexpress.
begin;
create table if not exists public.benefit_trip_referral_commissions(
  id uuid primary key default gen_random_uuid(),program_id uuid not null references public.benefit_programs(id),
  referral_id uuid not null references public.benefit_referral_links(id),trip_id uuid not null references public.trips(id),
  referrer_id uuid not null references public.users(id),referred_driver_id uuid not null references public.users(id),
  channel text not null check(channel in ('preview','production')),zone_id uuid not null references public.service_zones(id),
  commission_base numeric(12,2) not null check(commission_base>=0),commission_percent numeric(7,4) not null check(commission_percent between 0 and 100),
  commission_amount numeric(12,2) not null check(commission_amount>=0),wallet_transaction_id uuid references public.wallet_transactions(id),
  created_at timestamptz not null default now(),unique(program_id,trip_id,referral_id)
);
alter table public.benefit_trip_referral_commissions enable row level security;
revoke all on public.benefit_trip_referral_commissions from public,anon,authenticated;
create table if not exists public.benefit_driver_referral_rewards(
  id uuid primary key default gen_random_uuid(),program_id uuid not null references public.benefit_programs(id),
  referral_id uuid not null references public.benefit_referral_links(id),trigger_trip_id uuid not null references public.trips(id),
  beneficiary_id uuid not null references public.users(id),beneficiary_role text not null check(beneficiary_role in ('referrer','referred')),
  channel text not null check(channel in ('preview','production')),zone_id uuid not null references public.service_zones(id),
  amount numeric(12,2) not null check(amount>0),currency_code text not null,wallet_transaction_id uuid references public.wallet_transactions(id),
  created_at timestamptz not null default now(),unique(referral_id,beneficiary_role)
);
alter table public.benefit_driver_referral_rewards enable row level security;
revoke all on public.benefit_driver_referral_rewards from public,anon,authenticated;
create or replace function public.admin_driver_referral_dashboard(
  p_zone_id uuid,
  p_channel text,
  p_status text default 'all'
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_stats jsonb;
  v_referrals jsonb;
begin
  if auth.uid() is null
    or not public.is_admin()
    or p_channel not in ('preview','production')
    or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso a referidos no autorizado';
  end if;

  v_context := public.admin_access_context();
  if coalesce(v_context->>'role','') not in ('super_admin','zone_monitor') then
    raise exception 'El historial de referidos requiere acceso administrativo central';
  end if;
  if v_context->>'zone_id' is not null
    and (v_context->>'zone_id')::uuid <> p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  if p_status not in ('all','pending','qualified','reward_review','closed') then
    raise exception 'Filtro de estado inválido';
  end if;
  if not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active) then
    raise exception 'Zona no disponible';
  end if;

  select jsonb_build_object(
    'total', count(*),
    'pending', count(*) filter (where l.state='pending'),
    'activated', count(*) filter (where l.state='qualified'),
    'conversion_percent', case when count(*)=0 then 0
      else round(100.0 * count(*) filter (where l.state='qualified') / count(*), 1) end
  )
  into v_stats
  from public.benefit_referral_links l
  join public.benefit_programs p on p.id=l.program_id
  where l.zone_id=p_zone_id and l.channel=p_channel
    and p.program_type in ('referral','referral_commission');

  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb)
  into v_referrals
  from (
    select
      l.id,
      l.state,
      l.plan_payment_percent,
      l.created_at,
      l.qualified_at,
      code.code as referral_code,
      referrer.full_name as referrer_name,
      referrer.phone as referrer_phone,
      referred.full_name as referred_name,
      referred.phone as referred_phone,
      coalesce(payments.payment_count,0) as activity_count,
      coalesce(payments.commission_total,0) as commission_total,
      payments.last_payment_at as last_activity_at
    from public.benefit_referral_links l
    join public.benefit_programs p on p.id=l.program_id
    join public.users referrer on referrer.id=l.referrer_id
    join public.users referred on referred.id=l.referee_id
    left join public.driver_referral_codes code
      on code.driver_id=l.referrer_id and code.channel=l.channel
    left join lateral (
      select coalesce(sum(x.payment_count),0)::integer as payment_count,
        coalesce(sum(x.commission_total),0)::numeric(12,2) as commission_total,
        max(x.last_payment_at) as last_payment_at
      from (
        select count(*)::integer as payment_count,coalesce(sum(c.commission_amount),0)::numeric(12,2) as commission_total,max(c.created_at) as last_payment_at
          from public.benefit_subscription_commissions c where c.referral_id=l.id and c.channel=l.channel
        union all
        select count(*)::integer,coalesce(sum(c.commission_amount),0)::numeric(12,2),max(c.created_at)
          from public.benefit_trip_referral_commissions c where c.referral_id=l.id and c.channel=l.channel
        union all
        select count(*)::integer,coalesce(sum(r.amount),0)::numeric(12,2),max(r.created_at)
          from public.benefit_driver_referral_rewards r where r.referral_id=l.id and r.channel=l.channel
      ) x
    ) payments on true
    where l.zone_id=p_zone_id and l.channel=p_channel
      and p.program_type in ('referral','referral_commission')
      and (p_status='all' or l.state=p_status)
  ) r;

  return jsonb_build_object('stats',v_stats,'referrals',v_referrals,'currency',(select currency_code from public.service_zones where id=p_zone_id));
end $$;
create or replace function public.admin_benefit_program_save(
  p_id uuid,p_zone_id uuid,p_channel text,p_type text,p_name text,
  p_description text,p_config jsonb,p_state text,
  p_starts_at timestamptz default null,p_ends_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_context jsonb;v_record public.benefit_programs%rowtype;
begin
  if auth.uid() is null or not public.is_admin()
    or p_channel not in ('preview','production')
    or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso a beneficios no autorizado';
  end if;
  v_context:=public.admin_access_context();
  if coalesce(v_context->>'role','')<>'super_admin' then
    raise exception 'Solo el superadministrador puede configurar programas de beneficios';
  end if;
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid<>p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  if not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active) then
    raise exception 'La zona no existe o está inactiva';
  end if;
  if p_type not in ('coupon','activation','loyalty','referral','referral_commission','driver_challenge')
    or p_state not in ('draft','active','paused','closed') then
    raise exception 'Tipo o estado de programa inválido';
  end if;
  if length(trim(coalesce(p_name,'')))<2 or length(trim(p_name))>100 then
    raise exception 'El nombre debe tener entre 2 y 100 caracteres';
  end if;
  if length(coalesce(p_description,''))>1000 then
    raise exception 'La descripción no puede superar 1000 caracteres';
  end if;
  if p_config is null or jsonb_typeof(p_config)<>'object' then
    raise exception 'La configuración del programa es inválida';
  end if;
  if p_ends_at is not null and p_starts_at is not null and p_ends_at<=p_starts_at then
    raise exception 'La fecha de fin debe ser posterior a la de inicio';
  end if;

  if p_type='coupon' then
    if coalesce(p_config->>'code','') !~ '^[A-Z0-9_-]{3,64}$' then
      raise exception 'El código debe tener de 3 a 64 caracteres: letras mayúsculas, números, guion o guion bajo';
    end if;
    if p_config->>'discount_type' not in ('fixed','percent') then
      raise exception 'El tipo de descuento debe ser monto fijo o porcentaje';
    end if;
    if coalesce((p_config->>'value')::numeric,0)<=0 then
      raise exception 'El descuento debe ser mayor que cero';
    end if;
    if p_config->>'discount_type'='percent' and (p_config->>'value')::numeric>100 then
      raise exception 'El porcentaje de descuento no puede superar 100';
    end if;
    if coalesce((p_config->>'max_discount')::numeric,0)<0
       or coalesce((p_config->>'min_fare')::numeric,0)<0 then
      raise exception 'El tope de descuento y la tarifa mínima no pueden ser negativos';
    end if;
    if coalesce(p_config->>'service_mode','transport') not in ('transport','delivery') then
      raise exception 'El servicio del cupón no es válido';
    end if;
    if coalesce(p_config->>'audience','passengers') not in ('passengers','clients') then
      raise exception 'El público de un cupón debe ser pasajeros o clientes';
    end if;
  end if;

  if p_state='active' and p_type not in ('referral','referral_commission','coupon','activation','loyalty','driver_challenge') then
    raise exception 'Este tipo de programa requiere reglas de liquidación antes de activarse';
  end if;
  if p_type='activation' and p_state='active' then
    if p_config->>'trigger_type'<>'first_trip' then
      raise exception 'La bienvenida solo puede activarse con el primer viaje';
    end if;
    if coalesce((p_config->>'value')::numeric,0)<=0 then
      raise exception 'La bienvenida requiere un valor mayor que cero';
    end if;
    if p_config->>'reward_type' not in ('fixed','percent','coupon') then
      raise exception 'El tipo de recompensa de bienvenida no es válido';
    end if;
    if p_config->>'reward_type'='percent' and (p_config->>'value')::numeric>100 then
      raise exception 'El porcentaje de la bienvenida no puede superar 100';
    end if;
    if p_config->>'reward_type'='coupon' and p_config->>'reward_destination'<>'coupon' then
      raise exception 'La recompensa tipo cupón debe entregarse como cupón';
    end if;
  end if;
  if p_type='loyalty' and p_state='active' then
    if coalesce((p_config->>'trip_threshold')::integer,0)<=0 then
      raise exception 'La lealtad requiere una meta de viajes mayor que cero';
    end if;
    if coalesce((p_config->>'free_trip_cap')::numeric,0)<0 then
      raise exception 'El tope del viaje gratis no puede ser negativo';
    end if;
  end if;
  if p_type='driver_challenge' and p_state='active' then
    if coalesce((p_config->>'trip_goal')::integer,(p_config->>'trip_threshold')::integer,0)<=0 then
      raise exception 'El reto requiere una meta de viajes mayor que cero';
    end if;
    if coalesce((p_config->>'value')::numeric,0)<=0 then
      raise exception 'El reto requiere un bono mayor que cero';
    end if;
    if p_config->>'period' not in ('daily','weekly','monthly','custom') then
      raise exception 'El periodo del reto no es válido';
    end if;
  end if;
  if p_type='referral_commission' and (
    coalesce(p_config->>'commission_basis','plan_payment') not in ('plan_payment','company_trip')
    or (coalesce(p_config->>'commission_basis','plan_payment')='company_trip' and
      (coalesce((p_config->>'company_commission_percent')::numeric,0)<=0
       or coalesce((p_config->>'company_commission_percent')::numeric,0)>100))
    or (coalesce(p_config->>'commission_basis','plan_payment')='plan_payment' and
      (not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.country_code='BO')
       or coalesce((p_config->>'plan_payment_percent')::numeric,0)<=0
       or coalesce((p_config->>'plan_payment_percent')::numeric,0)>100))
  ) then raise exception 'La comisión MLM debe tener un porcentaje válido'; end if;
  if p_type='referral' and p_state='active' and (
    coalesce((p_config->>'referrer_reward')::numeric,0)<=0
    or coalesce((p_config->>'referred_reward')::numeric,0)<=0
    or coalesce((p_config->>'min_paid_trips')::integer,0)<0
    or coalesce(p_config->>'referrer_destination','wallet')<>'wallet'
    or coalesce(p_config->>'referred_destination','wallet')<>'wallet'
  ) then raise exception 'El programa de referidos requiere recompensas válidas en billetera'; end if;
  if p_id is not null and not exists(select 1 from public.benefit_programs
    where id=p_id and zone_id=p_zone_id and channel=p_channel) then
    raise exception 'No se puede modificar un programa ajeno';
  end if;

  insert into public.benefit_programs(id,channel,zone_id,program_type,name,description,config,state,starts_at,ends_at,created_by)
  values(coalesce(p_id,gen_random_uuid()),p_channel,p_zone_id,p_type,trim(p_name),coalesce(p_description,''),p_config,p_state,p_starts_at,p_ends_at,auth.uid())
  on conflict(id) do update set program_type=excluded.program_type,name=excluded.name,
    description=excluded.description,config=excluded.config,state=excluded.state,
    starts_at=excluded.starts_at,ends_at=excluded.ends_at,updated_at=now()
  returning * into v_record;
  perform public.admin_log_action('upsert','benefit_program',v_record.id::text,
    jsonb_build_object('channel',p_channel,'zone_id',p_zone_id,'type',p_type,'state',p_state));
  return to_jsonb(v_record);
end $$;
create or replace function public.sync_benefit_program_marketplace_coupon()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_country text; v_funded_by text;
begin
  if new.program_type<>'coupon' then return new; end if;
  if coalesce(new.config->>'service_mode','transport')<>'delivery' or new.state<>'active' then
    update public.marketplace_coupons set active=false,updated_at=now() where benefit_program_id=new.id;
    return new;
  end if;
  select country_code into v_country from public.service_zones where id=new.zone_id;
  v_funded_by:=case coalesce(new.config->>'discount_absorber','company')
    when 'driver' then 'driver' when 'split' then 'split' else 'express' end;
  insert into public.marketplace_coupons(zone_id,country_code,channel,benefit_program_id,code,title,description,
    discount_type,discount_value,min_order,max_discount,funded_by,usage_limit,per_user_limit,starts_at,ends_at,
    active,preview_visible,production_visible)
  values(new.zone_id,v_country,new.channel,new.id,upper(trim(new.config->>'code')),new.name,nullif(new.description,''),
    new.config->>'discount_type',(new.config->>'value')::numeric,coalesce(nullif(new.config->>'min_fare','')::numeric,0),
    nullif(new.config->>'max_discount','')::numeric,v_funded_by,nullif(new.config->>'max_total_uses','')::integer,
    coalesce(nullif(new.config->>'uses_per_user','')::integer,1),new.starts_at,new.ends_at,true,
    new.channel='preview',new.channel='production')
  on conflict(benefit_program_id) where benefit_program_id is not null do update set
    zone_id=excluded.zone_id,country_code=excluded.country_code,channel=excluded.channel,code=excluded.code,
    title=excluded.title,description=excluded.description,discount_type=excluded.discount_type,
    discount_value=excluded.discount_value,min_order=excluded.min_order,max_discount=excluded.max_discount,
    funded_by=excluded.funded_by,usage_limit=excluded.usage_limit,per_user_limit=excluded.per_user_limit,
    starts_at=excluded.starts_at,ends_at=excluded.ends_at,active=true,
    preview_visible=excluded.preview_visible,production_visible=excluded.production_visible,updated_at=now();
  return new;
end $$;
create or replace function public.my_driver_referral_status(p_channel text default 'production')
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();v_runtime jsonb;v_zone uuid;v_country text;v_currency text;v_code text;
  v_program uuid;v_percent numeric;v_total numeric;v_has_referrer boolean;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false
    or (v_runtime->>'environment') is distinct from p_channel
    or p_channel not in ('preview','production') then raise exception 'Entorno de datos no autorizado'; end if;
  select dp.zone_id,z.country_code,z.currency_code into v_zone,v_country,v_currency
    from public.driver_profiles dp join public.service_zones z on z.id=dp.zone_id
    where dp.id=v_uid and z.active;
  if v_zone is null then raise exception 'Se requiere perfil de conductor y zona activa'; end if;
  insert into public.driver_referral_codes(driver_id,channel,code)
    values(v_uid,p_channel,upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)))
    on conflict(driver_id,channel) do nothing;
  select code into v_code from public.driver_referral_codes
    where driver_id=v_uid and channel=p_channel;
  select id,case when config->>'commission_basis'='company_trip' then (config->>'company_commission_percent')::numeric else (config->>'plan_payment_percent')::numeric end into v_program,v_percent
    from public.benefit_programs where program_type in ('referral','referral_commission')
      and state='active' and zone_id=v_zone and channel=p_channel
      and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now())
    order by created_at desc limit 1;
  select coalesce((select sum(commission_amount) from public.benefit_subscription_commissions where referrer_id=v_uid and channel=p_channel),0)
    + coalesce((select sum(commission_amount) from public.benefit_trip_referral_commissions where referrer_id=v_uid and channel=p_channel),0)
    + coalesce((select sum(amount) from public.benefit_driver_referral_rewards where beneficiary_id=v_uid and beneficiary_role='referrer' and channel=p_channel),0)
    into v_total;
  select exists(select 1 from public.benefit_referral_links
    l join public.benefit_programs p on p.id=l.program_id
    where l.referee_id=v_uid and l.channel=p_channel
      and p.program_type in ('referral','referral_commission')) into v_has_referrer;
  return jsonb_build_object('eligible',true,'code',v_code,'zone_id',v_zone,'country_code',v_country,
    'program_active',v_program is not null,'percent',v_percent,
    'program_type',(select program_type from public.benefit_programs where id=v_program),
    'commission_basis',(select config->>'commission_basis' from public.benefit_programs where id=v_program),
    'min_paid_trips',(select nullif(config->>'min_paid_trips','')::integer from public.benefit_programs where id=v_program),
    'referrals',(select count(*) from public.benefit_referral_links l
      join public.benefit_programs p on p.id=l.program_id
      where l.referrer_id=v_uid and l.channel=p_channel and p.program_type in ('referral','referral_commission')),
    'credited_total',v_total,'has_referrer',v_has_referrer,'currency',v_currency);
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
  if v_zone is null then raise exception 'Se requiere perfil de conductor y zona activa'; end if;
  select driver_id into v_referrer from public.driver_referral_codes
    where code=upper(trim(coalesce(p_code,''))) and channel=p_channel;
  if v_referrer is null or v_referrer=v_uid then raise exception 'Código de referido inválido'; end if;
  if not exists(select 1 from public.driver_profiles where id=v_referrer) then
    raise exception 'El código no pertenece a un conductor'; end if;
  select id,case when config->>'commission_basis'='company_trip' then (config->>'company_commission_percent')::numeric else (config->>'plan_payment_percent')::numeric end into v_program,v_percent
    from public.benefit_programs where program_type in ('referral','referral_commission')
      and state='active' and zone_id=v_zone and channel=p_channel
      and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now())
    order by created_at desc limit 1;
  if v_program is null or (coalesce(v_percent,0)<=0 and not exists(select 1 from public.benefit_programs p where p.id=v_program and p.program_type='referral')) then
    raise exception 'El programa de referidos no está activo en tu zona'; end if;
  if exists(select 1 from public.benefit_programs p where p.id=v_program and p.program_type='referral'
      and nullif(p.config->>'max_referrals_per_user','') is not null
      and (select count(*) from public.benefit_referral_links l where l.program_id=p.id and l.referrer_id=v_referrer)>= (p.config->>'max_referrals_per_user')::integer) then
    raise exception 'El conductor alcanzó el máximo de referidos del programa'; end if;
  insert into public.benefit_referral_links(channel,zone_id,referrer_id,referee_id,
    program_id,state,plan_payment_percent)
  values(p_channel,v_zone,v_referrer,v_uid,v_program,'pending',v_percent)
  on conflict(channel,referee_id) do nothing returning id into v_link;
  if v_link is null then raise exception 'Este conductor ya tiene un código de referido registrado'; end if;
  return jsonb_build_object('linked',true,'percent',v_percent,'currency',(select currency_code from public.service_zones where id=v_zone));
end $$;
create or replace function public.credit_driver_plan_referral()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_plan public.driver_subscription_plans%rowtype;v_zone public.service_zones%rowtype;
  v_link public.benefit_referral_links%rowtype;v_program public.benefit_programs%rowtype;v_amount numeric(12,2);v_commission numeric(12,2);
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
  select * into v_program from public.benefit_programs where id=v_link.program_id;
  if v_program.config->>'commission_basis'='company_trip' then return new; end if;
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
create or replace function public.settle_driver_benefit_referrals()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_trip public.trips%rowtype;v_request public.ride_requests%rowtype;v_zone public.service_zones%rowtype;
 v_link public.benefit_referral_links%rowtype;v_program public.benefit_programs%rowtype;v_paid integer;v_min integer;
 v_amount numeric(12,2);v_percent numeric(7,4);v_wallet uuid;v_reward_role text;v_reward_user uuid;
begin
 if new.status<>'paid' or new.trip_id is null or (tg_op='UPDATE' and old.status='paid') then return new; end if;
 select * into v_trip from public.trips where id=new.trip_id;
 if not found or v_trip.status<>'completed' or v_trip.payment_status<>'paid' then return new; end if;
 select * into v_request from public.ride_requests where id=v_trip.ride_request_id;
 if not found or v_request.channel<>new.channel then return new; end if;
 select * into v_zone from public.service_zones where id=v_request.zone_id;
 for v_link in select l.* from public.benefit_referral_links l
   join public.benefit_programs p on p.id=l.program_id
   where l.referee_id=v_trip.driver_id and l.channel=new.channel and l.zone_id=v_request.zone_id
     and l.state in ('pending','qualified') and p.state='active'
     and (p.program_type='referral' or (p.program_type='referral_commission' and p.config->>'commission_basis'='company_trip'))
     and (p.starts_at is null or p.starts_at<=now()) and (p.ends_at is null or p.ends_at>now())
   for update of l
 loop
   select * into v_program from public.benefit_programs where id=v_link.program_id;
   if v_program.program_type='referral' then
     v_min:=greatest(coalesce(nullif(v_program.config->>'min_paid_trips','')::integer,0),1);
     v_paid:=v_link.qualifying_paid_trips+1;
     update public.benefit_referral_links set qualifying_paid_trips=v_paid,
       state=case when v_paid>=v_min then 'qualified' else 'pending' end,
       qualified_at=case when v_paid>=v_min then coalesce(qualified_at,now()) else qualified_at end
       where id=v_link.id;
     if v_paid>=v_min and v_link.state<>'qualified' then
       for v_reward_role,v_reward_user in select * from (values('referrer',v_link.referrer_id),('referred',v_link.referee_id)) x(role,user_id)
       loop
         v_amount:=coalesce(nullif(v_program.config->>(v_reward_role||'_reward'),'')::numeric,0);
         if v_program.config->>(v_reward_role||'_reward_type')='percent' then
           v_amount:=round(greatest(coalesce(new.amount,0),0)*v_amount/100,2);
         end if;
         if v_amount<=0 then continue; end if;
         insert into public.benefit_driver_referral_rewards(program_id,referral_id,trigger_trip_id,beneficiary_id,
           beneficiary_role,channel,zone_id,amount,currency_code)
         values(v_program.id,v_link.id,v_trip.id,v_reward_user,v_reward_role,new.channel,v_request.zone_id,v_amount,v_zone.currency_code)
         on conflict(referral_id,beneficiary_role) do nothing returning id into v_wallet;
         if v_wallet is not null then
           insert into public.wallet_transactions(user_id,amount,type,status,reference,trip_id,country_code,channel)
           values(v_reward_user,v_amount,'adjustment','completed','benefit:driver-referral:'||v_wallet::text,v_trip.id,v_zone.country_code,new.channel)
           returning id into v_wallet;
           update public.benefit_driver_referral_rewards set wallet_transaction_id=v_wallet
             where referral_id=v_link.id and beneficiary_role=v_reward_role;
           if new.channel='production' then perform public.mirror_legacy_wallet_delta(v_reward_user,v_zone.currency_code,v_amount); end if;
         end if;
       end loop;
     end if;
   else
     if v_link.state='pending' then
       update public.benefit_referral_links set state='qualified',qualified_at=coalesce(qualified_at,now()),
         qualifying_paid_trips=qualifying_paid_trips+1 where id=v_link.id;
     end if;
     v_percent:=coalesce(nullif(v_program.config->>'company_commission_percent','')::numeric,0);
     v_amount:=round(greatest(coalesce(new.commission_amount,0),0)*v_percent/100,2);
     if v_percent<=0 or v_amount<=0 then continue; end if;
     if not coalesce((v_program.config->>'lifetime')::boolean,true)
       and v_link.created_at<=now()-make_interval(months=>coalesce(nullif(v_program.config->>'benefit_months','')::integer,0)) then continue; end if;
     insert into public.benefit_trip_referral_commissions(program_id,referral_id,trip_id,referrer_id,referred_driver_id,
       channel,zone_id,commission_base,commission_percent,commission_amount)
     values(v_program.id,v_link.id,v_trip.id,v_link.referrer_id,v_trip.driver_id,new.channel,v_request.zone_id,
       greatest(coalesce(new.commission_amount,0),0),v_percent,v_amount)
     on conflict(program_id,trip_id,referral_id) do nothing returning id into v_wallet;
     if v_wallet is not null then
       insert into public.wallet_transactions(user_id,amount,type,status,reference,trip_id,country_code,channel)
       values(v_link.referrer_id,v_amount,'adjustment','completed','benefit:trip-referral:'||v_wallet::text,v_trip.id,v_zone.country_code,new.channel)
       returning id into v_wallet;
       update public.benefit_trip_referral_commissions set wallet_transaction_id=v_wallet where program_id=v_program.id and trip_id=v_trip.id and referral_id=v_link.id;
       if new.channel='production' then perform public.mirror_legacy_wallet_delta(v_link.referrer_id,v_zone.currency_code,v_amount); end if;
     end if;
   end if;
 end loop;
 return new;
end $$;
revoke all on function public.settle_driver_benefit_referrals() from public,anon,authenticated;
commit;
