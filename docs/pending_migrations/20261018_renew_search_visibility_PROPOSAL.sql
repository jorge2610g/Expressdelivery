-- PROPUESTA, NO APLICADA. Requiere autorización explícita y validación en Supabase.
--
-- Problema: «Seguir 3 minutos» llama a renew_ride_request, que vuelve a poner la misma
-- solicitud en 'searching' con expires_at = now() + 3 min. Pero
-- available_ride_requests_for_driver solo lista solicitudes con created_at dentro de
-- request_visible_seconds (180 s). Una solicitud creada hace más de 3 min nunca vuelve a
-- aparecer al conductor, aunque siga abierta. El trigger trg_notify_available_ride sí
-- inserta la notificación «Nueva solicitud disponible», pero al abrirla la lista no trae
-- la solicitud.
--
-- Solución mínima:
--   1) columna search_started_at (NULL en solicitudes existentes, que siguen usando created_at);
--   2) renew_ride_request la marca con now();
--   3) el filtro de visibilidad del conductor usa coalesce(search_started_at, created_at).
-- No cambia created_at (historial), ni expires_at, ni lo que ve el pasajero
-- (passenger_home_state ordena por created_at y no filtra por ventana).
--
-- Antes de aplicar: guardar la definición actual de las tres funciones (pg_get_functiondef)
-- para poder revertir. Rollback: restaurar esas definiciones y
-- alter table public.ride_requests drop column search_started_at;

alter table public.ride_requests
  add column if not exists search_started_at timestamptz;

create or replace function public.renew_ride_request(
  p_ride_request_id uuid,
  p_proposed_fare numeric default null::numeric
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_row public.ride_requests%rowtype;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select *
    into v_row
  from public.ride_requests
  where id = p_ride_request_id
    and passenger_id = v_uid
    and status in ('searching','offers_received')
  for update;

  if v_row.id is null then
    raise exception 'Solicitud no disponible';
  end if;

  update public.driver_offers
  set status = 'declined'
  where ride_request_id = p_ride_request_id
    and status = 'pending';

  delete from public.ride_request_views
  where ride_request_id = p_ride_request_id;

  update public.ride_requests
  set proposed_fare = coalesce(p_proposed_fare, proposed_fare),
      status = 'searching',
      expires_at = now() + interval '3 minutes',
      search_started_at = now(),
      updated_at = now()
  where id = p_ride_request_id
  returning * into v_row;

  return to_jsonb(v_row);
end;
$function$;

create or replace function public.available_ride_requests_for_driver()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_scheduled_before integer := 30;
  v_visible_seconds integer := 180;
  v_max_visible integer := 20;
  v_radius numeric := 15;
  v_lat numeric;
  v_lng numeric;
  v_zone_id uuid;
  v_audit boolean := false;
  v_limit integer := 20;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  if not (
    public.driver_work_permission_allowed(v_uid,'ride',public.admin_user_runtime_environment(v_uid))
    or public.driver_work_permission_allowed(v_uid,'parcel',public.admin_user_runtime_environment(v_uid))
  ) then return '[]'::jsonb; end if;
  if not public.is_approved_online_driver(v_uid) then
    return '[]'::jsonb;
  end if;

  select
    coalesce(scheduled_publish_before_minutes,30),
    coalesce(request_visible_seconds,180),
    coalesce(max_visible_requests_driver,20),
    coalesce(max_driver_request_radius_km,15)
  into v_scheduled_before,v_visible_seconds,v_max_visible,v_radius
  from public.app_settings where id=true;

  select exists(
    select 1
    from public.audit_test_group_members m
    join public.audit_test_groups g on g.id=m.group_id
    where m.user_id=v_uid and m.enabled=true and g.active=true
  ) into v_audit;

  v_limit := case
    when v_audit then 250
    else least(greatest(v_max_visible,1),100)
  end;

  select latitude,longitude,zone_id
    into v_lat,v_lng,v_zone_id
  from public.driver_profiles
  where id=v_uid
  limit 1;

  if v_zone_id is null
     or not public.driver_subscription_allows_dispatch(v_uid) then
    return '[]'::jsonb;
  end if;

  select coalesce(
    jsonb_agg((
      to_jsonb(x)
      - 'parcel_sender_name' - 'parcel_sender_phone'
      - 'parcel_recipient_name' - 'parcel_recipient_phone'
      - 'parcel_photo_paths'
    ) order by x.created_at asc),
    '[]'::jsonb
  )
  into v_result
  from (
    select r.*
    from public.ride_requests r
    where r.status in ('searching','offers_received')
      and r.expires_at > now()
      and r.passenger_id <> v_uid
      and r.zone_id = v_zone_id
      and public.same_operational_scope(r.passenger_id,v_uid)
      and (r.service_mode <> 'parcel' or public.parcel_driver_can_carry(v_uid,r.id))
      and (
        r.scheduled_for is null
        or r.scheduled_for <=
          now()+make_interval(
            mins=>least(greatest(v_scheduled_before,5),1440)
          )
      )
      and (
        r.scheduled_for is not null
        or coalesce(r.search_started_at, r.created_at) >
          now()-make_interval(
            secs=>least(greatest(v_visible_seconds,30),1800)
          )
      )
      and exists(
        select 1
        from public.zone_service_catalog zs
        where zs.zone_id=v_zone_id
          and zs.service_key=r.category
          and zs.enabled=true
          and zs.driver_visible=true
      )
      and case when r.service_mode='parcel' then
        public.driver_work_permission_allowed(
          v_uid,'parcel',public.admin_user_runtime_environment(v_uid))
        and public.express_parcel_zone_available(v_zone_id,r.channel,'driver')
      else
        public.driver_work_permission_allowed(
          v_uid,'ride',public.admin_user_runtime_environment(v_uid))
      end
      and (
        v_lat is null
        or v_lng is null
        or r.pickup_latitude is null
        or r.pickup_longitude is null
        or public.geo_distance_km(
          v_lat,v_lng,r.pickup_latitude,r.pickup_longitude
        ) <= least(greatest(v_radius,1),100)
      )
    order by r.created_at asc
    limit v_limit
  ) x;

  return v_result;
end;
$function$;
