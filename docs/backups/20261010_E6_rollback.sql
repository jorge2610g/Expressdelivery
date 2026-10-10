-- ROLLBACK manual de 20261010180000_least_privilege_anon_and_table_grants.sql
-- Re-otorga a anon/authenticated/PUBLIC los privilegios que figuraban en el ACL
-- guardado en public.acl_backup_20261010_e6 (solo añade; no quita nada).
do $rb$
declare
  r record; v_role text; v_priv text; v_privs text; v_map jsonb := jsonb_build_object(
    'a','insert','w','update','d','delete','D','truncate','x','references','t','trigger');
  c text;
begin
  for r in select * from public.acl_backup_20261010_e6 where kind = 'table' and acl is not null loop
    foreach v_role in array array['anon','authenticated'] loop
      v_privs := substring(r.acl from '[{,]"?' || v_role || '=([a-zA-Z*]*)/');
      continue when v_privs is null;
      foreach c in array regexp_split_to_array(replace(v_privs, '*', ''), '') loop
        v_priv := v_map ->> c;
        if v_priv in ('insert','update','delete','truncate','references','trigger') then
          execute format('grant %s on table %s to %I', v_priv, r.object, v_role);
        end if;
      end loop;
    end loop;
  end loop;

  for r in select * from public.acl_backup_20261010_e6 where kind = 'function' loop
    continue when to_regprocedure(r.object) is null;
    if r.acl is null or r.acl ~ '[{,]=X' then
      execute format('grant execute on function %s to public', r.object);
    end if;
    if r.acl ~ '[{,]anon=X' then
      execute format('grant execute on function %s to anon', r.object);
    end if;
    if r.acl ~ '[{,]authenticated=X' then
      execute format('grant execute on function %s to authenticated', r.object);
    end if;
  end loop;
end
$rb$;
