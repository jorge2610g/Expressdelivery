-- Foundation for configurable coupons and user incentives.
-- Campaigns are always created as drafts; no payment or wallet flow is changed.
begin;

create table if not exists public.benefit_programs (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  program_type text not null check (program_type in
    ('coupon','activation','loyalty','referral','referral_commission','driver_challenge')),
  name text not null check (length(trim(name)) between 2 and 100),
  description text not null default '' check (length(description)<=1000),
  config jsonb not null default '{}'::jsonb,
  state text not null default 'draft' check (state in ('draft','active','paused','closed')),
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at>starts_at)
);
create index if not exists benefit_programs_scope_idx
  on public.benefit_programs(channel,zone_id,program_type,state,created_at desc);
alter table public.benefit_programs enable row level security;
revoke all on public.benefit_programs from public,anon,authenticated;

create table if not exists public.benefit_redemptions (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.benefit_programs(id),
  channel text not null check (channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id),
  user_id uuid not null references public.users(id),
  trip_id uuid references public.trips(id),
  benefit_type text not null,
  amount numeric(12,2) not null check (amount>=0),
  currency_code text not null,
  state text not null default 'pending_review' check (state in ('pending_review','approved','reversed')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(program_id,user_id,trip_id,benefit_type)
);
create index if not exists benefit_redemptions_user_scope_idx
  on public.benefit_redemptions(user_id,channel,zone_id,created_at desc);
alter table public.benefit_redemptions enable row level security;
revoke all on public.benefit_redemptions from public,anon,authenticated;

create table if not exists public.benefit_referral_links (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('preview','production')),
  zone_id uuid not null references public.service_zones(id),
  referrer_id uuid not null references public.users(id),
  referee_id uuid not null references public.users(id),
  program_id uuid not null references public.benefit_programs(id),
  state text not null default 'pending' check (state in ('pending','qualified','reward_review','closed')),
  qualifying_paid_trips integer not null default 0 check (qualifying_paid_trips>=0),
  created_at timestamptz not null default now(),
  qualified_at timestamptz,
  check(referrer_id<>referee_id),
  unique(channel,referee_id)
);
alter table public.benefit_referral_links enable row level security;
revoke all on public.benefit_referral_links from public,anon,authenticated;

create or replace function public.admin_benefit_program_list(
  p_zone_id uuid,p_channel text,p_type text default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_context jsonb;
begin
  if auth.uid() is null or not public.is_admin()
    or p_channel not in ('preview','production')
    or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso a beneficios no autorizado';
  end if;
  v_context:=public.admin_access_context();
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid<>p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  if coalesce(v_context->>'role','') not in ('super_admin','zone_monitor') then
    raise exception 'El módulo de beneficios requiere rol administrativo central';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]'::jsonb)
    from public.benefit_programs p
    where p.zone_id=p_zone_id and p.channel=p_channel
      and (p_type is null or p.program_type=p_type));
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
  if p_type not in ('coupon','activation','loyalty','referral','referral_commission','driver_challenge')
    or p_state not in ('draft','active','paused','closed')
    or length(trim(coalesce(p_name,'')))<2 or length(trim(p_name))>100
    or length(coalesce(p_description,''))>1000
    or p_config is null or jsonb_typeof(p_config)<>'object'
    or (p_ends_at is not null and p_starts_at is not null and p_ends_at<=p_starts_at)
    or not exists(select 1 from public.service_zones z where z.id=p_zone_id and z.active) then
    raise exception 'Configuración del programa inválida';
  end if;
  -- Commercial and financial policy is not finalized: live benefits remain blocked.
  if p_state='active' then
    raise exception 'Los programas requieren revisión de reglas financieras antes de activarse';
  end if;
  if p_id is not null and not exists(select 1 from public.benefit_programs
    where id=p_id and zone_id=p_zone_id and channel=p_channel) then
    raise exception 'No se puede modificar un programa ajeno';
  end if;
  insert into public.benefit_programs(id,channel,zone_id,program_type,name,description,config,state,starts_at,ends_at,created_by)
  values(coalesce(p_id,gen_random_uuid()),p_channel,p_zone_id,p_type,trim(p_name),coalesce(p_description,''),p_config,'draft',p_starts_at,p_ends_at,auth.uid())
  on conflict(id) do update set program_type=excluded.program_type,name=excluded.name,
    description=excluded.description,config=excluded.config,state='draft',
    starts_at=excluded.starts_at,ends_at=excluded.ends_at,updated_at=now()
  returning * into v_record;
  perform public.admin_log_action('upsert','benefit_program',v_record.id::text,
    jsonb_build_object('channel',p_channel,'zone_id',p_zone_id,'type',p_type,'state','draft'));
  return to_jsonb(v_record);
end $$;

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
    from public.users u
    left join public.driver_profiles dp on dp.id=u.id
    join public.service_zones z on z.id=coalesce(u.last_zone_id,dp.zone_id)
    where u.id=v_uid and z.active;
  if v_zone is null then return jsonb_build_object('available',false,'items','[]'::jsonb); end if;
  return jsonb_build_object('available',true,'currency',v_currency,'zone_id',v_zone,
    'items',(select coalesce(jsonb_agg(jsonb_build_object(
      'id',p.id,'type',p.program_type,'name',p.name,'description',p.description,
      'config',p.config,'currency',v_currency,'starts_at',p.starts_at,'ends_at',p.ends_at)
      order by p.created_at desc),'[]'::jsonb)
      from public.benefit_programs p
      where p.zone_id=v_zone and p.channel=p_channel and p.state='active'
        and (p.starts_at is null or p.starts_at<=now())
        and (p.ends_at is null or p.ends_at>now())
        and p.program_type in ('coupon','activation','loyalty','referral')),
    'history',(select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc),'[]'::jsonb)
      from public.benefit_redemptions r where r.user_id=v_uid and r.zone_id=v_zone and r.channel=p_channel));
end $$;

revoke all on function public.admin_benefit_program_list(uuid,text,text) from public,anon;
revoke all on function public.admin_benefit_program_save(uuid,uuid,text,text,text,text,jsonb,text,timestamptz,timestamptz) from public,anon;
revoke all on function public.my_benefits_overview(text) from public,anon;
grant execute on function public.admin_benefit_program_list(uuid,text,text) to authenticated;
grant execute on function public.admin_benefit_program_save(uuid,uuid,text,text,text,text,jsonb,text,timestamptz,timestamptz) to authenticated;
grant execute on function public.my_benefits_overview(text) to authenticated;

commit;
