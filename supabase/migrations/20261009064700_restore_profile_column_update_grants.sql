-- Express 2026-10-09: repair Preview's incomplete permissions bootstrap.
-- It created columns and RLS policies but omitted 12 *column-scoped* GRANTs
-- already present in the Production schema. The existing mobile APK therefore
-- failed with PostgREST 42501 when changing driver offline/online status.
--
-- Keep Preview / Production on the same SQL contract. No table-wide UPDATE.
-- driver_profiles: exactly the eight columns writable by authenticated in Prod.
GRANT UPDATE (
  city, heading_degrees, latitude, license_number,
  longitude, online_status, updated_at, vehicle_summary
) ON public.driver_profiles TO authenticated;

-- public.users: restore the four personal-profile fields writable in Prod.
-- active_mode + updated_at are granted by the preceding migration in this PR
-- and are already granted in existing Production. This is idempotent.
GRANT UPDATE (avatar_url, full_name, phone, preferred_language)
  ON public.users TO authenticated;

-- Verify no global UPDATE privilege or ability to approve drivers/accounts.
DO $check$
BEGIN
  IF NOT has_column_privilege('authenticated','public.driver_profiles','online_status','UPDATE')
     OR NOT has_column_privilege('authenticated','public.driver_profiles','updated_at','UPDATE')
     OR NOT has_column_privilege('authenticated','public.users','phone','UPDATE')
     OR has_table_privilege('authenticated','public.driver_profiles','UPDATE')
     OR has_table_privilege('authenticated','public.users','UPDATE')
     OR has_column_privilege('authenticated','public.driver_profiles','approval_status','UPDATE')
     OR has_column_privilege('authenticated','public.users','account_status','UPDATE')
  THEN
    RAISE EXCEPTION 'Express driver/public profile grants drifted from least-privilege schema';
  END IF;
END;
$check$;
