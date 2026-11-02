-- Conductor ocupado: quien tiene un viaje activo no puede recibir ni aceptar otro.
-- Cambios:
--   1) Trigger en driver_offers: no permite ofertas pendientes nuevas (ni reactivarlas)
--      de un conductor con viaje activo.
--   2) select_ride_offer: antes de crear el viaje, bloquea al conductor y rechaza si ya
--      tiene viaje activo. El bloqueo evita dos selecciones simultáneas.
-- No cambia montos, tarifas, estados de viajes existentes, cobros ni billetera.
-- Viaje activo = trips.status distinto de 'completed' y 'cancelled'.
-- Base: definición VIGENTE de select_ride_offer. Falla cerrado si el texto cambia.

create or replace function public.driver_has_active_trip(p_driver_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.trips t
    where t.driver_id = p_driver_id
      and t.status not in ('completed', 'cancelled')
  );
$$;

create or replace function public.guard_driver_offer_no_active_trip()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.status = 'pending'
     and (tg_op = 'INSERT' or old.status is distinct from new.status)
     and public.driver_has_active_trip(new.driver_id) then
    raise exception 'Tienes un viaje activo. Termínalo antes de ofertar.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_driver_offer_no_active_trip on public.driver_offers;
create trigger trg_guard_driver_offer_no_active_trip
  before insert or update of status on public.driver_offers
  for each row execute function public.guard_driver_offer_no_active_trip();

do $migration$
declare
  v_sql text;
  v_anchor text :=
    '  if v_driver_id = v_passenger_id then' || chr(10) ||
    '    raise exception ''No puedes asignarte tu propia solicitud'';' || chr(10) ||
    '  end if;' || chr(10);
  v_new text := v_anchor ||
    chr(10) ||
    '  -- Conductor ocupado: un solo viaje activo por conductor. El bloqueo evita' || chr(10) ||
    '  -- que dos selecciones simultáneas creen dos viajes.' || chr(10) ||
    '  perform pg_advisory_xact_lock(hashtext(''driver_trip:'' || v_driver_id::text));' || chr(10) ||
    '  if public.driver_has_active_trip(v_driver_id) then' || chr(10) ||
    '    raise exception ''El conductor ya tiene un viaje activo.'';' || chr(10) ||
    '  end if;' || chr(10);
begin
  select pg_get_functiondef('public.select_ride_offer(uuid)'::regprocedure)
    into v_sql;
  -- Ya aplicada: no repetir.
  if strpos(v_sql, 'driver_has_active_trip(v_driver_id)') > 0 then
    return;
  end if;
  if (length(v_sql) - length(replace(v_sql, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'select_ride_offer has changed: review busy driver guard before applying';
  end if;
  execute replace(v_sql, v_anchor, v_new);
end
$migration$;
