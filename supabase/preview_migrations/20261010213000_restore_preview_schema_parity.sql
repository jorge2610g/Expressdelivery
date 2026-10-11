-- QA-only: restore missing schema objects in the already separate Express Preview project.
-- Destination MUST be xbphilqezmwfjfpdbwad, never production zgpijrznvaskgcmauwxx.
-- Source of compatibility: Production schema introspection 2026-10-10 and
-- 20261009154500_admin_admob_controls.sql,
-- 20261009165500_shared_distance_steps.sql,
-- 20261009172500_exclusive_zone_coverage_mode.sql.
-- This does not create/update payment providers, credentials or live users.
-- Run via Supabase Preview apply_migration ONLY after destination confirmation.

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS admob_android_app_id text,
  ADD COLUMN IF NOT EXISTS admob_publisher_id text,
  ADD COLUMN IF NOT EXISTS ads_passenger_preview_home_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS ads_passenger_preview_trip_enabled boolean NOT NULL DEFAULT true;

ALTER TABLE public.service_zones
  ADD COLUMN IF NOT EXISTS coverage_mode text NOT NULL DEFAULT 'radius';

-- Retain the effective polygon on existing QA zone(s); without this,
-- restoring the new coverage_mode column would change their coverage to radius.
UPDATE public.service_zones AS z
SET coverage_mode = 'polygon'
WHERE z.coverage_mode = 'radius'
  AND EXISTS (
    SELECT 1 FROM public.service_zone_polygons p
    WHERE p.zone_id = z.id AND p.active = true
  );

ALTER TABLE public.service_zones
  DROP CONSTRAINT IF EXISTS service_zones_coverage_mode_check;
ALTER TABLE public.service_zones
  ADD CONSTRAINT service_zones_coverage_mode_check
  CHECK (coverage_mode IN ('radius', 'polygon'));

CREATE TABLE IF NOT EXISTS public.zone_distance_fare_steps (
  zone_id uuid NOT NULL REFERENCES public.service_zones(id) ON DELETE CASCADE,
  service_key text NOT NULL,
  up_to_km numeric(9,2) NOT NULL CHECK (up_to_km > 0),
  fare numeric(12,2) NOT NULL CHECK (fare > 0),
  PRIMARY KEY (zone_id, service_key, up_to_km)
);
CREATE INDEX IF NOT EXISTS zone_distance_fare_steps_lookup
  ON public.zone_distance_fare_steps(zone_id, service_key, up_to_km);
ALTER TABLE public.zone_distance_fare_steps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.zone_distance_fare_steps FROM public, anon, authenticated;
-- Only privileged server-side operations may use the restored table.
-- Missing/changed RPC definitions, RLS policies, triggers and Edge Functions
-- remain a separate review gate, not solved by this schema migration.
