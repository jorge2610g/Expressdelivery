-- Configuración avanzada administrable desde Adminexpress.
-- Mantiene en base de datos los parámetros operativos que antes quedaban dispersos.

alter table public.app_settings
  add column if not exists allow_pagorut boolean not null default false,
  add column if not exists allow_mercadopago boolean not null default false,
  add column if not exists allow_santander boolean not null default false,
  add column if not exists allow_mach boolean not null default false,
  add column if not exists allow_tenpo boolean not null default false,
  add column if not exists search_timeout_seconds integer not null default 180,
  add column if not exists request_visible_seconds integer not null default 180,
  add column if not exists scheduled_rides_enabled boolean not null default true,
  add column if not exists scheduled_publish_before_minutes integer not null default 30,
  add column if not exists max_driver_request_radius_km numeric not null default 15,
  add column if not exists max_visible_requests_driver integer not null default 20,
  add column if not exists allow_counteroffers boolean not null default true,
  add column if not exists min_driver_offer numeric not null default 1,
  add column if not exists max_driver_offer numeric not null default 9999,
  add column if not exists chat_enabled boolean not null default true,
  add column if not exists calls_enabled boolean not null default true,
  add column if not exists share_trip_enabled boolean not null default true,
  add column if not exists sos_enabled boolean not null default true,
  add column if not exists saved_places_enabled boolean not null default true,
  add column if not exists ratings_enabled boolean not null default true,
  add column if not exists rating_comment_enabled boolean not null default true,
  add column if not exists rating_min integer not null default 1,
  add column if not exists rating_max integer not null default 5,
  add column if not exists maintenance_mode boolean not null default false,
  add column if not exists maintenance_message text,
  add column if not exists minimum_app_version text;

create or replace function public.admin_advanced_settings_update(
  p_allow_pagorut boolean,
  p_allow_mercadopago boolean,
  p_allow_santander boolean,
  p_allow_mach boolean,
  p_allow_tenpo boolean,
  p_search_timeout_seconds integer,
  p_request_visible_seconds integer,
  p_scheduled_rides_enabled boolean,
  p_scheduled_publish_before_minutes integer,
  p_max_driver_request_radius_km numeric,
  p_max_visible_requests_driver integer,
  p_allow_counteroffers boolean,
  p_min_driver_offer numeric,
  p_max_driver_offer numeric,
  p_chat_enabled boolean,
  p_calls_enabled boolean,
  p_share_trip_enabled boolean,
  p_sos_enabled boolean,
  p_saved_places_enabled boolean,
  p_ratings_enabled boolean,
  p_rating_comment_enabled boolean,
  p_rating_min integer,
  p_rating_max integer,
  p_maintenance_mode boolean,
  p_maintenance_message text,
  p_minimum_app_version text
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  update public.app_settings
  set allow_pagorut=coalesce(p_allow_pagorut,false),
      allow_mercadopago=coalesce(p_allow_mercadopago,false),
      allow_santander=coalesce(p_allow_santander,false),
      allow_mach=coalesce(p_allow_mach,false),
      allow_tenpo=coalesce(p_allow_tenpo,false),
      search_timeout_seconds=least(greatest(coalesce(p_search_timeout_seconds,180),30),1800),
      request_visible_seconds=least(greatest(coalesce(p_request_visible_seconds,180),30),1800),
      scheduled_rides_enabled=coalesce(p_scheduled_rides_enabled,true),
      scheduled_publish_before_minutes=least(greatest(coalesce(p_scheduled_publish_before_minutes,30),5),1440),
      max_driver_request_radius_km=least(greatest(coalesce(p_max_driver_request_radius_km,15),1),100),
      max_visible_requests_driver=least(greatest(coalesce(p_max_visible_requests_driver,20),1),100),
      allow_counteroffers=coalesce(p_allow_counteroffers,true),
      min_driver_offer=greatest(coalesce(p_min_driver_offer,1),0),
      max_driver_offer=greatest(coalesce(p_max_driver_offer,9999),coalesce(p_min_driver_offer,1)),
      chat_enabled=coalesce(p_chat_enabled,true),
      calls_enabled=coalesce(p_calls_enabled,true),
      share_trip_enabled=coalesce(p_share_trip_enabled,true),
      sos_enabled=coalesce(p_sos_enabled,true),
      saved_places_enabled=coalesce(p_saved_places_enabled,true),
      ratings_enabled=coalesce(p_ratings_enabled,true),
      rating_comment_enabled=coalesce(p_rating_comment_enabled,true),
      rating_min=least(greatest(coalesce(p_rating_min,1),1),5),
      rating_max=least(greatest(coalesce(p_rating_max,5),1),5),
      maintenance_mode=coalesce(p_maintenance_mode,false),
      maintenance_message=nullif(trim(coalesce(p_maintenance_message,'')),''),
      minimum_app_version=nullif(trim(coalesce(p_minimum_app_version,'')),''),
      updated_at=now()
  where id=true
  returning to_jsonb(app_settings.*) into v_result;

  perform public.admin_log_action(
    'update','advanced_app_settings','global',v_result
  );
  return v_result;
end; $$;