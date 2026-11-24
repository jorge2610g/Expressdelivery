-- Montos legibles en las instrucciones del repartidor: «$ 15.000» en lugar de «$ 15000.00».
create or replace function public.courier_money_text(p_amount numeric)
returns text language sql immutable set search_path to 'public' as $$
  select case
    when p_amount = trunc(p_amount) then replace(to_char(p_amount, 'FM999,999,999,990'), ',', '.')
    else replace(replace(replace(to_char(p_amount, 'FM999,999,999,990.00'), ',', '~'), '.', ','), '~', '.')
  end;
$$;

do $m$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'marketplace_merchant_request_courier';
  v_new := regexp_replace(v_def, 'trim\(to_char\(([^,]+), ''FM999999990\.00''\)\)', 'public.courier_money_text(\1)', 'g');
  if v_new = v_def then raise exception 'No se pudo parchear marketplace_merchant_request_courier'; end if;
  execute v_new;
end $m$;
