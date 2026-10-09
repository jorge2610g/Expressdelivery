-- Admin-only advertising controls for ONE shared Supabase project.
-- Two web panels remain independent by p_channel; Production defaults OFF.
-- AdMob identifiers are PUBLIC identifiers, never OAuth credentials/API secrets.
alter table public.app_settings
  add column if not exists admob_android_app_id text,
  add column if not exists admob_publisher_id text,
  add column if not exists ads_passenger_preview_home_enabled boolean not null default true,
  add column if not exists ads_passenger_preview_trip_enabled boolean not null default true;

create or replace function public.admin_admob_settings_get(
  p_channel text
) returns jsonb
language plpgsql stable security definer
set search_path = public
as $function$
declare
  v_channel text := lower(trim(coalesce(p_channel, '')));
  v_settings public.app_settings%rowtype;
begin
  if v_channel not in ('preview','production')
     or not public.is_admin()
     or not public.admin_environment_allowed(v_channel) then
    raise exception 'Sin permiso para administrar anuncios en el entorno solicitado';
  end if;
  select * into v_settings from public.app_settings where id = true;
  if not found then
    raise exception 'Configuración de Express no disponible';
  end if;
  return jsonb_build_object(
    'channel', v_channel,
    'enabled', case when v_channel = 'preview'
      then v_settings.ads_passenger_preview_enabled
      else v_settings.ads_passenger_enabled end,
    'home_enabled', case when v_channel = 'preview'
      then v_settings.ads_passenger_preview_home_enabled
      else v_settings.ads_passenger_home_enabled end,
    'trip_enabled', case when v_channel = 'preview'
      then v_settings.ads_passenger_preview_trip_enabled
      else v_settings.ads_passenger_trip_enabled end,
    'admob_android_app_id', case when v_channel = 'production'
      then v_settings.admob_android_app_id else null end,
    'admob_passenger_banner_unit_id', case when v_channel = 'production'
      then v_settings.admob_passenger_banner_unit_id else null end,
    'admob_publisher_id', case when v_channel = 'production'
      then v_settings.admob_publisher_id else null end,
    'updated_at', v_settings.updated_at
  );
end
$function$;

create or replace function public.admin_admob_settings_update(
  p_channel text,
  p_enabled boolean,
  p_home_enabled boolean,
  p_trip_enabled boolean,
  p_android_app_id text default null,
  p_banner_unit_id text default null,
  p_publisher_id text default null
) returns jsonb
language plpgsql security definer
set search_path = public
as $function$
declare
  v_channel text := lower(trim(coalesce(p_channel, '')));
  v_app_id text := nullif(trim(coalesce(p_android_app_id, '')), '');
  v_banner_id text := nullif(trim(coalesce(p_banner_unit_id, '')), '');
  v_publisher_id text := nullif(trim(coalesce(p_publisher_id, '')), '');
begin
  if v_channel not in ('preview','production')
     or not public.is_admin()
     or not public.admin_environment_allowed(v_channel) then
    raise exception 'Sin permiso para cambiar anuncios en el entorno solicitado';
  end if;
  if p_enabled is null or p_home_enabled is null or p_trip_enabled is null then
    raise exception 'Los interruptores deben tener valores válidos';
  end if;

  if v_channel = 'preview' then
    -- Preview never touches real ad IDs, payments, or production ad flags.
    if v_app_id is not null or v_banner_id is not null
       or v_publisher_id is not null then
      raise exception 'Los ID de AdMob solo se administran en Producción';
    end if;
    update public.app_settings
    set ads_passenger_preview_enabled = p_enabled,
        ads_passenger_preview_home_enabled = p_home_enabled,
        ads_passenger_preview_trip_enabled = p_trip_enabled,
        updated_at = now()
    where id = true;
  else
    if v_app_id is not null and
       v_app_id !~ '^ca-app-pub-[0-9]{16}~[0-9]{10}$' then
      raise exception 'ID de aplicación AdMob inválido';
    end if;
    if v_banner_id is not null and
       v_banner_id !~ '^ca-app-pub-[0-9]{16}/[0-9]{10}$' then
      raise exception 'ID de unidad de anuncios inválido';
    end if;
    if v_publisher_id is not null and
       v_publisher_id !~ '^pub-[0-9]{16}$' then
      raise exception 'ID de editor inválido';
    end if;
    if p_enabled and (v_app_id is null or
                      v_banner_id is null or v_publisher_id is null) then
      raise exception 'Completa los tres ID de AdMob antes de activar Producción';
    end if;
    if v_publisher_id is not null and v_app_id is not null and
       substring(v_app_id from 12 for 16) <> substring(v_publisher_id from 5) then
      raise exception 'El ID de aplicación no coincide con el editor AdMob';
    end if;
    if v_publisher_id is not null and v_banner_id is not null and
       substring(v_banner_id from 12 for 16) <> substring(v_publisher_id from 5) then
      raise exception 'El ID de banner no coincide con el editor AdMob';
    end if;
    update public.app_settings
    set ads_passenger_enabled = p_enabled,
        ads_passenger_home_enabled = p_home_enabled,
        ads_passenger_trip_enabled = p_trip_enabled,
        admob_android_app_id = v_app_id,
        admob_passenger_banner_unit_id = v_banner_id,
        admob_publisher_id = v_publisher_id,
        updated_at = now()
    where id = true;
  end if;

  if not found then
    raise exception 'Configuración de Express no disponible';
  end if;
  return public.admin_admob_settings_get(v_channel);
end
$function$;

revoke all on function public.admin_admob_settings_get(text)
from public, anon;
revoke all on function public.admin_admob_settings_update(
  text,boolean,boolean,boolean,text,text,text
) from public, anon;
grant execute on function public.admin_admob_settings_get(text) to authenticated;
grant execute on function public.admin_admob_settings_update(
  text,boolean,boolean,boolean,text,text,text
) to authenticated;

-- No ad enablement is applied by this migration. Existing flags stay intact.
