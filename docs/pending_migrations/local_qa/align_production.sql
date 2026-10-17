-- Tabla de entorno por cuenta usada por same_operational_scope (columnas de producción).
create table if not exists public.account_runtime_bindings (
  user_id uuid primary key references public.users(id),
  environment text not null,
  source text not null,
  bound_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Alineación del esquema local con producción (solo entorno local).
-- Triggers que producción NO tiene (se retiran):
drop trigger if exists driver_offers_require_verified_phone on public.driver_offers;
drop trigger if exists ride_requests_require_verified_phone on public.ride_requests;
-- Triggers con push/notificación externa (se excluyen):
drop trigger if exists trg_notify_ride_offer on public.driver_offers;
drop trigger if exists trg_notify_available_ride on public.ride_requests;
-- Triggers exclusivos de Envíos con dependencias no replicadas (se excluyen):
drop trigger if exists guard_parcel_ride_offer_permission on public.driver_offers;
drop trigger if exists guard_parcel_trip_assignment on public.trips;
-- Columnas de producción usadas por triggers y funciones:
alter table public.ride_requests add column if not exists parcel_kind text;
alter table public.ride_requests add column if not exists parcel_sender_name text;
alter table public.ride_requests add column if not exists parcel_sender_phone text;
alter table public.ride_requests add column if not exists parcel_recipient_name text;
alter table public.ride_requests add column if not exists parcel_recipient_phone text;
alter table public.ride_requests add column if not exists parcel_details text;
alter table public.ride_requests add column if not exists scheduled_for timestamptz;
alter table public.ride_requests add column if not exists zone_id uuid;
alter table public.driver_profiles add column if not exists latitude numeric;
alter table public.driver_profiles add column if not exists longitude numeric;
alter table public.driver_profiles add column if not exists heading_degrees numeric;
alter table public.driver_profiles add column if not exists zone_id uuid;
alter table public.driver_profiles add column if not exists country_code text;
alter table public.driver_profiles add column if not exists location_updated_at timestamptz;
-- Restricciones de producción (nombres y valores):
alter table public.ride_requests drop constraint if exists ride_requests_channel_check;
alter table public.ride_requests add constraint ride_requests_channel_check check (channel = any (array['preview'::text,'production'::text]));
alter table public.ride_requests drop constraint if exists ride_requests_service_mode_check;
alter table public.ride_requests add constraint ride_requests_service_mode_check check (service_mode = any (array['taxi'::text,'parcel'::text]));
alter table public.ride_requests drop constraint if exists ride_requests_status_check;
alter table public.ride_requests add constraint ride_requests_status_check check (status = any (array['searching'::text,'offers_received'::text,'driver_selected'::text,'cancelled'::text,'expired'::text]));
alter table public.driver_offers drop constraint if exists driver_offers_channel_check;
alter table public.driver_offers add constraint driver_offers_channel_check check (channel = any (array['preview'::text,'production'::text]));
alter table public.driver_offers drop constraint if exists driver_offers_status_check;
alter table public.driver_offers add constraint driver_offers_status_check check (status = any (array['pending'::text,'selected'::text,'declined'::text,'expired'::text]));
alter table public.trips drop constraint if exists trips_channel_check;
alter table public.trips add constraint trips_channel_check check (channel = any (array['preview'::text,'production'::text]));
-- Ajustes globales de producción (una sola fila). Valores de producción en 2026-10-16:
-- offer_timeout_seconds=20, search_timeout_seconds=180. Otros con defaults de migraciones.
create table if not exists public.app_settings (
  id boolean primary key default true,
  offer_timeout_seconds integer not null default 20,
  search_timeout_seconds integer not null default 180,
  request_visible_seconds integer not null default 180,
  max_visible_requests_driver integer not null default 20,
  scheduled_publish_before_minutes integer not null default 30,
  max_driver_request_radius_km numeric not null default 15,
  min_driver_offer numeric not null default 1,
  max_driver_offer numeric not null default 9999,
  updated_at timestamptz not null default now()
);
insert into public.app_settings(id) values (true) on conflict (id) do nothing;
