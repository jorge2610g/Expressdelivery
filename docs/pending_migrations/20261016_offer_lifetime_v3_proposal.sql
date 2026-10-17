-- PROPUESTA v3, NO APLICADA. Requiere autorización explícita y validación en Supabase.
-- Sustituye a la v2 (que queda incluida). Objetivo:
--   1) La vigencia de cada OFERTA es app_settings.offer_timeout_seconds (acotada 10..600),
--      sin superar la vigencia de su SOLICITUD.
--   2) La vigencia de la SOLICITUD es ride_requests.expires_at (search_timeout_seconds,
--      180 s por defecto), que ya fija el cliente al crear la solicitud. No se cambia aquí.
--   3) Una solicitud vencida no admite ofertas nuevas ni aceptaciones.
--   4) Una oferta pendiente nunca queda sin vencimiento válido.
--
-- Base: definiciones VIGENTES de producción (pg_get_functiondef). Falla cerrado si cambian.
-- Triggers afectados: trg_driver_offer_deadline (15 s -> tiempo configurado) y
-- trg_enforce_driver_offer_minimum_lifetime (30 s -> solo garantiza no nulo).

create or replace function public.driver_offer_expires_at(p_created timestamptz, p_request uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_timeout integer;
  v_request_expires timestamptz;
begin
  select coalesce(a.offer_timeout_seconds, 20) into v_timeout
  from public.app_settings a where a.id = true;
  v_timeout := least(greatest(coalesce(v_timeout, 20), 10), 600);

  select r.expires_at into v_request_expires
  from public.ride_requests r where r.id = p_request;

  if v_request_expires is null then
    raise exception 'Solicitud sin vencimiento válido';
  end if;

  return least(p_created + make_interval(secs => v_timeout), v_request_expires);
end
$fn$;

create or replace function public.enforce_driver_offer_deadline()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  new.created_at := coalesce(new.created_at, now());
  if new.status = 'pending' then
    if (select r.expires_at from public.ride_requests r where r.id = new.ride_request_id) <= now() then
      raise exception 'La solicitud ya venció';
    end if;
    new.expires_at := public.driver_offer_expires_at(new.created_at, new.ride_request_id);
  end if;
  return new;
end;
$function$;

create or replace function public.enforce_driver_offer_minimum_lifetime()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.status = 'pending' and new.expires_at is null then
    new.expires_at := public.driver_offer_expires_at(new.created_at, new.ride_request_id);
  end if;
  return new;
end;
$function$;

-- select_ride_offer: incluye la guardia v2 (oferta no nula y vigente) y añade la
-- vigencia de la solicitud. Dos sustituciones exactas; falla si el texto no coincide.
do $migration$
declare
  v_sql text;
  v_old_offer text := '(o.expires_at is null or o.expires_at > now())';
  v_new_offer text := 'o.expires_at is not null and o.expires_at > now()';
  v_old_req text := 'and r.status in (''searching'',''offers_received'')';
  v_new_req text := 'and r.status in (''searching'',''offers_received'')' || chr(10) || '    and r.expires_at is not null and r.expires_at > now()';
begin
  select pg_get_functiondef('public.select_ride_offer(uuid)'::regprocedure)
    into v_sql;
  if (length(v_sql) - length(replace(v_sql, v_old_offer, ''))) / length(v_old_offer) <> 1
     or (length(v_sql) - length(replace(v_sql, v_old_req, ''))) / length(v_old_req) <> 1 then
    raise exception 'select_ride_offer has changed: review offer lifetime v3 before applying';
  end if;
  v_sql := replace(v_sql, v_old_offer, v_new_offer);
  v_sql := replace(v_sql, v_old_req, v_new_req);
  execute v_sql;
end
$migration$;
