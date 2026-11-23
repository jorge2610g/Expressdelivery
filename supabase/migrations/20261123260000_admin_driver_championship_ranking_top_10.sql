-- El panel solo muestra los 10 primeros del ranking.
do $$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_driver_championship_ranking';
  if v_def is null or position('o.pos <= 100' in v_def) = 0 then
    raise exception 'admin_driver_championship_ranking no tiene la forma esperada';
  end if;
  execute replace(v_def, 'o.pos <= 100', 'o.pos <= 10');
end $$;
