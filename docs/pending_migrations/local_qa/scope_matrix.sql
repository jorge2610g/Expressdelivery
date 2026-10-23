insert into public.users(id,full_name,active_mode) values
 ('a0000000-0000-4000-8000-00000000000a','Usuario prod sin grupo','passenger'),
 ('a0000000-0000-4000-8000-00000000000b','Usuario prod en grupo','passenger'),
 ('a0000000-0000-4000-8000-00000000000c','Preview grupo G1','passenger'),
 ('a0000000-0000-4000-8000-00000000000d','Preview grupo G2','passenger'),
 ('a0000000-0000-4000-8000-00000000000e','Sin binding en grupo G1','passenger'),
 ('a0000000-0000-4000-8000-00000000000f','Sin binding sin grupo','passenger');
insert into public.audit_test_groups(id,name,slug,active) values
 ('c1000000-0000-4000-8000-000000000001','G1','g1',true),('c1000000-0000-4000-8000-000000000002','G2','g2',true);
insert into public.audit_test_group_members(group_id,user_id,role,enabled) values
 ('c1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-00000000000b','passenger',true),
 ('c1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-00000000000c','passenger',true),
 ('c1000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-00000000000d','passenger',true),
 ('c1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-00000000000e','passenger',true);
insert into public.account_runtime_bindings(user_id,environment,source) values
 ('a0000000-0000-4000-8000-00000000000a','production','synthetic'),
 ('a0000000-0000-4000-8000-00000000000b','production','synthetic'),
 ('a0000000-0000-4000-8000-00000000000c','preview','synthetic'),
 ('a0000000-0000-4000-8000-00000000000d','preview','synthetic');
-- Versión del repositorio (035), copia renombrada para comparar en paralelo
create or replace function public.same_scope_repo_035(p_user_a uuid, p_user_b uuid)
returns boolean language plpgsql stable set search_path = public, app_private as $f$
declare v_group_a uuid; v_group_b uuid; v_member_enabled_a boolean; v_member_enabled_b boolean; v_group_active_a boolean; v_group_active_b boolean;
begin
  if p_user_a is null or p_user_b is null then return false; end if;
  select m.group_id, m.enabled, g.active into v_group_a, v_member_enabled_a, v_group_active_a
  from public.audit_test_group_members m join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_a limit 1;
  select m.group_id, m.enabled, g.active into v_group_b, v_member_enabled_b, v_group_active_b
  from public.audit_test_group_members m join public.audit_test_groups g on g.id = m.group_id
  where m.user_id = p_user_b limit 1;
  if v_group_a is null and v_group_b is null then return true; end if;
  if v_group_a is null or v_group_b is null then return false; end if;
  return v_group_a = v_group_b and coalesce(v_member_enabled_a,false) and coalesce(v_member_enabled_b,false) and coalesce(v_group_active_a,false) and coalesce(v_group_active_b,false);
end $f$;
-- Matriz: producción vs repositorio
with u(id,label) as (values
 ('a0000000-0000-4000-8000-00000000000a'::uuid,'prod_sin_grupo'),
 ('a0000000-0000-4000-8000-00000000000b'::uuid,'prod_en_G1'),
 ('a0000000-0000-4000-8000-00000000000c'::uuid,'preview_G1'),
 ('a0000000-0000-4000-8000-00000000000d'::uuid,'preview_G2'),
 ('a0000000-0000-4000-8000-00000000000e'::uuid,'sin_binding_G1'),
 ('a0000000-0000-4000-8000-00000000000f'::uuid,'sin_binding_sin_grupo'))
select x.label||' vs '||y.label as par, public.same_operational_scope(x.id,y.id) as prod, public.same_scope_repo_035(x.id,y.id) as repo_035, (public.same_operational_scope(x.id,y.id) is distinct from public.same_scope_repo_035(x.id,y.id)) as differs from u x join u y on x.label < y.label order by differs desc, par;
