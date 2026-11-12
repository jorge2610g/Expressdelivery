-- Resumen del pasajero en las solicitudes que el conductor ve antes de aceptar u ofertar.
--
-- Cambio aditivo: se reemplaza available_ride_requests_for_driver_v4(text) con la
-- misma firma, el mismo cuerpo y los mismos permisos, y solo se agregan cuatro
-- campos por solicitud:
--   passenger_first_name     primer nombre de users.full_name (o null)
--   passenger_avatar_url     users.avatar_url (o null)
--   passenger_rating         promedio de ratings.score del pasajero (o null sin calificaciones)
--   passenger_rating_count   cantidad de calificaciones del pasajero (0 si no tiene)
--
-- No incluye teléfono: sigue reservado a trip_counterpart_phone durante el viaje activo.
-- No modifica v3/v2/base, RLS, tarifas ni datos. Migración nueva: no edita migraciones aplicadas.

create or replace function public.available_ride_requests_for_driver_v4(
  p_channel text default 'production'::text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_raw jsonb;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  v_raw := public.available_ride_requests_for_driver_v3(p_channel);
  if v_raw is null or jsonb_typeof(v_raw) <> 'array' then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(
    e
    || jsonb_build_object('quick_offer_steps',
         public.driver_quick_offer_steps(
           coalesce(
             nullif(e->>'zone_id','')::uuid,
             public.service_zone_id_for_point(
               nullif(e->>'pickup_latitude','')::numeric,
               nullif(e->>'pickup_longitude','')::numeric
             )
           ),
           e->>'category', e->>'channel', e->>'currency'
         ))
    || jsonb_build_object(
         'passenger_first_name', pu.first_name,
         'passenger_avatar_url', pu.avatar_url,
         'passenger_rating', pr.rating,
         'passenger_rating_count', coalesce(pr.rating_count, 0)
       )
    order by ord), '[]'::jsonb)
  into v_result
  from jsonb_array_elements(v_raw) with ordinality as data(e, ord)
  left join lateral (
    select
      nullif(split_part(btrim(coalesce(u.full_name, '')), ' ', 1), '') as first_name,
      nullif(btrim(coalesce(u.avatar_url, '')), '') as avatar_url
    from public.users u
    where u.id = nullif(data.e->>'passenger_id', '')::uuid
  ) pu on true
  left join lateral (
    select
      round(avg(x.score)::numeric, 2) as rating,
      count(*)::int as rating_count
    from public.ratings x
    where x.to_user_id = nullif(data.e->>'passenger_id', '')::uuid
      and x.rated_role = 'passenger'
  ) pr on true;
  return v_result;
end
$function$;
