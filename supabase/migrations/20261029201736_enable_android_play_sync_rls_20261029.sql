-- This table is a server-only mirror of the Google Play Production track.
-- anon/authenticated have no table grants; service_role and the postgres-owned
-- SECURITY DEFINER RPCs are the only intended consumers. Keep RLS enabled with
-- no client policies so future grants do not silently expose release state.
ALTER TABLE public.android_play_production_sync
  ENABLE ROW LEVEL SECURITY;
