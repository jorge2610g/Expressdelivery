-- Un conductor en línea que deja de enviar ubicación ya NO se desconecta solo: queda
-- «sin ubicación» (el panel ya lo marca) y no recibe solicitudes hasta que vuelva la señal.
-- Reemplaza la migración de 30 minutos (20261123230000), que quedó sin efecto.
create or replace function public.expire_stale_online_drivers()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  return 0;
end
$function$;

-- Despacho: solo se ofrece a conductores con ubicación reciente (3 min).
do $$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ride_dispatch_candidates';
  if v_def is null or position('dp.latitude is not null' in v_def) = 0 then
    raise exception 'ride_dispatch_candidates no tiene la forma esperada';
  end if;
  if position('location_updated_at' in v_def) = 0 then
    v_def := replace(v_def, 'and dp.latitude is not null',
      E'and dp.location_updated_at is not null\n    and dp.location_updated_at > now() - interval ''3 minutes''\n    and dp.latitude is not null');
    execute v_def;
  end if;
end $$;
