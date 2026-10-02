-- Allow authenticated drivers to update only their own operational profile fields.
-- Row ownership remains enforced by the existing drivers_update_self RLS policy.
grant update (
  online_status,
  updated_at,
  license_number,
  vehicle_summary,
  city,
  latitude,
  longitude,
  heading_degrees
) on table public.driver_profiles to authenticated;
