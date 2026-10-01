-- Independent passenger live offer feed + persistent app diagnostics.

create or replace function public.passenger_live_offer_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_ride public.ride_requests%rowtype;
  v_offers jsonb := '[]'::jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select *
    into v_ride
  from public.ride_requests r
  where r.passenger_id = v_uid
    and r.status in ('searching','offers_received')
    and r.expires_at > now() - interval '30 seconds'
  order by r.created_at desc
  limit 1;

  if v_ride.id is not null then
    select coalesce(
      jsonb_agg(
        to_jsonb(o) ||
        jsonb_build_object(
          'driver_profiles',
          jsonb_build_object(
            'id', dp.id,
            'rating', dp.rating,
            'completed_trips', dp.completed_trips,
            'vehicle_summary', dp.vehicle_summary,
            'city', dp.city,
            'approval_status', dp.approval_status,
            'online_status', dp.online_status
          ),
          'driver_user',
          jsonb_build_object(
            'id', u.id,
            'full_name', u.full_name,
            'avatar_url', u.avatar_url
          )
        )
        order by o.created_at asc
      ),
      '[]'::jsonb
    )
      into v_offers
    from public.driver_offers o
    left join public.driver_profiles dp on dp.id = o.driver_id
    left join public.users u on u.id = o.driver_id
    where o.ride_request_id = v_ride.id
      and o.status = 'pending'
      and coalesce(o.expires_at, now() + interval '1 second') > now();
  end if;

  return jsonb_build_object(
    'ride', case when v_ride.id is null then null else to_jsonb(v_ride) end,
    'offers', v_offers,
    'server_now', now()
  );
end;
$function$;

revoke execute on function public.passenger_live_offer_state() from public;
revoke execute on function public.passenger_live_offer_state() from anon;
grant execute on function public.passenger_live_offer_state() to authenticated;

create table if not exists public.app_error_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null references auth.users(id) on delete set null,
  environment text not null default 'preview',
  level text not null default 'error'
    check (level in ('info','warning','error','fatal')),
  source text not null,
  event_name text null,
  message text not null,
  stack_trace text null,
  screen text null,
  app_version text null,
  build_number text null,
  platform text null,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.app_error_logs enable row level security;

drop policy if exists app_error_logs_insert_self on public.app_error_logs;
create policy app_error_logs_insert_self
on public.app_error_logs
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists app_error_logs_select_self on public.app_error_logs;
create policy app_error_logs_select_self
on public.app_error_logs
for select
to authenticated
using (user_id = (select auth.uid()));

revoke all on table public.app_error_logs from anon;
revoke update, delete on table public.app_error_logs from authenticated;
grant insert, select on table public.app_error_logs to authenticated;

create index if not exists app_error_logs_user_created_idx
  on public.app_error_logs (user_id, created_at desc);

create index if not exists app_error_logs_created_idx
  on public.app_error_logs (created_at desc);
