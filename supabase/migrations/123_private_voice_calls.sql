-- Private in-app voice calls for active Express trips.
-- Phone numbers remain private; only opaque ZEGOCLOUD identities are exposed to clients.

create table if not exists public.private_voice_calls (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  channel text not null check (channel in ('preview','production')),
  call_id text not null unique,
  caller_id uuid not null references public.users(id) on delete cascade,
  callee_id uuid not null references public.users(id) on delete cascade,
  caller_role text not null check (caller_role in ('passenger','driver')),
  provider text not null default 'zegocloud',
  status text not null default 'initiated'
    check (status in ('initiated','accepted','declined','missed','cancelled','ended','failed')),
  initiated_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  check (caller_id <> callee_id)
);

create index if not exists private_voice_calls_trip_id_idx
  on public.private_voice_calls(trip_id, initiated_at desc);

create index if not exists private_voice_calls_participants_idx
  on public.private_voice_calls(caller_id, callee_id, initiated_at desc);

alter table public.private_voice_calls enable row level security;

drop policy if exists private_voice_calls_participant_read on public.private_voice_calls;
create policy private_voice_calls_participant_read
  on public.private_voice_calls
  for select
  to authenticated
  using (
    caller_id = (select auth.uid())
    or callee_id = (select auth.uid())
  );

revoke all on public.private_voice_calls from anon;
revoke insert, update, delete on public.private_voice_calls from authenticated;
grant select on public.private_voice_calls to authenticated;

comment on table public.private_voice_calls is
  'Metadata-only audit trail for privacy-preserving in-app voice calls. Audio is not recorded.';
