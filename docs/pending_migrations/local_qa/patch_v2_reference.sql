-- Corrección de vencimiento de ofertas de taxi (propuesta, no aplicada).
-- Parte de la definición VIGENTE de producción (pg_get_functiondef), no de una copia
-- estática del repositorio, y cambia UNA sola condición. Falla cerrado si la
-- definición cambió o si el texto no aparece exactamente una vez.
-- Efecto: una oferta solo es aceptable con expires_at no nulo y vigente.
do $migration$
declare
  v_sql text;
  v_old text := '(o.expires_at is null or o.expires_at > now())';
  v_new text := 'o.expires_at is not null and o.expires_at > now()';
begin
  select pg_get_functiondef('public.select_ride_offer(uuid)'::regprocedure)
    into v_sql;
  if (length(v_sql) - length(replace(v_sql, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'select_ride_offer has changed: review expiry guard before applying';
  end if;
  execute replace(v_sql, v_old, v_new);
end
$migration$;
