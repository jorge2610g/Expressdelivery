-- PROPUESTA, NO APLICADA. Requiere autorización explícita del propietario y validación en Supabase.
--
-- Objetivo (comentario P0 de PR #262, 18-oct-2026): «+» y «−» en «Seguimos buscando / Subir mi oferta»
--   * un escalón por toque: CLP +250 (Chile) y BOB +1 (Bolivia), según zona, moneda, servicio y canal
--     reales de la solicitud;
--   * «−» nunca baja de la última oferta confirmada;
--   * el servidor valida el precio al renovar, no solo el cliente.
--
-- Qué hace este archivo:
--   1) passenger_search_fare_rule(p_ride_request_id): lectura segura para el pasajero dueño de la solicitud.
--      Devuelve solo moneda, paso, oferta confirmada y redondeo. No expone tablas de reglas.
--   2) renew_ride_request: reemplaza la versión de 20261018_renew_search_visibility_PROPOSAL.sql.
--      Conserva search_started_at y añade validación de piso, paso y redondeo. No recibe moneda.
--
-- Dependencias:
--   * Aplicar junto con la parte de visibilidad del conductor de 20261018_renew_search_visibility_PROPOSAL.sql
--     (columna search_started_at y función available_ride_requests_for_driver). Esta propuesta ya incluye la
--     columna y el sello de renovación; la función del conductor sigue en el archivo anterior.
--   * Usa driver_quick_offer_steps (SECURITY DEFINER, no concedida a authenticated) desde dentro de una función
--     SECURITY DEFINER. El cliente nunca la llama directamente.
--   * El paso se toma del escalón más pequeño de la regla efectiva: 250 CLP o 1 BOB en el respaldo actual.
--     No se usa fare_rounding_increment como cantidad a sumar.
--
-- Rollback: restaurar las definiciones actuales de renew_ride_request (pg_get_functiondef) y
--   drop function public.passenger_search_fare_rule(uuid).

alter table public.ride_requests
  add column if not exists search_started_at timestamptz;

-- 1) Lectura segura para el pasajero.
create or replace function public.passenger_search_fare_rule(p_ride_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  v_uid uuid := auth.uid();
  v_row public.ride_requests%rowtype;
  v_steps jsonb;
  v_step numeric;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select *
    into v_row
  from public.ride_requests
  where id = p_ride_request_id
    and passenger_id = v_uid
    and status in ('searching','offers_received');

  if v_row.id is null then
    raise exception 'Solicitud no disponible';
  end if;

  v_steps := public.driver_quick_offer_steps(
    v_row.zone_id,
    v_row.category,
    v_row.channel,
    v_row.currency
  );

  select min(s.value::numeric)
    into v_step
  from jsonb_array_elements_text(v_steps) as s(value)
  where s.value::numeric > 0;

  return jsonb_build_object(
    'currency', v_row.currency,
    'step', v_step,
    'confirmed_fare', v_row.proposed_fare,
    'rounding_increment', public.fare_rounding_increment(v_row.currency, v_row.channel)
  );
end;
$fn$;

revoke all on function public.passenger_search_fare_rule(uuid) from public;
grant execute on function public.passenger_search_fare_rule(uuid) to authenticated;

-- 2) Renovación con validación de servidor.
create or replace function public.renew_ride_request(
  p_ride_request_id uuid,
  p_proposed_fare numeric default null::numeric
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_uid uuid := auth.uid();
  v_row public.ride_requests%rowtype;
  v_steps jsonb;
  v_step numeric;
  v_increment numeric;
  v_diff numeric;
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

  if p_proposed_fare is not null then
    v_increment := public.fare_rounding_increment(v_row.currency, v_row.channel);

    if public.fare_round_value(p_proposed_fare, v_increment) <> p_proposed_fare then
      raise exception 'El monto tiene más precisión que la permitida para esta moneda';
    end if;

    if p_proposed_fare < coalesce(v_row.proposed_fare, 0) then
      raise exception 'La oferta no puede bajar de % %', v_row.proposed_fare, v_row.currency;
    end if;

    v_diff := p_proposed_fare - coalesce(v_row.proposed_fare, 0);
    if v_diff > 0 then
      v_steps := public.driver_quick_offer_steps(
        v_row.zone_id, v_row.category, v_row.channel, v_row.currency
      );
      select min(s.value::numeric)
        into v_step
      from jsonb_array_elements_text(v_steps) as s(value)
      where s.value::numeric > 0;

      if v_step is not null and mod(v_diff, v_step) <> 0 then
        raise exception 'El aumento debe ser de % en %', v_step, v_row.currency;
      end if;
    end if;
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
$fn$;
