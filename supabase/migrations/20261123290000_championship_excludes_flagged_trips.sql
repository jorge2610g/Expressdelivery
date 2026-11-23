-- Los viajes marcados por irregularidades (abiertos o confirmados) no suman al campeonato.
do $$
declare
  v_def text; v_new text; v_fn text;
  v_excl constant text := ' and not exists (select 1 from public.trip_integrity_flags f where f.trip_id = t.id and f.review_status in (''open'',''confirmed''))';
begin
  foreach v_fn in array array['driver_championships_for_driver','admin_driver_championship_ranking','admin_driver_championship_driver_trips'] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;
    if v_def is null then raise exception 'no existe %', v_fn; end if;
    if position('trip_integrity_flags' in v_def) > 0 then continue; end if;
    v_new := replace(v_def, 'and t.status=''completed'' and t.channel=v_champ.channel',
                            'and t.status=''completed'' and t.channel=v_champ.channel' || v_excl);
    v_new := replace(v_new, 'and t.status = ''completed'' and t.channel = v_champ.channel',
                            'and t.status = ''completed'' and t.channel = v_champ.channel' || v_excl);
    if v_new = v_def then raise exception 'sin cambios en %', v_fn; end if;
    execute v_new;
  end loop;
end $$;
