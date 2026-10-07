-- Passenger advertising controls.
-- Preview uses Google's official AdMob test IDs. Production stays ad-free
-- until a real AdMob app ID is packaged and a real banner unit ID is set.

alter table public.app_settings
  add column if not exists ads_passenger_enabled boolean not null default true,
  add column if not exists ads_passenger_home_enabled boolean not null default true,
  add column if not exists ads_passenger_trip_enabled boolean not null default true,
  add column if not exists admob_passenger_banner_unit_id text;

create or replace function public.admin_set_passenger_ads(
  p_enabled boolean default null,
  p_home_enabled boolean default null,
  p_trip_enabled boolean default null,
  p_banner_unit_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_banner text:=nullif(trim(coalesce(p_banner_unit_id,'')),'');
  v_result jsonb;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if v_banner is not null
     and v_banner !~ '^ca-app-pub-[0-9]+/[0-9]+$' then
    raise exception 'AdMob banner unit ID inválido';
  end if;

  update public.app_settings
  set ads_passenger_enabled=coalesce(p_enabled,ads_passenger_enabled),
      ads_passenger_home_enabled=coalesce(
        p_home_enabled,
        ads_passenger_home_enabled
      ),
      ads_passenger_trip_enabled=coalesce(
        p_trip_enabled,
        ads_passenger_trip_enabled
      ),
      admob_passenger_banner_unit_id=case
        when p_banner_unit_id is null then admob_passenger_banner_unit_id
        else v_banner
      end,
      updated_at=now()
  where id=true
  returning to_jsonb(app_settings.*) into v_result;

  perform public.admin_log_action(
    'update',
    'passenger_ads',
    'global',
    jsonb_build_object(
      'enabled',v_result->'ads_passenger_enabled',
      'home_enabled',v_result->'ads_passenger_home_enabled',
      'trip_enabled',v_result->'ads_passenger_trip_enabled',
      'banner_configured',
        coalesce(v_result->>'admob_passenger_banner_unit_id','') <> ''
    )
  );

  return v_result;
end;
$$;

revoke all on function public.admin_set_passenger_ads(
  boolean,boolean,boolean,text
) from public,anon;
grant execute on function public.admin_set_passenger_ads(
  boolean,boolean,boolean,text
) to authenticated,service_role;

comment on column public.app_settings.ads_passenger_enabled is
  'Global passenger AdMob switch. Drivers never render passenger ad widgets.';
comment on column public.app_settings.ads_passenger_trip_enabled is
  'Allows passenger ads only while a trip is in progress; not during pickup/cancel stages.';
