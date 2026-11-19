-- Tarifas por horario (tarifa nocturna, de madrugada, etc.).
--
-- Una tarifa por horario es una tarifa completa (base, precio por km, por
-- minuto y mínimo) con un nombre y una franja de horas. Mientras la hora local
-- de la zona esté dentro de la franja, esa tarifa reemplaza a la tarifa normal
-- de la zona y el servicio. Fuera de toda franja, nada cambia.
--
-- No se toca fare_rules (solo admite una regla por zona y servicio).
-- La comisión y el multiplicador de la regla normal se conservan.

-- Zona horaria de cada zona para interpretar las franjas.
alter table public.service_zones
  add column if not exists timezone text not null default 'America/La_Paz';
update public.service_zones
   set timezone = 'America/Santiago'
 where country_code = 'CL' and timezone = 'America/La_Paz';

create table if not exists public.fare_time_rules (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  service_key text not null,
  name text not null,
  start_time time not null,
  end_time time not null,
  days_of_week smallint[] not null default array[1,2,3,4,5,6,7]::smallint[],
  base_fare numeric not null default 0,
  per_km numeric not null default 0,
  per_minute numeric not null default 0,
  minimum_fare numeric not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fare_time_rules_name_check
    check (char_length(btrim(name)) between 1 and 60),
  constraint fare_time_rules_window_check check (start_time <> end_time),
  constraint fare_time_rules_days_check
    check (cardinality(days_of_week) between 1 and 7
           and days_of_week <@ array[1,2,3,4,5,6,7]::smallint[]),
  constraint fare_time_rules_amounts_check
    check (base_fare >= 0 and per_km >= 0 and per_minute >= 0
           and minimum_fare >= 0)
);

create index if not exists fare_time_rules_lookup_idx
  on public.fare_time_rules (zone_id, service_key) where active;

-- Solo las funciones del servidor y del panel leen o escriben esta tabla.
alter table public.fare_time_rules enable row level security;
revoke all on public.fare_time_rules from anon, authenticated;

-- ¿La hora local cae dentro de la franja? Las franjas pueden cruzar la
-- medianoche (22:00 a 05:00): la parte de la madrugada cuenta con el día en
-- que empezó la franja. Los días son ISO: 1 = lunes ... 7 = domingo.
create or replace function public.fare_time_rule_matches(
  p_start time,
  p_end time,
  p_days smallint[],
  p_local timestamp
)
returns boolean
language sql
immutable
as $$
  select case
    when p_start < p_end then
      extract(isodow from p_local)::smallint = any(p_days)
      and p_local::time >= p_start
      and p_local::time < p_end
    else
      (p_local::time >= p_start
        and extract(isodow from p_local)::smallint = any(p_days))
      or (p_local::time < p_end
        and extract(isodow from (p_local - interval '1 day'))::smallint
            = any(p_days))
  end
$$;

-- Tarifa efectiva en un instante dado (permite probar cualquier hora).
create or replace function public.effective_fare_rule_at(
  p_service_key text,
  p_zone_id uuid,
  p_at timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_base jsonb;
  v_time public.fare_time_rules%rowtype;
  v_local timestamp;
  v_service text := nullif(btrim(coalesce(p_service_key, '')), '');
begin
  -- Regla normal: idéntica a la lógica anterior de effective_fare_rule.
  select to_jsonb(x)
    into v_base
  from (
    select
      f.id,
      f.scope_type,
      f.service_key,
      f.zone_id,
      f.base_fare,
      f.per_km,
      f.per_minute,
      f.minimum_fare,
      f.surge_multiplier,
      f.commission_percent
    from public.fare_rules f
    where f.active = true
      and (
        (p_zone_id is not null
          and f.scope_type = 'zone_service'
          and f.zone_id = p_zone_id
          and f.service_key = p_service_key)
        or
        (f.scope_type = 'service' and f.service_key = p_service_key)
        or
        f.scope_type = 'global'
      )
    order by
      case
        when f.scope_type = 'zone_service' then 3
        when f.scope_type = 'service' then 2
        else 1
      end desc
    limit 1
  ) x;

  if p_zone_id is null or v_service is null then
    return v_base;
  end if;

  select p_at at time zone coalesce(z.timezone, 'America/La_Paz')
    into v_local
  from public.service_zones z
  where z.id = p_zone_id;
  if v_local is null then
    return v_base;
  end if;

  select t.*
    into v_time
  from public.fare_time_rules t
  where t.active
    and t.zone_id = p_zone_id
    and t.service_key = v_service
    and public.fare_time_rule_matches(
      t.start_time, t.end_time, t.days_of_week, v_local)
  order by t.created_at desc, t.id
  limit 1;

  if not found then
    return v_base;
  end if;

  return coalesce(
           v_base,
           jsonb_build_object(
             'scope_type', 'zone_service',
             'service_key', v_service,
             'zone_id', p_zone_id,
             'surge_multiplier', 1,
             'commission_percent', 0
           )
         )
         || jsonb_build_object(
           'base_fare', v_time.base_fare,
           'per_km', v_time.per_km,
           'per_minute', v_time.per_minute,
           'minimum_fare', v_time.minimum_fare,
           'time_rule_id', v_time.id,
           'time_rule_name', v_time.name
         );
end;
$$;

revoke execute on function public.effective_fare_rule_at(text, uuid, timestamptz)
  from public, anon;
grant execute on function public.effective_fare_rule_at(text, uuid, timestamptz)
  to authenticated;

-- Misma firma de siempre: el cálculo de tarifas, el contexto de zona y los
-- pagos con billetera siguen llamándola sin cambios.
create or replace function public.effective_fare_rule(
  p_service_key text,
  p_zone_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select public.effective_fare_rule_at(p_service_key, p_zone_id, now());
$$;
