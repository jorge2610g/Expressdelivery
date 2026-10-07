-- Correct partial admin updates for the Mapbox quota guard.
-- Keep existing limits unchanged when a parameter is omitted.

create or replace function public.admin_set_mapbox_quota_control(
  p_mode text default null,
  p_directions_limit bigint default null,
  p_static_tiles_limit bigint default null,
  p_warning_ratio numeric default null,
  p_fallback_ratio numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_mode text:=lower(trim(coalesce(p_mode,'')));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  perform public.mapbox_quota_reset_if_needed();

  update public.map_provider_quota_control
  set mode=case
        when p_mode is null then mode
        when v_mode in ('auto','mapbox','fallback') then v_mode
        else mode
      end,
      directions_limit=case
        when p_directions_limit is null then directions_limit
        else greatest(p_directions_limit,1)
      end,
      static_tiles_limit=case
        when p_static_tiles_limit is null then static_tiles_limit
        else greatest(p_static_tiles_limit,1)
      end,
      warning_ratio=coalesce(p_warning_ratio,warning_ratio),
      fallback_ratio=coalesce(p_fallback_ratio,fallback_ratio),
      updated_at=now()
  where provider='mapbox';

  return public.mapbox_quota_state('production');
end;
$$;

revoke all on function public.admin_set_mapbox_quota_control(
  text,bigint,bigint,numeric,numeric
) from public,anon,authenticated;
grant execute on function public.admin_set_mapbox_quota_control(
  text,bigint,bigint,numeric,numeric
) to authenticated,service_role;
