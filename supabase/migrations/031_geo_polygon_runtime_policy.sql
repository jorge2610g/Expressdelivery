-- Política geográfica para cobertura por polígonos y alertas de seguridad.

create or replace function public.point_in_json_polygon(
  p_lat numeric,
  p_lng numeric,
  p_polygon jsonb
)
returns boolean
language plpgsql
immutable
set search_path=public
as $$
declare
  v_inside boolean := false;
  v_count integer;
  i integer;
  j integer;
  xi double precision;
  yi double precision;
  xj double precision;
  yj double precision;
  x double precision := p_lng::double precision;
  y double precision := p_lat::double precision;
begin
  if p_lat is null or p_lng is null or jsonb_typeof(p_polygon) <> 'array' then
    return false;
  end if;
  v_count := jsonb_array_length(p_polygon);
  if v_count < 3 then return false; end if;
  j := v_count - 1;
  for i in 0..v_count - 1 loop
    yi := nullif(p_polygon->i->>'lat','')::double precision;
    xi := nullif(p_polygon->i->>'lng','')::double precision;
    yj := nullif(p_polygon->j->>'lat','')::double precision;
    xj := nullif(p_polygon->j->>'lng','')::double precision;
    if yi is not null and xi is not null and yj is not null and xj is not null then
      if ((yi > y) <> (yj > y))
         and (x < ((xj - xi) * (y - yi) / nullif(yj - yi,0)) + xi) then
        v_inside := not v_inside;
      end if;
    end if;
    j := i;
  end loop;
  return v_inside;
exception when others then
  return false;
end;
$$;

create or replace function public.app_geo_policy(
  p_lat numeric,
  p_lng numeric,
  p_for text default 'passenger'
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_has_coverage boolean;
  v_inside boolean;
  v_security jsonb;
begin
  v_has_coverage := exists(
    select 1
    from public.service_zone_polygons p
    join public.service_zones z on z.id=p.zone_id
    where p.active=true and z.active=true
  );

  v_inside := not v_has_coverage or exists(
    select 1
    from public.service_zone_polygons p
    join public.service_zones z on z.id=p.zone_id
    where p.active=true and z.active=true
      and public.point_in_json_polygon(p_lat,p_lng,p.polygon)
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',s.id,
        'name',s.name,
        'zone_type',s.zone_type,
        'severity',s.severity,
        'message',s.message,
        'applies_to',s.applies_to
      )
      order by s.severity desc
    ),
    '[]'::jsonb
  )
  into v_security
  from public.security_zones s
  where s.active=true
    and (s.applies_to='both' or s.applies_to=coalesce(p_for,'passenger'))
    and public.point_in_json_polygon(p_lat,p_lng,s.polygon);

  return jsonb_build_object(
    'coverage_enforced',v_has_coverage,
    'inside_coverage',v_inside,
    'security_zones',v_security
  );
end;
$$;
