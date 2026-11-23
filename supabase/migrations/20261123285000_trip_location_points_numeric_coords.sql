-- geo_distance_km trabaja con numeric: las coordenadas del recorrido también.
-- (Ya incluido en la creación de la tabla de 20261123280000; se deja por trazabilidad.)
alter table public.trip_location_points
  alter column latitude type numeric(10,7) using latitude::numeric,
  alter column longitude type numeric(10,7) using longitude::numeric;
