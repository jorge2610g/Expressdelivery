-- Multi-provider phone OTP router for Express.
-- Firebase reserves the first 10 daily sends per Firebase project; after that,
-- the Edge Function routes Chile to LETEL and Bolivia to Unimatrix.
-- Provider credentials never live in Postgres or the client.

create table if not exists public.phone_otp_provider_usage (
  provider_key text not null,
  usage_date date not null,
  sent_count integer not null default 0 check (sent_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (provider_key, usage_date)
);

alter table public.phone_otp_provider_usage enable row level security;

create table if not exists public.phone_otp_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  channel text not null check (channel in ('preview','production')),
  country_code text not null check (country_code in ('CL','BO')),
  phone text not null check (phone ~ '^\\+[1-9][0-9]{6,14}$'),
  provider text not null check (provider in ('firebase','letel','unimatrix')),
  provider_key text,
  provider_message_id text,
  code_hash text,
  status text not null default 'reserved'
    check (status in ('reserved','sent','verified','failed','expired')),
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 10),
  expires_at timestamptz not null,
  sent_at timestamptz,
  verified_at timestamptz,
  error_code text,
  provider_meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists phone_otp_challenges_user_created_idx
  on public.phone_otp_challenges(user_id, created_at desc);
create index if not exists phone_otp_challenges_phone_created_idx
  on public.phone_otp_challenges(phone, created_at desc);
create index if not exists phone_otp_challenges_status_expires_idx
  on public.phone_otp_challenges(status, expires_at);

alter table public.phone_otp_challenges enable row level security;

create or replace function public.reserve_phone_otp_daily_slot(
  p_provider_key text,
  p_limit integer default 10
)
returns jsonb
language plpgsql
security invoker
set search_path=public
as $$
declare
  v_key text:=trim(coalesce(p_provider_key,''));
  v_limit integer:=coalesce(p_limit,10);
  v_day date:=(now() at time zone 'UTC')::date;
  v_count integer;
begin
  if v_key='' or length(v_key)>180 then
    raise exception 'provider_key inválido';
  end if;
  if v_limit<1 or v_limit>100 then
    raise exception 'límite diario inválido';
  end if;

  insert into public.phone_otp_provider_usage(
    provider_key, usage_date, sent_count, updated_at
  )
  values(v_key, v_day, 1, now())
  on conflict(provider_key, usage_date)
  do update
    set sent_count=public.phone_otp_provider_usage.sent_count+1,
        updated_at=now()
    where public.phone_otp_provider_usage.sent_count < v_limit
  returning sent_count into v_count;

  if v_count is null then
    select sent_count into v_count
    from public.phone_otp_provider_usage
    where provider_key=v_key and usage_date=v_day;

    return jsonb_build_object(
      'reserved',false,
      'provider_key',v_key,
      'date',v_day,
      'used',coalesce(v_count,0),
      'limit',v_limit
    );
  end if;

  return jsonb_build_object(
    'reserved',true,
    'provider_key',v_key,
    'date',v_day,
    'used',v_count,
    'remaining',greatest(v_limit-v_count,0),
    'limit',v_limit
  );
end;
$$;

comment on table public.phone_otp_provider_usage is
  'Server-only counters used by the OTP router to cap Firebase at the free daily allowance.';
comment on table public.phone_otp_challenges is
  'Server-only audit/challenge records for Firebase, LETEL and Unimatrix phone verification.';
