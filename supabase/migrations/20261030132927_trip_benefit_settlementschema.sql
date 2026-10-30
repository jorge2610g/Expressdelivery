-- Applies passenger ride coupons and trip-earned benefits only after a paid,
-- directly settled ride. Promotion value is credited to the driver's
-- non-withdrawable in-app wallet; Express never collects the ride fare.
begin;

alter table public.ride_requests
  add column if not exists benefit_coupon_code text,
  add column if not exists benefit_coupon_program_id uuid references public.benefit_programs(id),
  add column if not exists benefit_user_coupon_id uuid,
  add column if not exists benefit_discount_amount numeric(12,2) not null default 0
    check (benefit_discount_amount >= 0);

alter table public.trips
  add column if not exists passenger_due_amount numeric(12,2),
  add column if not exists promotion_credit_amount numeric(12,2) not null default 0
    check (promotion_credit_amount >= 0);

create table if not exists public.benefit_user_coupons (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.benefit_programs(id),
  channel text not null check(channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id),
  user_id uuid not null references public.users(id),
  code text not null unique check(code ~ '^[A-Z0-9-]{8,24}$'),
  discount_type text not null check(discount_type in ('fixed','percent')),
  value numeric(12,2) not null check(value>0),
  max_discount numeric(12,2) check(max_discount is null or max_discount>=0),
  source_type text not null check(source_type in ('activation','loyalty')),
  source_trip_id uuid not null references public.trips(id),
  state text not null default 'available' check(state in ('available','reserved','redeemed','expired')),
  reserved_request_id uuid references public.ride_requests(id),
  redeemed_trip_id uuid references public.trips(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '90 days',
  unique(program_id,user_id,source_trip_id)
);
create index if not exists benefit_user_coupons_available_idx
  on public.benefit_user_coupons(user_id,channel,zone_id,state,expires_at);
alter table public.benefit_user_coupons enable row level security;
revoke all on public.benefit_user_coupons from public,anon,authenticated;

create table if not exists public.benefit_coupon_reservations (
  ride_request_id uuid primary key references public.ride_requests(id) on delete cascade,
  channel text not null check(channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id),
  user_id uuid not null references public.users(id),
  program_id uuid references public.benefit_programs(id),
  user_coupon_id uuid references public.benefit_user_coupons(id),
  state text not null default 'reserved' check(state in ('reserved','redeemed','released')),
  created_at timestamptz not null default now(),
  check ((program_id is null) <> (user_coupon_id is null))
);
create index if not exists benefit_coupon_reservations_program_idx
  on public.benefit_coupon_reservations(program_id,state,channel,zone_id);
alter table public.benefit_coupon_reservations enable row level security;
revoke all on public.benefit_coupon_reservations from public,anon,authenticated;

create table if not exists public.benefit_driver_challenge_awards (
  program_id uuid not null references public.benefit_programs(id),
  user_id uuid not null references public.users(id),
  cycle_start timestamptz not null,
  trip_id uuid not null references public.trips(id),
  channel text not null check(channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id),
  amount numeric(12,2) not null check(amount>0),
  currency_code text not null,
  wallet_transaction_id uuid references public.wallet_transactions(id),
  created_at timestamptz not null default now(),
  primary key(program_id,user_id,cycle_start)
);
alter table public.benefit_driver_challenge_awards enable row level security;
revoke all on public.benefit_driver_challenge_awards from public,anon,authenticated;

create or replace function public.guard_benefit_coupon_fields()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    new.benefit_coupon_code:=nullif(upper(trim(coalesce(new.benefit_coupon_code,''))),'');
    new.benefit_coupon_program_id:=null;
    new.benefit_user_coupon_id:=null;
    new.benefit_discount_amount:=0;
    return new;
  end if;
  if current_setting('app.benefit_coupon_write',true)='on' then return new; end if;
  if new.benefit_coupon_code is distinct from old.benefit_coupon_code
     or new.benefit_coupon_program_id is distinct from old.benefit_coupon_program_id
     or new.benefit_user_coupon_id is distinct from old.benefit_user_coupon_id
     or new.benefit_discount_amount is distinct from old.benefit_discount_amount then
    raise exception 'Los datos del cupón los valida el servidor';
  end if;
  return new;
end $$;
drop trigger if exists benefit_coupon_fields_guard on public.ride_requests;
create trigger benefit_coupon_fields_guard before insert or update on public.ride_requests
for each row execute function public.guard_benefit_coupon_fields();
revoke all on function public.guard_benefit_coupon_fields() from public,anon,authenticated;

create or replace function public.reserve_benefit_coupon_for_request()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_program public.benefit_programs%rowtype;
  v_coupon public.benefit_user_coupons%rowtype;
  v_config jsonb;
  v_first_ride boolean;
  v_max_total integer;
  v_per_user integer;
  v_used_total integer;
  v_used_user integer;
begin
  if new.benefit_coupon_code is null then return new; end if;
  if auth.uid() is distinct from new.passenger_id or new.zone_id is null then
    raise exception 'No se pudo validar el cupón para este pasajero y zona';
  end if;

  select * into v_program from public.benefit_programs p
  where p.channel=new.channel and p.zone_id=new.zone_id
    and p.program_type='coupon' and p.state='active'
    and upper(coalesce(p.config->>'code',''))=new.benefit_coupon_code
    and (p.starts_at is null or p.starts_at<=now())
    and (p.ends_at is null or p.ends_at>now())
  for update;

  if found then
    v_config:=v_program.config;
    if new.service_mode='parcel'
       or coalesce(v_config->>'audience','passengers') not in ('passengers','clients')
       or coalesce(v_config->>'service_mode','transport') not in ('transport','taxi',new.service_mode)
       or coalesce(v_config->>'service_mode','transport')='delivery'
       or (coalesce(v_config->>'service_type','all') not in ('all',new.category)
           and not (v_config->>'service_type'='moto' and new.category in ('motorcycle','moto')))
       or coalesce(new.proposed_fare,0)<coalesce(nullif(v_config->>'min_fare','')::numeric,0) then
      raise exception 'El cupón no aplica a este servicio o tarifa';
    end if;
    if v_config->>'discount_type' not in ('fixed','percent')
       or coalesce(nullif(v_config->>'value','')::numeric,0)<=0 then
      raise exception 'El cupón no tiene un descuento válido';
    end if;
    if coalesce((v_config->>'first_ride_only')::boolean,false) and exists(
      select 1 from public.trips t where t.passenger_id=new.passenger_id
        and t.channel=new.channel and t.status='completed' and t.payment_status='paid'
    ) then raise exception 'Este cupón es válido solo para el primer viaje'; end if;
    if coalesce(v_config->>'target_audience','all')='new' and exists(
      select 1 from public.trips t where t.passenger_id=new.passenger_id
        and t.channel=new.channel and t.status='completed' and t.payment_status='paid'
    ) then raise exception 'Este cupón es solo para usuarios nuevos'; end if;
    if coalesce(v_config->>'target_audience','all')='returning' and not exists(
      select 1 from public.trips t where t.passenger_id=new.passenger_id
        and t.channel=new.channel and t.status='completed' and t.payment_status='paid'
    ) then raise exception 'Este cupón es para usuarios frecuentes'; end if;
    if new.payment_method='wallet' then
      raise exception 'Los cupones de viaje requieren pagar la diferencia en efectivo o QR del conductor';
    end if;
    v_max_total:=nullif(v_config->>'max_total_uses','')::integer;
    v_per_user:=nullif(v_config->>'uses_per_user','')::integer;
    select count(*) into v_used_total from public.benefit_coupon_reservations r
      where r.program_id=v_program.id and r.channel=new.channel and r.state in ('reserved','redeemed');
    select count(*) into v_used_user from public.benefit_coupon_reservations r
      where r.program_id=v_program.id and r.user_id=new.passenger_id
        and r.channel=new.channel and r.state in ('reserved','redeemed');
    if v_max_total is not null and v_used_total>=v_max_total then raise exception 'Este cupón ya alcanzó su límite de usos'; end if;
    if v_per_user is not null and v_used_user>=v_per_user then raise exception 'Ya utilizaste el máximo permitido de este cupón'; end if;
    perform set_config('app.benefit_coupon_write','on',true);
    update public.ride_requests set benefit_coupon_program_id=v_program.id where id=new.id;
    insert into public.benefit_coupon_reservations(ride_request_id,channel,zone_id,user_id,program_id)
      values(new.id,new.channel,new.zone_id,new.passenger_id,v_program.id);
    return new;
  end if;

  select * into v_coupon from public.benefit_user_coupons c
  where c.code=new.benefit_coupon_code and c.user_id=new.passenger_id
    and c.zone_id=new.zone_id and c.channel=new.channel and c.state='available'
    and c.expires_at>now()
  for update;
  if not found then raise exception 'El código de cupón no es válido o no está disponible'; end if;
  update public.benefit_user_coupons set state='reserved',reserved_request_id=new.id where id=v_coupon.id;
  perform set_config('app.benefit_coupon_write','on',true);
  update public.ride_requests set benefit_user_coupon_id=v_coupon.id where id=new.id;
  insert into public.benefit_coupon_reservations(ride_request_id,channel,zone_id,user_id,user_coupon_id)
    values(new.id,new.channel,new.zone_id,new.passenger_id,v_coupon.id);
  return new;
end $$;
drop trigger if exists benefit_coupon_request_reservation on public.ride_requests;
create trigger benefit_coupon_request_reservation after insert on public.ride_requests
for each row execute function public.reserve_benefit_coupon_for_request();
revoke all on function public.reserve_benefit_coupon_for_request() from public,anon,authenticated;

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
      'driver_credits',(select coalesce(sum(r.amount),0) from public.benefit_redemptions r where r.program_id=p.id and r.benefit_type='ride_coupon' and r.state='approved'),
      'challenge_participants',(select count(distinct a.user_id) from public.benefit_driver_challenge_awards a where a.program_id=p.id),
      'challenge_awards',(select count(*) from public.benefit_driver_challenge_awards a where a.program_id=p.id),
      'challenge_credits',(select coalesce(sum(a.amount),0) from public.benefit_driver_challenge_awards a where a.program_id=p.id)
    )) order by p.created_at desc),'[]'::jsonb)
    from public.benefit_programs p where p.zone_id=p_zone_id and p.channel=p_channel
      and (p_type is null or p.program_type=p_type));
end $$;
revoke all on function public.admin_benefit_program_list(uuid,text,text) from public,anon;
grant execute on function public.admin_benefit_program_list(uuid,text,text) to authenticated;

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
  if p_type not in ('coupon','activation','loyalty','referral','referral_commission','driver_challenge')
    or p_state not in ('draft','active','paused','closed')
    or length(trim(coalesce(p_name,'')))<2 or length(trim(p_name))>100
    or length(coalesce(p_description,''))>1000
    or p_config is null or jsonb_typeof(p_config)<>'object'
    or (p_ends_at is not null and p_starts_at is not null and p_ends_at<=p_starts_at)
    or not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active) then
    raise exception 'Configuración del programa inválida';
  end if;
  if p_type='coupon' and (
    coalesce(p_config->>'code','') !~ '^[A-Z0-9_-]{3,64}$'
    or p_config->>'discount_type' not in ('fixed','percent')
    or coalesce((p_config->>'value')::numeric,0)<=0
    or (p_config->>'discount_type'='percent' and (p_config->>'value')::numeric>100)
    or coalesce((p_config->>'max_discount')::numeric,0)<0
    or coalesce((p_config->>'min_fare')::numeric,0)<0
    or (p_state='active' and (coalesce(p_config->>'service_mode','transport')='delivery'
      or coalesce(p_config->>'audience','passengers') not in ('passengers','clients')))
  ) then raise exception 'Datos inválidos; los cupones de viaje se aplican al transporte'; end if;
  if p_state='active' and p_type not in ('referral_commission','coupon','activation','loyalty','driver_challenge') then
    raise exception 'Este tipo de programa requiere reglas de liquidación antes de activarse';
  end if;
  if p_type='activation' and p_state='active' and (
    p_config->>'trigger_type'<>'first_trip'
    or p_config->>'reward_destination'='wallet'
    or coalesce((p_config->>'value')::numeric,0)<=0
    or p_config->>'reward_type' not in ('fixed','percent','coupon')
    or (p_config->>'reward_type'='percent' and (p_config->>'value')::numeric>100)
  ) then raise exception 'La bienvenida requiere primer viaje y una recompensa en cupón'; end if;
  if p_type='loyalty' and p_state='active' and (
    coalesce((p_config->>'trip_threshold')::integer,0)<=0
    or coalesce((p_config->>'free_trip_cap')::numeric,0)<0
  ) then raise exception 'Configura el umbral y el tope del viaje gratis'; end if;
  if p_type='driver_challenge' and p_state='active' and (
    coalesce((p_config->>'trip_goal')::integer,(p_config->>'trip_threshold')::integer,0)<=0
    or coalesce((p_config->>'value')::numeric,0)<=0
    or p_config->>'period' not in ('daily','weekly','monthly','custom')
  ) then raise exception 'El reto requiere una meta, un periodo y un bono positivo'; end if;
  if p_type='referral_commission' and (
    not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.country_code='BO')
    or coalesce((p_config->>'plan_payment_percent')::numeric,0)<=0
    or coalesce((p_config->>'plan_payment_percent')::numeric,0)>100
  ) then raise exception 'El referido de pagos de plan requiere porcentaje válido y una zona de Bolivia'; end if;
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

create or replace function public.release_benefit_coupon_reservation()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status in ('cancelled','canceled','expired','rejected') then
    update public.benefit_coupon_reservations set state='released'
      where ride_request_id=new.id and state='reserved';
    update public.benefit_user_coupons set state='available',reserved_request_id=null
      where id=(select user_coupon_id from public.benefit_coupon_reservations where ride_request_id=new.id)
        and state='reserved';
  end if;
  return new;
end $$;
drop trigger if exists benefit_coupon_request_release on public.ride_requests;
create trigger benefit_coupon_request_release after update of status on public.ride_requests
for each row execute function public.release_benefit_coupon_reservation();
revoke all on function public.release_benefit_coupon_reservation() from public,anon,authenticated;

create or replace function public.release_benefit_coupon_for_cancelled_trip()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_request uuid;
begin
  if new.status not in ('cancelled','canceled') then return new; end if;
  v_request:=new.ride_request_id;
  update public.benefit_coupon_reservations set state='released'
    where ride_request_id=v_request and state='reserved';
  update public.benefit_user_coupons set state='available',reserved_request_id=null
    where id=(select user_coupon_id from public.benefit_coupon_reservations where ride_request_id=v_request)
      and state='reserved';
  return new;
end $$;
drop trigger if exists benefit_coupon_trip_release on public.trips;
create trigger benefit_coupon_trip_release after update of status on public.trips
for each row execute function public.release_benefit_coupon_for_cancelled_trip();
revoke all on function public.release_benefit_coupon_for_cancelled_trip() from public,anon,authenticated;

create or replace function public.quote_trip_benefit_amounts()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_request public.ride_requests%rowtype;v_reservation public.benefit_coupon_reservations%rowtype;
  v_program public.benefit_programs%rowtype;v_coupon public.benefit_user_coupons%rowtype;
  v_config jsonb;v_fare numeric(12,2);v_discount numeric(12,2):=0;
begin
  select * into v_request from public.ride_requests where id=new.ride_request_id;
  if not found then return new; end if;
  v_fare:=round(greatest(coalesce(new.final_fare,v_request.proposed_fare,0),0),2);
  new.passenger_due_amount:=v_fare;
  new.promotion_credit_amount:=0;
  if v_request.service_mode='parcel' or v_request.payment_method not in ('cash','driver_qr') then return new; end if;
  select * into v_reservation from public.benefit_coupon_reservations
    where ride_request_id=v_request.id and state='reserved';
  if not found then return new; end if;
  if v_reservation.program_id is not null then
    select * into v_program from public.benefit_programs where id=v_reservation.program_id;
    v_config:=v_program.config;
    if v_config->>'discount_type'='percent' then
      v_discount:=round(v_fare*coalesce((v_config->>'value')::numeric,0)/100,2);
    else v_discount:=round(coalesce((v_config->>'value')::numeric,0),2); end if;
    if nullif(v_config->>'max_discount','') is not null then
      v_discount:=least(v_discount,(v_config->>'max_discount')::numeric);
    end if;
  else
    select * into v_coupon from public.benefit_user_coupons where id=v_reservation.user_coupon_id;
    if v_coupon.discount_type='percent' then v_discount:=round(v_fare*v_coupon.value/100,2);
    else v_discount:=round(v_coupon.value,2); end if;
    if v_coupon.max_discount is not null then v_discount:=least(v_discount,v_coupon.max_discount); end if;
  end if;
  v_discount:=least(greatest(v_discount,0),v_fare);
  new.passenger_due_amount:=greatest(v_fare-v_discount,0);
  new.promotion_credit_amount:=v_discount;
  return new;
end $$;
drop trigger if exists zzzz_trip_benefit_quote on public.trips;
create trigger zzzz_trip_benefit_quote before insert or update of final_fare on public.trips
for each row execute function public.quote_trip_benefit_amounts();
revoke all on function public.quote_trip_benefit_amounts() from public,anon,authenticated;

create or replace function public.issue_benefit_user_coupon(
  p_program_id uuid,p_user_id uuid,p_trip_id uuid,p_channel text,p_zone_id uuid,
  p_source_type text,p_discount_type text,p_value numeric,p_max_discount numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_code text;
begin
  if p_source_type not in ('activation','loyalty') or p_discount_type not in ('fixed','percent') or p_value<=0 then
    raise exception 'Recompensa de cupón inválida';
  end if;
  select id into v_id from public.benefit_user_coupons
    where program_id=p_program_id and user_id=p_user_id and source_trip_id=p_trip_id;
  if v_id is not null then return v_id; end if;
  v_code:='EX-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into public.benefit_user_coupons(program_id,user_id,source_trip_id,channel,zone_id,
    code,discount_type,value,max_discount,source_type)
  values(p_program_id,p_user_id,p_trip_id,p_channel,p_zone_id,v_code,
    p_discount_type,p_value,p_max_discount,p_source_type)
  on conflict(program_id,user_id,source_trip_id) do nothing
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.issue_benefit_user_coupon(uuid,uuid,uuid,text,uuid,text,text,numeric,numeric) from public,anon,authenticated;

create or replace function public.settle_trip_benefits_for_payment()
returns trigger language plpgsql security definer set search_path=public as $$
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
        (select count(*) from public.benefit_user_coupons where program_id=v_program.id) then
        if v_config->>'reward_type'='percent' then
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
    end if;
  end loop;

  -- Driver challenge bonuses are internal-wallet credits, capped to one award per cycle.
  for v_program in select * from public.benefit_programs p
    where p.zone_id=v_request.zone_id and p.channel=v_request.channel
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
           and r.zone_id=v_request.zone_id and r.service_mode<>'parcel'
           and (coalesce(v_config->>'service_type','all') in ('all',r.category)
             or (v_config->>'service_type'='moto' and r.category in ('motorcycle','moto'))))>=v_goal
    then
      insert into public.benefit_driver_challenge_awards(program_id,user_id,cycle_start,trip_id,channel,zone_id,amount,currency_code)
      values(v_program.id,v_trip.driver_id,v_cycle_start,v_trip.id,v_request.channel,v_request.zone_id,
        (v_config->>'value')::numeric,v_zone.currency_code)
      on conflict(program_id,user_id,cycle_start) do nothing
      returning trip_id into v_award_id;
      if v_award_id is not null then
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
drop trigger if exists settle_trip_benefits_for_payment on public.payment_transactions;
create trigger settle_trip_benefits_for_payment after insert or update of status on public.payment_transactions
for each row execute function public.settle_trip_benefits_for_payment();
revoke all on function public.settle_trip_benefits_for_payment() from public,anon,authenticated;

create or replace function public.my_benefits_overview(p_channel text default 'production')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_uid uuid:=auth.uid();v_runtime jsonb;v_zone uuid;v_currency text;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  v_runtime:=public.resolve_current_runtime_environment();
  if coalesce((v_runtime->>'allowed')::boolean,false)=false
    or (v_runtime->>'environment') is distinct from p_channel
    or p_channel not in ('preview','production') then raise exception 'Entorno de datos no autorizado'; end if;
  select z.id,z.currency_code into v_zone,v_currency
    from public.users u left join public.driver_profiles dp on dp.id=u.id
    join public.service_zones z on z.id=coalesce(u.last_zone_id,dp.zone_id)
    where u.id=v_uid and z.active;
  if v_zone is null then return jsonb_build_object('available',false,'items','[]'::jsonb,'coupons','[]'::jsonb); end if;
  return jsonb_build_object('available',true,'currency',v_currency,'zone_id',v_zone,
    'items',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'type',p.program_type,'name',p.name,
      'description',p.description,'config',p.config,'currency',v_currency,'starts_at',p.starts_at,'ends_at',p.ends_at)
      order by p.created_at desc),'[]'::jsonb) from public.benefit_programs p
      where p.zone_id=v_zone and p.channel=p_channel and p.state='active'
        and (p.starts_at is null or p.starts_at<=now()) and (p.ends_at is null or p.ends_at>now())
        and (p.program_type in ('coupon','activation','loyalty','referral')
          or (p.program_type='driver_challenge' and exists(select 1 from public.driver_profiles dp where dp.id=v_uid)))),
    'coupons',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'code',c.code,'name',p.name,
      'discount_type',c.discount_type,'value',c.value,'max_discount',c.max_discount,
      'currency',v_currency,'expires_at',c.expires_at,'state',c.state) order by c.created_at desc),'[]'::jsonb)
      from public.benefit_user_coupons c join public.benefit_programs p on p.id=c.program_id
      where c.user_id=v_uid and c.zone_id=v_zone and c.channel=p_channel
        and c.state='available' and c.expires_at>now()),
    'history',(select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc),'[]'::jsonb)
      from public.benefit_redemptions r where r.user_id=v_uid and r.zone_id=v_zone and r.channel=p_channel));
end $$;
revoke all on function public.my_benefits_overview(text) from public,anon;
grant execute on function public.my_benefits_overview(text) to authenticated;


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

  -- Commission and fare rules use the same canonical configuration for both
  -- account channels. Ledger rows below still keep new.channel for isolation.
  if v_zone_id is not null and v_service_key is not null then
    v_fare_rule:=public.effective_fare_rule(v_service_key,v_zone_id);
  end if;

  if new.trip_id is not null or new.delivery_id is not null then
    -- Express does not charge a commission on passenger rides or deliveries.
    v_commission_percent:=0;
  elsif v_fare_rule is not null then
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

commit;
