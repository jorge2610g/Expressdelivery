-- Al bloquear la conexión de un conductor con deuda, el mensaje indica cuánto debe y el tope,
-- con el formato que la app ya sabe mostrar («deuda de billetera es CLP 500 … tope … CLP 0»).
create or replace function public.guard_driver_online_adjustment_debt()
returns trigger language plpgsql security definer set search_path to '' as $fn$
declare
  v_total numeric;
  v_limit numeric;
  v_currency text;
begin
  if new.online_status='online' and old.online_status is distinct from new.online_status then
    select s.debt_total,s.debt_limit,s.currency_code
      into v_total,v_limit,v_currency
      from public.wallet_debt_limit_status_v1(
        new.id,new.zone_id,public.admin_user_runtime_environment(new.id),'driver'
      ) s;
    if v_total>v_limit then
      raise exception 'Tu deuda de billetera es % % y supera el tope permitido de % %. Paga desde Pagos y billetera para conectarte.',
        coalesce(v_currency,''), v_total, coalesce(v_currency,''), v_limit;
    end if;
  end if;
  return new;
end;
$fn$;
