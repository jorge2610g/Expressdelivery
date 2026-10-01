-- Functional observability for Express ride/push flow.
-- Records only technical identifiers/statuses and avoids addresses, phone numbers
-- and push token contents.

create table if not exists public.app_flow_events (
  id bigint generated always as identity primary key,
  event_type text not null,
  entity_type text not null,
  entity_id text null,
  actor_user_id uuid null,
  passenger_id uuid null,
  driver_id uuid null,
  status text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.app_flow_events enable row level security;
revoke all on table public.app_flow_events from anon, authenticated;

create index if not exists app_flow_events_created_idx
  on public.app_flow_events (created_at desc);
create index if not exists app_flow_events_entity_idx
  on public.app_flow_events (entity_type, entity_id, created_at desc);
create index if not exists app_flow_events_passenger_idx
  on public.app_flow_events (passenger_id, created_at desc);
create index if not exists app_flow_events_driver_idx
  on public.app_flow_events (driver_id, created_at desc);
create index if not exists app_flow_events_type_idx
  on public.app_flow_events (event_type, created_at desc);

-- Live database already has the trigger functions installed. This migration
-- versions the observability table; trigger definitions remain managed by the
-- Supabase migration history for the project.
