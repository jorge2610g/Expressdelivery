-- Passenger advertising controls.
-- Production stays disabled until real AdMob IDs are configured.
-- Preview is enabled so Google test ads can be validated safely.

alter table public.app_settings
  add column if not exists ads_passenger_enabled boolean not null default false,
  add column if not exists ads_passenger_preview_enabled boolean not null default true,
  add column if not exists ads_passenger_home_enabled boolean not null default true,
  add column if not exists ads_passenger_trip_enabled boolean not null default true;

update public.app_settings
set ads_passenger_enabled = coalesce(ads_passenger_enabled, false),
    ads_passenger_preview_enabled = coalesce(ads_passenger_preview_enabled, true),
    ads_passenger_home_enabled = coalesce(ads_passenger_home_enabled, true),
    ads_passenger_trip_enabled = coalesce(ads_passenger_trip_enabled, true),
    updated_at = now()
where id = true;
