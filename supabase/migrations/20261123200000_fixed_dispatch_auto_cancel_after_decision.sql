-- Precio fijo: si al terminar el minuto el pasajero no decide en 30 s (seguir o
-- cancelar), el viaje se cancela solo, igual que en el flujo de ofertas.
do $mig$
declare d text; i integer;
begin
  d := pg_get_functiondef('public.fixed_dispatch_advance_v1(uuid)'::regprocedure);
  if position('Tiempo de búsqueda vencido' in d) = 0 then
    if position($k$    update public.ride_requests set dispatch_exhausted_at = coalesce(dispatch_exhausted_at, now()) where id = v_ride.id;
    return jsonb_build_object('state','exhausted');$k$ in d) = 0 then
      raise exception 'advance cambió de forma';
    end if;
    d := replace(d, $k$    update public.ride_requests set dispatch_exhausted_at = coalesce(dispatch_exhausted_at, now()) where id = v_ride.id;
    return jsonb_build_object('state','exhausted');$k$,
$k$    update public.ride_requests set dispatch_exhausted_at = coalesce(dispatch_exhausted_at, now()) where id = v_ride.id;
    if v_ride.dispatch_exhausted_at is not null and v_ride.dispatch_exhausted_at <= now() - interval '30 seconds' then
      update public.ride_requests set status = 'cancelled', cancellation_reason = 'Tiempo de búsqueda vencido', updated_at = now()
       where id = v_ride.id;
      return jsonb_build_object('state','closed');
    end if;
    return jsonb_build_object('state','exhausted');$k$);
    execute d;
  end if;
  d := pg_get_functiondef('public.fixed_dispatch_tick_all_v1()'::regprocedure);
  if position('Tiempo de búsqueda vencido' in d) = 0 then
    i := position(E'\nbegin\n' in d);
    if i = 0 then raise exception 'tick cambió de forma'; end if;
    d := substr(d, 1, i + 6)
      || E'  update public.ride_requests set status = ''cancelled'', cancellation_reason = ''Tiempo de búsqueda vencido'', updated_at = now()\n'
      || E'   where dispatch_style = ''sequential'' and status in (''searching'',''offers_received'')\n'
      || E'     and dispatch_exhausted_at is not null and dispatch_exhausted_at <= now() - interval ''30 seconds'';\n'
      || substr(d, i + 7);
    execute d;
  end if;
  d := pg_get_functiondef('public.passenger_fixed_dispatch_state_v1(uuid)'::regprocedure);
  if position('decision_seconds_left' in d) = 0 then
    if position($k$'exhausted', v_ride.dispatch_exhausted_at is not null, 'round', v_ride.dispatch_round,$k$ in d) = 0 then
      raise exception 'state cambió de forma';
    end if;
    d := replace(d, $k$'exhausted', v_ride.dispatch_exhausted_at is not null, 'round', v_ride.dispatch_round,$k$,
$k$'exhausted', v_ride.dispatch_exhausted_at is not null, 'round', v_ride.dispatch_round,
    'decision_seconds_left', case when v_ride.dispatch_exhausted_at is null then null
       else greatest(0, 30 - floor(extract(epoch from (now() - v_ride.dispatch_exhausted_at)))) end,$k$);
    execute d;
  end if;
end
$mig$;
