-- Exact pg_get_functiondef snapshots, Production before channel-grant guards 2026-10-09.
-- Emergency rollback only. Reverting removes QA-only administrator authorization protection.

-- admin_driver_kyc_bolivia_set_method
CREATE OR REPLACE FUNCTION public.admin_driver_kyc_bolivia_set_method(p_channel text, p_method text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_channel text:=lower(trim(coalesce(p_channel,'')));
  v_method text:=lower(trim(coalesce(p_method,'')));
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in('preview','production') then raise exception 'Canal inválido'; end if;
  if v_method not in('automatic','didit','manual') then
    raise exception 'Método no permitido'; end if;
  insert into public.driver_kyc_method_settings(
    country_code,channel,preferred_method,updated_by
  ) values('BO',v_channel,v_method,auth.uid())
  on conflict(country_code,channel) do update
    set preferred_method=excluded.preferred_method,updated_at=now(),
        updated_by=excluded.updated_by;
  return public.admin_driver_kyc_bolivia_settings(v_channel);
end; $function$;

-- admin_update_driver_priority_settings_v2
CREATE OR REPLACE FUNCTION public.admin_update_driver_priority_settings_v2(p_channel text, p_enabled boolean, p_enforcement_enabled boolean, p_high_min_score numeric, p_medium_min_score numeric, p_rating_weight numeric, p_reviews_weight numeric, p_experience_weight numeric, p_frequency_weight numeric, p_review_target integer, p_experience_trip_target integer, p_frequency_30d_target integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel),''),'preview'));
  v_current jsonb;
  v_next jsonb;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if v_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  if p_high_min_score<=p_medium_min_score then
    raise exception 'El umbral Alta debe ser mayor que el umbral Media';
  end if;
  if coalesce(p_rating_weight,0)+coalesce(p_reviews_weight,0)+
     coalesce(p_experience_weight,0)+coalesce(p_frequency_weight,0)<=0 then
    raise exception 'Los pesos deben sumar más de cero';
  end if;

  if v_channel='preview' then
    v_current := public.driver_priority_settings_for('preview');
    v_next := v_current || jsonb_build_object(
      'preview_enabled',coalesce(p_enabled,false),
      'preview_enforcement_enabled',coalesce(p_enforcement_enabled,false),
      'high_min_score',least(100,greatest(0,p_high_min_score)),
      'medium_min_score',least(100,greatest(0,p_medium_min_score)),
      'rating_weight',greatest(0,p_rating_weight),
      'reviews_weight',greatest(0,p_reviews_weight),
      'experience_weight',greatest(0,p_experience_weight),
      'frequency_weight',greatest(0,p_frequency_weight),
      'review_target',greatest(1,p_review_target),
      'experience_trip_target',greatest(1,p_experience_trip_target),
      'frequency_30d_target',greatest(1,p_frequency_30d_target),
      'updated_at',now()
    );
    perform public.admin_environment_config_upsert(
      'preview','driver_priority_settings','default',v_next
    );
  else
    update public.driver_priority_settings
    set production_enabled=coalesce(p_enabled,false),
        production_enforcement_enabled=coalesce(p_enforcement_enabled,false),
        high_min_score=least(100,greatest(0,p_high_min_score)),
        medium_min_score=least(100,greatest(0,p_medium_min_score)),
        rating_weight=greatest(0,p_rating_weight),
        reviews_weight=greatest(0,p_reviews_weight),
        experience_weight=greatest(0,p_experience_weight),
        frequency_weight=greatest(0,p_frequency_weight),
        review_target=greatest(1,p_review_target),
        experience_trip_target=greatest(1,p_experience_trip_target),
        frequency_30d_target=greatest(1,p_frequency_30d_target),
        updated_at=now()
    where id=true;

    perform public.admin_log_action(
      'update','driver_priority_settings','production',
      jsonb_build_object(
        'environment','production',
        'production_enabled',p_enabled,
        'production_enforcement_enabled',p_enforcement_enabled
      )
    );
  end if;

  return public.admin_driver_priority_state_v2(v_channel);
end;
$function$;

-- admin_update_dynamic_pricing_settings
CREATE OR REPLACE FUNCTION public.admin_update_dynamic_pricing_settings(p_channel text, p_enabled boolean, p_low_ratio numeric DEFAULT NULL::numeric, p_low_multiplier numeric DEFAULT NULL::numeric, p_low_min_drivers integer DEFAULT NULL::integer, p_radius_km numeric DEFAULT NULL::numeric, p_window_minutes integer DEFAULT NULL::integer, p_min_requests integer DEFAULT NULL::integer, p_elevated_ratio numeric DEFAULT NULL::numeric, p_high_ratio numeric DEFAULT NULL::numeric, p_critical_ratio numeric DEFAULT NULL::numeric, p_elevated_multiplier numeric DEFAULT NULL::numeric, p_high_multiplier numeric DEFAULT NULL::numeric, p_critical_multiplier numeric DEFAULT NULL::numeric, p_max_multiplier numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_row public.dynamic_pricing_channel_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  update public.dynamic_pricing_channel_settings
  set enabled=coalesce(p_enabled,enabled),
      low_ratio=coalesce(p_low_ratio,low_ratio),
      low_multiplier=coalesce(p_low_multiplier,low_multiplier),
      low_min_drivers=coalesce(p_low_min_drivers,low_min_drivers),
      radius_km=coalesce(p_radius_km,radius_km),
      window_minutes=coalesce(p_window_minutes,window_minutes),
      min_requests=coalesce(p_min_requests,min_requests),
      elevated_ratio=coalesce(p_elevated_ratio,elevated_ratio),
      high_ratio=coalesce(p_high_ratio,high_ratio),
      critical_ratio=coalesce(p_critical_ratio,critical_ratio),
      elevated_multiplier=coalesce(p_elevated_multiplier,elevated_multiplier),
      high_multiplier=coalesce(p_high_multiplier,high_multiplier),
      critical_multiplier=coalesce(p_critical_multiplier,critical_multiplier),
      max_multiplier=coalesce(p_max_multiplier,max_multiplier),
      updated_at=now(),
      updated_by=auth.uid()
  where channel=v_channel
  returning * into v_row;

  if not found then
    raise exception 'Configuración de demanda dinámica no disponible para %', v_channel;
  end if;

  update public.dynamic_pricing_settings
  set preview_enabled=case
        when v_channel='preview' then v_row.enabled
        else preview_enabled
      end,
      production_enabled=case
        when v_channel='production' then v_row.enabled
        else production_enabled
      end,
      updated_at=now(),
      updated_by=auth.uid()
  where id=true;

  return to_jsonb(v_row);
end;
$function$;
