-- ENTORNO LOCAL AISLADO (PostgreSQL 15 en Docker, 127.0.0.1). Solo datos sintéticos.
-- Esquema mínimo: columnas tomadas de metadatos de producción (sin filas).
-- Diferencias con Supabase: sin RLS, sin extensiones de Supabase, sin triggers de
-- notificación/push/suscripción/pagos, auth.uid() replicado en SQL.
create schema if not exists auth;
create schema if not exists app_private;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
end $$;
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;
create table public.users (id uuid primary key, full_name text, phone text,
  preferred_language text not null default 'es', active_mode text not null default 'passenger',
  account_status text not null default 'active', created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), preferred_payment_method text not null default 'cash');
create table public.driver_profiles (id uuid primary key references public.users(id),
  approval_status text not null default 'approved', online_status text not null default 'online',
  rating numeric not null default 5, completed_trips integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  accepted_payment_methods text[] not null default '{cash}');
create table public.ride_requests (id uuid primary key default gen_random_uuid(),
  passenger_id uuid not null references public.users(id), category text not null default 'ride',
  pickup_address text not null default 'Origen sintético', destination_address text not null default 'Destino sintético',
  proposed_fare numeric not null default 1000, currency text not null default 'CLP',
  payment_method text not null default 'cash', status text not null default 'searching',
  created_at timestamptz not null default now(), expires_at timestamptz,
  updated_at timestamptz not null default now(), pricing_mode text not null default 'fixed',
  demand_multiplier numeric not null default 1, channel text not null default 'production',
  service_mode text not null default 'ride', parcel_photo_paths text[] not null default '{}');
create table public.driver_offers (id uuid primary key default gen_random_uuid(),
  ride_request_id uuid not null references public.ride_requests(id), driver_id uuid not null references public.users(id),
  proposed_fare numeric not null, eta_minutes integer, status text not null default 'pending',
  created_at timestamptz not null default now(), expires_at timestamptz,
  channel text not null default 'production');
create table public.trips (id uuid primary key default gen_random_uuid(),
  ride_request_id uuid not null references public.ride_requests(id), passenger_id uuid not null,
  driver_id uuid not null, status text not null, final_fare numeric,
  payment_status text not null default 'pending', created_at timestamptz not null default now(),
  completed_at timestamptz, boarding_pin text, cancellation_reason text,
  channel text not null default 'production');
create table public.trip_status_history (id bigserial primary key, trip_id uuid not null references public.trips(id),
  status text not null, changed_by uuid not null, created_at timestamptz not null default now());
create table public.notifications (id uuid primary key default gen_random_uuid(), user_id uuid not null,
  title text not null, body text not null, type text not null, is_read boolean not null default false,
  created_at timestamptz not null default now(), metadata jsonb not null default '{}',
  campaign_id uuid, channel text not null default 'production');
create table public.audit_test_groups (id uuid primary key default gen_random_uuid(), name text not null,
  slug text not null, active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.audit_test_group_members (group_id uuid not null references public.audit_test_groups(id),
  user_id uuid not null references public.users(id), role text not null default 'driver',
  enabled boolean not null default true, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), primary key (group_id, user_id));
