-- Bolivia only, Preview and Production separated. No Chile policy is changed.
-- A Didit request reserves a slot BEFORE contacting the paid provider.
-- Counts include Didit sessions already recorded during the Bolivia-local month.
-- Each month starts at 00:00 in America/La_Paz.
create table if not exists public.driver_kyc_method_settings (
  country_code text not null references public.service_countries(country_code),
  channel text not null check (channel in ('preview','production')),
  preferred_method text not null default 'automatic'
    check (preferred_method in ('automatic','didit','manual')),
  didit_monthly_limit integer not null default 30 check (didit_monthly_limit=30),
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key(country_code,channel)
);
create table if not exists public.driver_kyc_didit_monthly_usage (
  country_code text not null,
  channel text not null check(channel in('preview','production')),
  month_start date not null,
  used_count integer not null default 0 check(used_count>=0),
  updated_at timestamptz not null default now(),
  primary key(country_code,channel,month_start)
);
create table if not exists public.driver_kyc_didit_claims (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  country_code text not null default 'BO',
  channel text not null check(channel in('preview','production')),
  month_start date not null,
  status text not null default 'reserved'
    check(status in('reserved','started','released')),
  provider_session_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists driver_kyc_claim_user_idx
  on public.driver_kyc_didit_claims(user_id,channel,month_start,created_at desc);
create unique index if not exists driver_kyc_claim_session_uidx
  on public.driver_kyc_didit_claims(provider_session_id)
  where provider_session_id is not null;
alter table public.driver_kyc_method_settings enable row level security;
alter table public.driver_kyc_didit_monthly_usage enable row level security;
alter table public.driver_kyc_didit_claims enable row level security;
revoke all on public.driver_kyc_method_settings,
  public.driver_kyc_didit_monthly_usage,
  public.driver_kyc_didit_claims from anon,authenticated;
insert into public.driver_kyc_method_settings(country_code,channel,preferred_method)
values ('BO','production','automatic'),('BO','preview','automatic')
on conflict(country_code,channel) do nothing;

-- Read-only authenticated routing. The latest existing Didit attempt can finish
-- even after the country budget reaches 30; no new paid session is allowed.
create or replace function public.driver_kyc_bolivia_state(
  p_country_code text default 'BO',
  p_channel text default 'production'
)
returns jsonb language plpgsql security definer stable
set search_path=public as $$
declare
  v_user uuid:=auth.uid();
  v_channel text:=lower(trim(coalesce(p_channel,'production')));
  v_country text:=upper(trim(coalesce(p_country_code,'')));
  v_month date:=(date_trunc('month',now() at time zone 'America/La_Paz'))::date;
  v_settings public.driver_kyc_method_settings%rowtype;
  v_used integer;
  v_latest text;
  v_has_verified boolean:=false;
  v_manual_active boolean:=false;
  v_didit_enabled boolean:=false;
  v_method text;
begin
  if v_user is null then raise exception 'Autenticación requerida'; end if;
  if v_channel not in ('preview','production') then raise exception 'Canal inválido'; end if;
  if v_channel='preview' and not (public.is_admin() or public.is_active_audit_user(v_user))
    then raise exception 'Preview reservado a QA'; end if;
  if v_channel='production' and public.is_active_audit_user(v_user) and not public.is_admin()
    then raise exception 'Cuenta QA no autorizada en producción'; end if;
  if v_country <> 'BO' then
    return jsonb_build_object('configured',false,'country_code',v_country);
  end if;
  select * into v_settings from public.driver_kyc_method_settings
  where country_code=v_country and channel=v_channel;
  select coalesce(s.didit_enabled,false) into v_didit_enabled
  from public.identity_verification_country_settings s
  where s.country_code=v_country;
  select coalesce(q.used_count, (
      select count(*)::integer from public.identity_verifications i
      where i.provider='didit' and i.document_type='driver_identity'
        and i.country_code='BO'
        and i.provider_environment=case when v_channel='preview' then 'sandbox' else 'production' end
        and (i.created_at at time zone 'America/La_Paz')::date>=v_month
        and (i.created_at at time zone 'America/La_Paz')::date<(v_month+interval '1 month')::date
    )) into v_used
  from (select 1) base left join public.driver_kyc_didit_monthly_usage q
   on q.country_code=v_country and q.channel=v_channel and q.month_start=v_month;

  select status into v_latest from public.identity_verifications i
  where i.user_id=v_user and i.provider='didit'
    and i.subject_role='driver' and i.document_type='driver_identity'
    and i.country_code=v_country
    and i.provider_environment=case when v_channel='preview' then 'sandbox' else 'production' end
  order by i.created_at desc,i.id desc limit 1;
  v_has_verified:=v_latest='verified';
  select exists(
    select 1 from public.driver_documents d
    join public.driver_document_requirements r on r.id=d.requirement_id
    where d.driver_id=v_user and d.verification_method='manual'
      and d.status in('pending','verified','rejected')
      and lower(r.code) in ('identity_card','national_id','id_card',
        'identity','carnet','cedula','cédula')
  ) into v_manual_active;
  v_method:=case
    when v_manual_active then 'manual'
    when v_has_verified or v_latest in ('pending','processing','review') then 'didit'
    when coalesce(v_settings.preferred_method,'automatic')='manual' then 'manual'
    when not coalesce(v_didit_enabled,false) then 'manual'
    when v_used>=30 then 'manual'
    else 'didit'
  end;

  return jsonb_build_object(
    'configured',true,'country_code','BO','channel',v_channel,
    'preferred_method',coalesce(v_settings.preferred_method,'automatic'),
    'effective_method',v_method,
    'didit_enabled',coalesce(v_didit_enabled,false),
    'month_start',v_month,
    'used',v_used,'limit',30,'remaining',greatest(0,30-v_used),
    'previous_didit_status',v_latest,
    'manual_existing',v_manual_active
  );
end; $$;
revoke all on function public.driver_kyc_bolivia_state(text,text) from public,anon;
grant execute on function public.driver_kyc_bolivia_state(text,text) to authenticated;

-- Atomic quota reservation under a database lock; the first request seeds its
-- baseline with this month's existing sessions (including failed/review ones).
create or replace function public.driver_kyc_bolivia_reserve_didit(
 p_user_id uuid,
 p_channel text default 'production'
)
returns jsonb language plpgsql security definer
set search_path=public as $$
declare
  v_user uuid:=p_user_id;
  v_channel text:=lower(trim(coalesce(p_channel,'production')));
  v_month date:=(date_trunc('month',now() at time zone 'America/La_Paz'))::date;
  v_used integer;
  v_latest text;
  v_mode text;
  v_didit_enabled boolean;
  v_claim uuid;
begin
  -- Never let arbitrary authenticated clients exhaust everyone's free quota.
  if auth.role() <> 'service_role' then raise exception 'Solo servidor'; end if;
  if v_user is null then raise exception 'Usuario requerido'; end if;
  if v_channel not in('preview','production') then raise exception 'Canal inválido'; end if;
  if v_channel='preview' and not public.is_active_audit_user(v_user) then
    raise exception 'Cuenta QA requerida'; end if;
  if v_channel='production' and public.is_active_audit_user(v_user) then
    raise exception 'Cuenta QA no permitida en producción'; end if;
  perform pg_advisory_xact_lock(hashtext('express_kyc_BO_'||v_channel||v_month::text));

  select preferred_method into v_mode from public.driver_kyc_method_settings
    where country_code='BO' and channel=v_channel;
  select didit_enabled into v_didit_enabled
  from public.identity_verification_country_settings where country_code='BO';
  if coalesce(v_mode,'automatic')='manual' or not coalesce(v_didit_enabled,false) then
    return jsonb_build_object('ok',false,'code','manual_kyc_required');
  end if;

  select status into v_latest from public.identity_verifications i
  where i.user_id=v_user and i.provider='didit' and i.subject_role='driver'
    and i.document_type='driver_identity' and i.country_code='BO'
    and i.provider_environment=case when v_channel='preview'
      then 'sandbox' else 'production' end
  order by i.created_at desc,i.id desc limit 1;
  if v_latest='verified' then
    return jsonb_build_object('ok',false,'code','already_verified');
  end if;
  if exists(
    select 1 from public.driver_documents d
    join public.driver_document_requirements r on r.id=d.requirement_id
    where d.driver_id=v_user and d.verification_method='manual'
      and d.status in('pending','verified','rejected')
      and lower(r.code) in('identity_card','national_id','id_card',
        'identity','carnet','cedula','cédula')
  ) then
    return jsonb_build_object('ok',false,'code','manual_kyc_in_progress');
  end if;

  -- Reuse a fresh reservation for the same user to avoid double-charging
  -- rapid taps; other users still get at most the remaining global slots.
  select id into v_claim from public.driver_kyc_didit_claims c
  where c.user_id=v_user and c.country_code='BO' and c.channel=v_channel
    and c.month_start=v_month and c.status='reserved'
    and c.created_at>=now()-interval '3 minutes'
  order by created_at desc limit 1;
  if v_claim is not null then
    return jsonb_build_object('ok',true,'claim_id',v_claim,'reused',true);
  end if;

  select coalesce(q.used_count, (
    select count(*)::integer from public.identity_verifications i
    where i.provider='didit' and i.document_type='driver_identity'
      and i.country_code='BO'
      and i.provider_environment=case when v_channel='preview'
        then 'sandbox' else 'production' end
      and (i.created_at at time zone 'America/La_Paz')::date>=v_month
      and (i.created_at at time zone 'America/La_Paz')::date<(v_month+interval '1 month')::date
  )) into v_used from (select 1) b
    left join public.driver_kyc_didit_monthly_usage q
    on q.country_code='BO' and q.channel=v_channel and q.month_start=v_month;
  if v_used>=30 then
    return jsonb_build_object('ok',false,'code','quota_exhausted',
      'used',v_used,'limit',30,'method','manual');
  end if;
  insert into public.driver_kyc_didit_monthly_usage(
    country_code,channel,month_start,used_count
  ) values('BO',v_channel,v_month,v_used+1)
    on conflict(country_code,channel,month_start)
    do update set used_count=excluded.used_count,updated_at=now();
  insert into public.driver_kyc_didit_claims(user_id,country_code,channel,month_start)
    values(v_user,'BO',v_channel,v_month) returning id into v_claim;
  return jsonb_build_object('ok',true,'claim_id',v_claim,'reused',false,
    'used',v_used+1,'limit',30);
end; $$;
revoke all on function public.driver_kyc_bolivia_reserve_didit(uuid,text)
  from public,anon,authenticated;
grant execute on function public.driver_kyc_bolivia_reserve_didit(uuid,text)
  to service_role;

-- Only the trusted server can finalize or refund a slot; clients cannot forge
-- sessions or artificially replenish the monthly quota.
create or replace function public.driver_kyc_bolivia_set_claim(
  p_claim_id uuid,p_status text,p_provider_session_id text default null
)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_claim public.driver_kyc_didit_claims%rowtype;
begin
  if auth.role() <> 'service_role' then raise exception 'Solo servidor'; end if;
  if p_status not in('started','released') then raise exception 'Estado inválido'; end if;
  select * into v_claim from public.driver_kyc_didit_claims
    where id=p_claim_id for update;
  if v_claim.id is null or v_claim.status<>'reserved' then return; end if;
  if p_status='started' then
    if nullif(trim(coalesce(p_provider_session_id,'')),'') is null
       then raise exception 'Sesión requerida'; end if;
    update public.driver_kyc_didit_claims
      set status='started',provider_session_id=p_provider_session_id,updated_at=now()
    where id=p_claim_id;
  else
    perform pg_advisory_xact_lock(hashtext(
      'express_kyc_BO_'||v_claim.channel||v_claim.month_start::text));
    update public.driver_kyc_didit_claims set status='released',updated_at=now()
      where id=p_claim_id and status='reserved';
    update public.driver_kyc_didit_monthly_usage
      set used_count=greatest(0,used_count-1),updated_at=now()
      where country_code='BO' and channel=v_claim.channel
        and month_start=v_claim.month_start;
  end if;
end; $$;
revoke all on function public.driver_kyc_bolivia_set_claim(uuid,text,text) from public,anon,authenticated;
grant execute on function public.driver_kyc_bolivia_set_claim(uuid,text,text) to service_role;

create or replace function public.admin_driver_kyc_bolivia_settings(
 p_channel text default 'production'
)
returns jsonb language plpgsql security definer stable set search_path=public as $$
declare v_channel text:=lower(trim(coalesce(p_channel,'production')));
  v_mode text;
  v_used integer;
  v_month date:=(date_trunc('month',now() at time zone 'America/La_Paz'))::date;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in('preview','production') then raise exception 'Canal inválido'; end if;
  select preferred_method into v_mode from public.driver_kyc_method_settings
   where country_code='BO' and channel=v_channel;
  select coalesce(q.used_count, (
    select count(*)::integer from public.identity_verifications i
    where i.country_code='BO' and i.provider='didit'
      and i.document_type='driver_identity'
      and i.provider_environment=case when v_channel='preview' then 'sandbox' else 'production' end
      and (i.created_at at time zone 'America/La_Paz')::date>=v_month
      and (i.created_at at time zone 'America/La_Paz')::date<(v_month+interval '1 month')::date
  )) into v_used from (select 1) b
    left join public.driver_kyc_didit_monthly_usage q
    on q.country_code='BO' and q.channel=v_channel and q.month_start=v_month;
  return jsonb_build_object('country_code','BO','channel',v_channel,
    'preferred_method',coalesce(v_mode,'automatic'),
    'used',v_used,'limit',30,'remaining',greatest(0,30-v_used),
    'month_start',v_month);
end; $$;
revoke all on function public.admin_driver_kyc_bolivia_settings(text) from public,anon;
grant execute on function public.admin_driver_kyc_bolivia_settings(text) to authenticated;

create or replace function public.admin_driver_kyc_bolivia_set_method(
 p_channel text,p_method text
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_channel text:=lower(trim(coalesce(p_channel,'')));
  v_method text:=lower(trim(coalesce(p_method,'')));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in('preview','production') then raise exception 'Canal inválido'; end if;
  if v_method not in('automatic','didit','manual') then
    raise exception 'Método no permitido'; end if;
  insert into public.driver_kyc_method_settings(
    country_code,channel,preferred_method,updated_by
  ) values('BO',v_channel,v_method,auth.uid())
  on conflict(country_code,channel) do update
    set preferred_method=excluded.preferred_method,updated_at=now(),
        updated_by=excluded.updated_by;
  return public.admin_driver_kyc_bolivia_settings(v_channel);
end; $$;
revoke all on function public.admin_driver_kyc_bolivia_set_method(text,text) from public,anon;
grant execute on function public.admin_driver_kyc_bolivia_set_method(text,text) to authenticated;
