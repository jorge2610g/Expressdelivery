-- Trigger helper functions should only be invoked by database triggers.
-- Applied to production Supabase project zgpijrznvaskgcmauwxx on 2026-09-30.

revoke execute on function public.notify_available_ride_to_drivers()
  from public, anon, authenticated;

revoke execute on function public.notify_ride_offer()
  from public, anon, authenticated;
