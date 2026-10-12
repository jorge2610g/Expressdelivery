-- Driver document expiration, guarded by effective date. Old verified
-- documents without a date remain usable until renewed.
alter table public.driver_document_requirements
  add column if not exists expiration_required boolean not null default false,
  add column if not exists expiration_required_since timestamptz;

-- This is opt-in per document requirement. Do not activate the hard
-- requirement globally until Web/Android clients both support expiry.
-- Existing manually approved drivers stay operational; any KNOWN expired
-- document will still be blocked by the guard below.

-- A single database and Web binary serve two account environments.
-- Enable in Preview first; Production stays unchanged until Preview QA.
create table if not exists public.driver_expiration_channel_settings(
  channel text primary key check (channel in ('preview','production')),
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.driver_expiration_channel_settings(channel,enabled)
values ('preview',true),('production',false)
on conflict(channel) do nothing;
alter table public.driver_expiration_channel_settings enable row level security;
revoke all on public.driver_expiration_channel_settings
  from public,anon,authenticated;

create or replace function public.my_driver_expiration_enforced()
returns boolean language sql stable security definer set search_path=public
as $
  select auth.uid() is not null and coalesce((
    select s.enabled from public.driver_expiration_channel_settings s
    where s.channel=coalesce((
      select b.environment from public.account_runtime_bindings b
      where b.user_id=auth.uid()),'production')
  ),false);
$;
revoke all on function public.my_driver_expiration_enforced()
  from public,anon;
grant execute on function public.my_driver_expiration_enforced()
  to authenticated;

create or replace function public.driver_doc_expiration_end(
  p_date date,p_country text
) returns timestamptz language sql immutable set search_path=public
as $$
  select ((p_date + 1)::timestamp at time zone
    case upper(coalesce(p_country,''))
      when 'CL' then 'America/Santiago'
      when 'BO' then 'America/La_Paz'
      when 'PE' then 'America/Lima'
      else 'UTC' end);
$$;

create or replace function public.driver_has_expired_required_document(
  p_driver_id uuid
) returns boolean language sql stable security definer
set search_path=public
as $$
  select exists(
    select 1 from public.driver_documents d
    join public.driver_document_requirements r on r.id=d.requirement_id
    join public.driver_profiles p on p.id=d.driver_id
    where d.driver_id=p_driver_id
      and exists(
        select 1 from public.driver_expiration_channel_settings s
        where s.enabled and s.channel=coalesce((
          select b.environment from public.account_runtime_bindings b
          where b.user_id=p_driver_id),'production')
      )
      and r.active and r.required
      and (r.country_code is null
        or upper(r.country_code)=upper(coalesce(p.country_code,'')))
      and (r.zone_id is null or r.zone_id=p.zone_id)
      and (
        (d.expires_at is not null and d.expires_at<=now())
        or (r.expiration_required and d.expires_at is null
            and r.expiration_required_since is not null
            and d.created_at>=r.expiration_required_since)
      )
  );
$$;
revoke all on function public.driver_has_expired_required_document(uuid)
  from public,anon,authenticated;

create or replace function public.driver_expiration_online_guard()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if new.online_status='online'
     and public.driver_has_expired_required_document(new.id) then
    if old.online_status is distinct from 'online' then
      raise exception 'Tienes un documento vencido. Renueva y espera aprobación antes de conectarte.';
    end if;
    -- Keep active trips completable, but remove driver from new offers.
    new.online_status:='offline';
  end if;
  return new;
end;
$$;
drop trigger if exists driver_expiration_online_guard on public.driver_profiles;
create trigger driver_expiration_online_guard
before update of online_status,latitude,longitude on public.driver_profiles
for each row execute function public.driver_expiration_online_guard();

-- Full scan is intentionally scoped and idempotent. Optionally schedule
-- this function when pg_cron has been provisioned by the operator.
create or replace function public.expire_online_drivers()
returns integer language plpgsql security definer set search_path=public
as $$
declare v_count integer:=0;
begin
  update public.driver_profiles p set online_status='offline',updated_at=now()
  where p.online_status='online'
    and public.driver_has_expired_required_document(p.id);
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.expire_online_drivers()
  from public,anon,authenticated;

create or replace function public.my_driver_expiration_notices()
returns jsonb language sql stable security definer set search_path=public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'requirement_id',r.id,'label',r.label,
    'expires_at',d.expires_at,
    'days_left',greatest(-999,floor(extract(epoch from
       (d.expires_at-now()))/86400)::integer),
    'expired',d.expires_at<=now()
  ) order by d.expires_at),'[]'::jsonb)
  from public.driver_profiles p
  join public.driver_document_requirements r
    on r.active and r.required
    and (r.country_code is null or upper(r.country_code)=upper(coalesce(p.country_code,'')))
    and (r.zone_id is null or r.zone_id=p.zone_id)
  join public.driver_documents d on d.driver_id=p.id and d.requirement_id=r.id
  where p.id=auth.uid() and public.is_account_active()
    and d.expires_at is not null and d.expires_at<=now()+interval '30 days';
$$;
revoke all on function public.my_driver_expiration_notices()
  from public,anon;
grant execute on function public.my_driver_expiration_notices()
  to authenticated;
