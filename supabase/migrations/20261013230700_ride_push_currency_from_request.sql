-- Repair ride-offer push currency without changing fares or trip transitions.
-- Reviewed against live Express Production function definitions on 2026-10-13.
-- Fail closed if either active function has changed since the review.
--
-- CLP (Chile): $ ; BOB (Bolivia): Bs ; other valid ISO codes: ISO + space.
-- The saved ride_requests.currency determines the notification unit.

create or replace function public.express_push_currency_label(p_currency text)
returns text
language sql immutable
set search_path = public
as $function$
  select case upper(btrim(coalesce(p_currency, '')))
    when 'CLP' then '$ '
    when 'BOB' then 'Bs '
    when '' then 'moneda no especificada '
    else upper(btrim(p_currency)) || ' '
  end;
$function$;

-- Used internally by SECURITY DEFINER notification functions.
revoke all on function public.express_push_currency_label(text)
  from public, anon, authenticated;

do $migration$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  -- Driver notification after offer acceptance.
  -- Keep the function's complete current body, grants, PIN, transactions and protections.
  select pg_get_functiondef('public.select_ride_offer(uuid)'::regprocedure)
    into v_sql;
  v_old := 'else ''Tu oferta de Bs '' || v_amount ||';
  v_new := 'else ''Tu oferta de '' || public.express_push_currency_label(v_currency) || v_amount ||';
  if strpos(v_sql, v_old) > 0 then
    execute replace(v_sql, v_old, v_new);
  elsif strpos(v_sql, v_new) = 0 then
    raise exception 'select_ride_offer has changed: review currency patch before applying';
  end if;

  -- Passenger notification when a driver sends an offer.
  -- Read currency from the exact ride_request associated with this offer.
  select pg_get_functiondef('public.notify_ride_offer()'::regprocedure)
    into v_sql;
  if strpos(v_sql, 'public.express_push_currency_label(v_currency)') = 0 then
    if strpos(v_sql, 'v_driver_zone uuid;') = 0
       or strpos(v_sql, 'select r.passenger_id,r.zone_id') = 0
       or strpos(v_sql, 'into v_passenger,v_ride_zone') = 0
       or strpos(v_sql, '|| '' te ofrece Bs '' || v_amount') = 0 then
      raise exception 'notify_ride_offer has changed: review currency patch before applying';
    end if;

    v_sql := replace(v_sql,
      'v_driver_zone uuid;',
      'v_driver_zone uuid;' || chr(10) || '  v_currency text;');
    v_sql := replace(v_sql,
      'select r.passenger_id,r.zone_id',
      'select r.passenger_id,r.zone_id,r.currency');
    v_sql := replace(v_sql,
      'into v_passenger,v_ride_zone',
      'into v_passenger,v_ride_zone,v_currency');
    v_sql := replace(v_sql,
      '|| '' te ofrece Bs '' || v_amount',
      '|| '' te ofrece '' || public.express_push_currency_label(v_currency) || v_amount');
    execute v_sql;
  end if;

  if public.express_push_currency_label('CLP') <> '$ '
     or public.express_push_currency_label('BOB') <> 'Bs '
     or public.express_push_currency_label('USD') <> 'USD ' then
    raise exception 'Currency label smoke test failed';
  end if;
end;
$migration$;

-- Post-apply verification (read-only):
-- select public.express_push_currency_label('CLP'),
--        public.express_push_currency_label('BOB');
-- select proname, strpos(pg_get_functiondef(oid),'te ofrece Bs ') = 0 as fixed
-- from pg_proc where proname='notify_ride_offer';
--
-- No conversion or rounding is applied to monetary values;
-- existing numeric formatting is intentionally preserved.
