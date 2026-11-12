-- Interruptor de llamadas por internet (ZEGO) del admin: app_settings.calls_enabled.
-- Apagado: la ruta responde 'phone' y no se envía ninguna invitación de ZEGO.
create or replace function public.call_route_for_counterpart(p_counterpart_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_me public.user_call_preferences%rowtype;
  v_other public.user_call_preferences%rowtype;
  v_has_trip boolean;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select exists (
    select 1 from public.trips t
    where t.status not in ('completed','cancelled')
      and (
        (t.passenger_id = v_uid and t.driver_id = p_counterpart_id)
        or (t.driver_id = v_uid and t.passenger_id = p_counterpart_id)
      )
  ) into v_has_trip;
  if not v_has_trip then
    raise exception 'No hay un viaje activo con esta persona';
  end if;

  -- Interruptor de llamadas por internet (ZEGO) en el admin.
  -- Apagado: se usa solo el teléfono normal, sin invitación de ZEGO.
  if not coalesce((select s.calls_enabled from public.app_settings s where s.id = true), true) then
    return jsonb_build_object('route', 'phone', 'reason', 'internet_calls_disabled');
  end if;

  select * into v_me from public.user_call_preferences where user_id = v_uid;
  select * into v_other from public.user_call_preferences where user_id = p_counterpart_id;

  -- Dentro de la app (presencia reciente): la llamada funciona sin sobreposición.
  if coalesce(v_other.app_foreground, false)
     and v_other.app_seen_at > now() - interval '90 seconds' then
    return jsonb_build_object('route', 'internet');
  end if;

  -- Fuera de la app: solo con sobreposición de pantalla en ambos lados.
  if coalesce(v_me.overlay_enabled, false) and coalesce(v_other.overlay_enabled, false) then
    return jsonb_build_object('route', 'internet', 'background', true);
  end if;

  return jsonb_build_object('route', 'unavailable', 'reason', 'counterpart_away');
end;
$function$;
