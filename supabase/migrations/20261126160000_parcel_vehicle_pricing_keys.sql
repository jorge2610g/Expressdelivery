-- Envíos por vehículo: claves de tarifa parcel_moto / parcel_auto / parcel_carga.
-- Cada una tiene su propia tarifa y su propio tipo de precio (solo ofertas / fijo / ambos).
-- Si un vehículo no tiene tarifa propia en la zona, se usa la tarifa general «parcel».
-- Estas claves nunca son visibles como servicio de viaje (ni para pasajero ni para conductor).

insert into public.service_catalog
  (service_key, name, description, icon_key, vehicle_type, enabled, allow_bidding, allow_fixed_price,
   sort_order, passenger_visible, driver_visible, scheduled_enabled)
values
  ('parcel_moto',  'Envío · Moto',  'Tarifa de envíos en moto',  'package', 'none', true, true, true, 49, false, false, false),
  ('parcel_auto',  'Envío · Auto',  'Tarifa de envíos en auto',  'package', 'none', true, true, true, 49, false, false, false),
  ('parcel_carga', 'Envío · Carga', 'Tarifa de envíos en carga', 'package', 'none', true, true, true, 49, false, false, false)
on conflict (service_key) do nothing;

insert into public.zone_service_catalog
  (zone_id, service_key, enabled, passenger_visible, driver_visible, allow_bidding, allow_fixed_price,
   scheduled_enabled, sort_order, price_mode)
select z.zone_id, k.service_key, true, false, false, true, true, false, 49, z.price_mode
from public.zone_service_catalog z
cross join (values ('parcel_moto'), ('parcel_auto'), ('parcel_carga')) k(service_key)
where z.service_key = 'parcel'
on conflict (zone_id, service_key) do nothing;

create or replace function public.zone_service_hide_parcel_vehicle_keys()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  if new.service_key in ('parcel_moto', 'parcel_auto', 'parcel_carga') then
    new.passenger_visible := false;
    new.driver_visible := false;
  end if;
  return new;
end $$;
drop trigger if exists zone_service_hide_parcel_vehicle_keys on public.zone_service_catalog;
create trigger zone_service_hide_parcel_vehicle_keys
  before insert or update on public.zone_service_catalog
  for each row execute function public.zone_service_hide_parcel_vehicle_keys();

create or replace function public.quote_service_fare_for_location(
  p_service_key text, p_distance_km numeric, p_duration_minutes numeric, p_lat numeric, p_lng numeric,
  p_dest_lat numeric default null, p_dest_lng numeric default null, p_price_mode text default 'offer')
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_channel text := 'production';
  v_quote jsonb; v_try jsonb; v_key text; v_keys text[]; v_mode text; v_zone uuid;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  v_keys := case when p_service_key in ('parcel_moto', 'parcel_auto', 'parcel_carga')
                 then array[p_service_key, 'parcel'] else array[p_service_key] end;
  foreach v_key in array v_keys loop
    begin
      v_try := public.dynamic_pricing_quote_internal(v_key, p_distance_km, p_duration_minutes, p_lat, p_lng,
                 v_channel, p_dest_lat, p_dest_lng, p_price_mode);
      v_zone := nullif(v_try->>'zone_id', '')::uuid;
      select zs.price_mode into v_mode from public.zone_service_catalog zs
        where zs.zone_id = v_zone and zs.service_key = v_key;
      -- Servicio en modo «solo fijo»: aunque se pida la tarifa de ofertas, se cotiza con la fija.
      if coalesce(p_price_mode, 'offer') <> 'fixed' and v_mode = 'fixed' then
        v_try := public.dynamic_pricing_quote_internal(v_key, p_distance_km, p_duration_minutes, p_lat, p_lng,
                   v_channel, p_dest_lat, p_dest_lng, 'fixed');
      end if;
    exception when others then
      if v_key = v_keys[array_upper(v_keys, 1)] then raise; end if;
      v_try := null;
    end;
    -- Una clave por vehículo solo vale si tiene regla propia en la zona; si no, se usa «parcel».
    if v_try is not null and (
         v_key = v_keys[array_upper(v_keys, 1)]
         or (v_try->'rule'->>'scope_type' = 'zone_service' and v_try->'rule'->>'service_key' = v_key)) then
      v_quote := v_try;
      exit;
    end if;
  end loop;
  v_quote := public.fare_round_quote(v_quote, v_channel);
  return v_quote || jsonb_build_object('price_mode', coalesce((
    select zs.price_mode from public.zone_service_catalog zs
    where zs.zone_id = nullif(v_quote->>'zone_id', '')::uuid and zs.service_key = v_key), 'offer'));
end $$;

do $$
declare d text; r text;
begin
  d := pg_get_functiondef('public.enforce_ride_recommended_fare_floor()'::regprocedure);
  r := replace(d,
    'case when new.service_mode=''parcel'' and exists(select 1 from public.zone_service_catalog zs where zs.zone_id=new.zone_id and zs.service_key=''parcel'' and zs.enabled) then ''parcel'' else new.category end',
    'coalesce(case when new.service_mode=''parcel'' then (select t.k from (values (1,''parcel_''||coalesce(new.parcel_kind,'''')),(2,''parcel'')) t(o,k) where exists(select 1 from public.fare_rules f where f.scope_type=''zone_service'' and f.zone_id=new.zone_id and f.service_key=t.k and f.active) order by t.o limit 1) end, new.category)');
  if r = d then raise exception 'ancla del piso de tarifa no encontrada'; end if;
  execute r;
end $$;

-- La disponibilidad de parcel_moto/auto/carga sigue el interruptor de «parcel» en la zona.
do $$
declare d text; r text;
begin
  d := pg_get_functiondef('public.quote_service_fare_for_location_base(text,numeric,numeric,numeric,numeric,numeric,numeric,text)'::regprocedure);
  r := replace(d,
    'if not exists(select 1 from public.zone_service_catalog zs where zs.zone_id=v_zone_id and zs.service_key=p_service_key and zs.enabled=true and zs.passenger_visible=true) then',
    'if not exists(select 1 from public.zone_service_catalog zs where zs.zone_id=v_zone_id and zs.service_key=case when p_service_key in (''parcel_moto'',''parcel_auto'',''parcel_carga'') then ''parcel'' else p_service_key end and zs.enabled=true and zs.passenger_visible=true) then');
  if r = d then raise exception 'ancla de disponibilidad no encontrada'; end if;
  execute r;
end $$;
