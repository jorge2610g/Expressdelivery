-- Keep the legacy 3-argument marker RPC aligned with the hardened
-- 4-argument implementation so stale/exact locations cannot bypass it.

create or replace function public.nearby_online_driver_markers(
  p_lat numeric,
  p_lng numeric,
  p_radius_km numeric default 5
)
returns jsonb
language sql
security definer
set search_path=public
as $$
  select public.nearby_online_driver_markers(
    p_lat,p_lng,p_radius_km,null::text
  );
$$;

revoke all on function public.nearby_online_driver_markers(
  numeric,numeric,numeric
) from public,anon;
grant execute on function public.nearby_online_driver_markers(
  numeric,numeric,numeric
) to authenticated;
