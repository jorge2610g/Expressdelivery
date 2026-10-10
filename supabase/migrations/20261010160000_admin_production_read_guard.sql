-- E1b · 2026-10-10 · RPC administrativas de LECTURA sin p_channel.
-- Tras E1 (escrituras), una cuenta Admin Preview-only aún podía leer datos
-- personales de Producción (usuarios, viajes, pagos, identidad, soporte…)
-- llamando /rest/v1/rpc. Misma técnica que 20261010120000:
--  * guard `admin_assert_environment('production')` en lecturas llamadas por clientes;
--  * REVOKE EXECUTE a clientes en funciones internas / SQL sin uso directo;
--  * se mantienen abiertas las de sesión y alcance (sin datos personales):
--    admin_access_context, admin_has_panel_access, admin_can_access_zone,
--    admin_effective_zone_id, admin_country_list_scoped, admin_zone_list_scoped,
--    admin_zone_list_for_country.
-- Respaldo en admin_function_backup_20261010 (prefijo 'E1b:'); rollback:
-- docs/backups/20261010_E1b_rollback.sql

create table if not exists public.admin_function_backup_20261010 (
  signature text primary key, definition text not null, acl text,
  backed_up_at timestamptz not null default now()
);
alter table public.admin_function_backup_20261010 enable row level security;
revoke all on public.admin_function_backup_20261010 from public, anon, authenticated;

do $mig$
declare
  v_guard_names text[] := array[
    'admin_audit_list','admin_audit_load_snapshot','admin_audit_load_snapshot_v2',
    'admin_audit_sandbox_state','admin_available_drivers','admin_dashboard_state',
    'admin_delivery_list_v2','admin_driver_list_v2','admin_driver_queue',
    'admin_driver_subscriptions','admin_identity_verification_list',
    'admin_identity_verification_list_scoped','admin_marketplace_merchant_users',
    'admin_open_service_requests','admin_panel_access_list','admin_partner_dashboard',
    'admin_partner_driver_list','admin_partner_member_list','admin_payment_overview',
    'admin_payment_overview_v2','admin_push_audience_estimate','admin_report_summary',
    'admin_stats','admin_support_threads','admin_topup_requests','admin_trip_list_v2',
    'admin_user_list','admin_user_list_v2','admin_user_list_v3'
  ];
  v_internal_names text[] := array[
    'admin_driver_detail','admin_trip_detail','admin_user_detail',
    'admin_driver_priority_state','admin_partner_payment_list',
    'admin_delivery_list','admin_trip_list'
  ];
  v_marker constant text := '-- E1b-20261010 production read guard';
  r record; v_def text; v_new text; v_count int := 0;
begin
  insert into public.admin_function_backup_20261010(signature, definition, acl)
  select 'E1b:' || p.oid::regprocedure::text, pg_get_functiondef(p.oid), p.proacl::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = any(v_guard_names || v_internal_names)
  on conflict (signature) do nothing;

  for r in
    select p.oid, p.oid::regprocedure::text sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(v_guard_names)
  loop
    v_def := pg_get_functiondef(r.oid);
    if position(v_marker in v_def) > 0 then continue; end if;
    if v_def !~* '\mlanguage plpgsql\M' then
      raise exception 'E1b: % no es plpgsql', r.sig;
    end if;
    v_new := regexp_replace(v_def, '(AS \$function\$.*?\m)(begin)\M',
      E'\\1\\2\n  ' || v_marker || E'\n  perform public.admin_assert_environment(''production'');', 'si');
    if v_new = v_def then raise exception 'E1b: no se encontró BEGIN en %', r.sig; end if;
    execute v_new;
    v_count := v_count + 1;
  end loop;
  raise notice 'E1b: guard inyectado en % funciones', v_count;

  for r in
    select p.oid::regprocedure::text sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(v_internal_names)
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end
$mig$;
