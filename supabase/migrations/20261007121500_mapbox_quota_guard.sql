-- Mapbox monthly quota guard.
-- Keeps a conservative internal meter because Mapbox does not expose public
-- programmatic usage statistics. Counters are shared by Preview + Production
-- because both currently use the same MAPBOX_PUBLIC_TOKEN.
--
-- Defaults mirror the 2026-10 public free tiers used by Express:
--   Directions API: 100,000 requests / billing month
--   Static Tiles API: 200,000 requests / billing month
-- AUTO falls back at 90% to leave a safety buffer for reporting lag, retries,
-- concurrent devices and any requests that our client-side meter may miss.

create table if not exists public.map_provider_quota_control (
  provider text primary key,
  mode text not null default 'auto'
    check (mode in ('auto','mapbox','fallback')),
  period_start date not null
    default date_trunc('month', timezone('utc',now()))::date,
  directions_limit bigint not null default 100000
    check (directions_limit > 0),
  static_tiles_limit bigint not null default 200000
    check (static_tiles_limit > 0),
  directions_used bigint not null default 0
    check (directions_used >= 0),
  static_tiles_used bigint not null default 0
    check (static_tiles_used >= 0),
  warning_ratio numeric(5,4) not null default 0.8000
    check (warning_ratio > 0 and warning_ratio < 1),
  fallback_ratio numeric(5,4) not null default 0.9000
    check (fallback_ratio > warning_ratio and fallback_ratio <= 1),
  updated_at timestamptz not null default now()
);

insert into public.map_provider_quota_control(provider)
values ('mapbox')
on conflict (provider) do nothing;

create table if not exists public.map_provider_usage_report_guard (
  user_id uuid not null references auth.users(id) on delete cascade,
  channel text not null check (channel in ('preview','production')),
  report_day date not null,
  directions_reported integer not null default 0
    check (directions_reported >= 0),
  static_tiles_reported integer not null default 0
    check (static_tiles_reported >= 0),
  updated_at timestamptz not null default now(),
  primary key(user_id,channel,report_day)
);

alter table public.map_provider_quota_control enable row level security;
alter table public.map_provider_usage_report_guard enable row level security;

revoke all on table public.map_provider_quota_control from public,anon,authenticated;
revoke all on table public.map_provider_usage_report_guard from public,anon,authenticated;
grant all on table public.map_provider_quota_control to service_role;
grant all on table public.map_provider_usage_report_guard to service_role;

create or replace function public.mapbox_quota_reset_if_needed()
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_period date:=date_trunc('month', timezone('utc',now()))::date;
begin
  insert into public.map_provider_quota_control(provider,period_start)
  values ('mapbox',v_period)
  on conflict (provider) do nothing;

  update public.map_provider_quota_control
  set period_start=v_period,
      directions_used=0,
      static_tiles_used=0,
      updated_at=now()
  where provider='mapbox'
    and period_start is distinct from v_period;
end;
$$;

revoke all on function public.mapbox_quota_reset_if_needed()
from public,anon,authenticated;
grant execute on function public.mapbox_quota_reset_if_needed()
to service_role;

create or replace function public.mapbox_quota_state(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_row public.map_provider_quota_control%rowtype;
  v_directions_ratio numeric;
  v_tiles_ratio numeric;
  v_allowed boolean;
  v_warning boolean;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  perform public.mapbox_quota_reset_if_needed();

  select * into v_row
  from public.map_provider_quota_control
  where provider='mapbox';

  v_directions_ratio:=
    v_row.directions_used::numeric / greatest(v_row.directions_limit,1);
  v_tiles_ratio:=
    v_row.static_tiles_used::numeric / greatest(v_row.static_tiles_limit,1);

  v_allowed:=case v_row.mode
    when 'fallback' then false
    when 'mapbox' then true
    else greatest(v_directions_ratio,v_tiles_ratio) < v_row.fallback_ratio
  end;

  v_warning:=
    greatest(v_directions_ratio,v_tiles_ratio) >= v_row.warning_ratio;

  return jsonb_build_object(
    'provider','mapbox',
    'channel',v_channel,
    'mode',v_row.mode,
    'period_start',v_row.period_start,
    'period_end',(v_row.period_start + interval '1 month - 1 day')::date,
    'directions_limit',v_row.directions_limit,
    'static_tiles_limit',v_row.static_tiles_limit,
    'directions_used',v_row.directions_used,
    'static_tiles_used',v_row.static_tiles_used,
    'directions_ratio',v_directions_ratio,
    'static_tiles_ratio',v_tiles_ratio,
    'warning_ratio',v_row.warning_ratio,
    'fallback_ratio',v_row.fallback_ratio,
    'warning',v_warning,
    'use_mapbox',v_allowed,
    'updated_at',v_row.updated_at
  );
end;
$$;

revoke all on function public.mapbox_quota_state(text)
from public,anon;
grant execute on function public.mapbox_quota_state(text)
to authenticated,service_role;

create or replace function public.record_mapbox_usage(
  p_channel text default 'production',
  p_directions_units integer default 0,
  p_static_tiles_units integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_day date:=timezone('utc',now())::date;
  v_requested_directions integer:=greatest(0,least(coalesce(p_directions_units,0),20));
  v_requested_tiles integer:=greatest(0,least(coalesce(p_static_tiles_units,0),250));
  v_guard public.map_provider_usage_report_guard%rowtype;
  v_directions_accepted integer:=0;
  v_tiles_accepted integer:=0;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  perform public.mapbox_quota_reset_if_needed();

  insert into public.map_provider_usage_report_guard(
    user_id,channel,report_day
  )
  values(v_uid,v_channel,v_day)
  on conflict (user_id,channel,report_day) do nothing;

  select * into v_guard
  from public.map_provider_usage_report_guard
  where user_id=v_uid
    and channel=v_channel
    and report_day=v_day
  for update;

  -- Anti-abuse ceilings are intentionally much higher than normal usage.
  -- They prevent one authenticated account from exhausting the global meter.
  v_directions_accepted:=least(
    v_requested_directions,
    greatest(0,250-v_guard.directions_reported)
  );
  v_tiles_accepted:=least(
    v_requested_tiles,
    greatest(0,5000-v_guard.static_tiles_reported)
  );

  if v_directions_accepted > 0 or v_tiles_accepted > 0 then
    update public.map_provider_usage_report_guard
    set directions_reported=directions_reported+v_directions_accepted,
        static_tiles_reported=static_tiles_reported+v_tiles_accepted,
        updated_at=now()
    where user_id=v_uid
      and channel=v_channel
      and report_day=v_day;

    update public.map_provider_quota_control
    set directions_used=directions_used+v_directions_accepted,
        static_tiles_used=static_tiles_used+v_tiles_accepted,
        updated_at=now()
    where provider='mapbox';
  end if;

  return public.mapbox_quota_state(v_channel)
    || jsonb_build_object(
      'accepted_directions_units',v_directions_accepted,
      'accepted_static_tiles_units',v_tiles_accepted
    );
end;
$$;

revoke all on function public.record_mapbox_usage(text,integer,integer)
from public,anon;
grant execute on function public.record_mapbox_usage(text,integer,integer)
to authenticated,service_role;

create or replace function public.admin_set_mapbox_quota_control(
  p_mode text default null,
  p_directions_limit bigint default null,
  p_static_tiles_limit bigint default null,
  p_warning_ratio numeric default null,
  p_fallback_ratio numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_mode text:=lower(trim(coalesce(p_mode,'')));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  perform public.mapbox_quota_reset_if_needed();

  update public.map_provider_quota_control
  set mode=case
        when p_mode is null then mode
        when v_mode in ('auto','mapbox','fallback') then v_mode
        else mode
      end,
      directions_limit=coalesce(
        greatest(p_directions_limit,1),
        directions_limit
      ),
      static_tiles_limit=coalesce(
        greatest(p_static_tiles_limit,1),
        static_tiles_limit
      ),
      warning_ratio=coalesce(p_warning_ratio,warning_ratio),
      fallback_ratio=coalesce(p_fallback_ratio,fallback_ratio),
      updated_at=now()
  where provider='mapbox';

  if exists (
    select 1
    from public.map_provider_quota_control
    where provider='mapbox'
      and (
        warning_ratio <= 0
        or warning_ratio >= 1
        or fallback_ratio <= warning_ratio
        or fallback_ratio > 1
      )
  ) then
    raise exception 'Umbrales Mapbox inválidos';
  end if;

  return public.mapbox_quota_state('production');
end;
$$;

revoke all on function public.admin_set_mapbox_quota_control(
  text,bigint,bigint,numeric,numeric
) from public,anon,authenticated;
grant execute on function public.admin_set_mapbox_quota_control(
  text,bigint,bigint,numeric,numeric
) to authenticated,service_role;

comment on table public.map_provider_quota_control is
  'Internal conservative Mapbox quota meter. AUTO switches to fallback before public free-tier limits.';
