-- E1 · 2026-10-10 · Las RPC administrativas de escritura SIN p_channel
-- solo validaban is_admin(); una cuenta super_admin con
-- allow_production=false (Admin Preview-only) podía escribir datos reales
-- llamando /rest/v1/rpc directamente. Ver docs/AUDIT_2026-10-10_ESTADO_Y_PLAN.md.
--
-- Cambios (aditivos, reversibles con 20261010120100_..._rollback.sql):
--  1. admin_users.allow_production DEFAULT false (nuevos admins no heredan Producción).
--  2. Respaldo de las definiciones originales en admin_function_backup_20261010.
--  3. RPC llamadas directamente por clientes: se inyecta al inicio
--     `perform public.admin_assert_environment('production');`.
--  4. Funciones internas que solo invocan wrappers *_v2 con canal validado:
--     se revoca EXECUTE a PUBLIC/anon/authenticated (los wrappers son
--     SECURITY DEFINER de postgres y siguen funcionando).
--  5. admin_environment_config_upsert exige permiso sobre p_environment.
-- No cambia firmas ni datos. Funciones ausentes en un proyecto se omiten.

alter table public.admin_users alter column allow_production set default false;

create table if not exists public.admin_function_backup_20261010 (
  signature text primary key,
  definition text not null,
  acl text,
  backed_up_at timestamptz not null default now()
);
alter table public.admin_function_backup_20261010 enable row level security;
revoke all on public.admin_function_backup_20261010 from public, anon, authenticated;

do $mig$
declare
  v_guard_names text[] := array[
    'admin_advanced_settings_update','admin_approve_preview_build',
    'admin_approve_single_app_candidate','admin_assign_partner_member_by_email',
    'admin_certify_single_app_candidate','admin_create_build_job',
    'admin_create_partner_settlement','admin_delete_driver_document_requirement',
    'admin_delete_zone_payment_method','admin_driver_floating_offer_update',
    'admin_identity_resolve','admin_identity_settings_update',
    'admin_mark_partner_settlement_paid','admin_marketplace_assign_merchant_user',
    'admin_marketplace_set_cross_sells','admin_marketplace_set_merchant_user_active',
    'admin_marketplace_set_plus_merchant_benefit','admin_marketplace_update_merchant_logistics',
    'admin_marketplace_update_merchant_v2','admin_marketplace_update_product_v2',
    'admin_marketplace_update_settings','admin_marketplace_update_zone_phase2',
    'admin_marketplace_upsert_banner','admin_marketplace_upsert_category',
    'admin_marketplace_upsert_coupon','admin_marketplace_upsert_home_section',
    'admin_marketplace_upsert_menu_section','admin_marketplace_upsert_merchant',
    'admin_marketplace_upsert_modifier','admin_marketplace_upsert_modifier_group',
    'admin_marketplace_upsert_plus_plan','admin_marketplace_upsert_product',
    'admin_phone_verification_settings_update','admin_promote_single_app_candidate',
    'admin_publish_build','admin_queue_single_app_candidate',
    'admin_remove_audit_group_member','admin_resolve_wallet_topup',
    'admin_send_announcement','admin_send_announcement_v2','admin_send_announcement_v3',
    'admin_set_audit_group_active','admin_set_audit_group_member',
    'admin_set_driver_partner','admin_set_driver_subscription',
    'admin_set_driver_subscription_provider_settings','admin_set_driver_subscription_settings',
    'admin_set_driver_subscription_zone_settings','admin_set_mapbox_quota_control',
    'admin_set_panel_access','admin_set_partner_member_active','admin_set_passenger_ads',
    'admin_set_zone_payment_provider','admin_set_zone_service','admin_settings_update',
    'admin_support_messages','admin_support_reply','admin_update_driver_priority_settings',
    'admin_update_zone_landing','admin_upsert_audit_group','admin_upsert_country_coverage',
    'admin_upsert_country_coverage_v2','admin_upsert_driver_document_requirement',
    'admin_upsert_driver_subscription_plan','admin_upsert_fare_rule','admin_upsert_partner',
    'admin_upsert_security_zone','admin_upsert_service','admin_upsert_special_fare_zone',
    'admin_upsert_zone','admin_upsert_zone_payment_method','admin_upsert_zone_polygon',
    'admin_upsert_zone_v2'
  ];
  v_internal_names text[] := array[
    'admin_assign_delivery','admin_assign_ride','admin_resolve_emergency',
    'admin_set_account_status','admin_set_driver_approval','admin_update_driver_profile',
    'admin_update_user_profile','admin_upsert_driver_document','admin_upsert_zone_v3',
    'admin_promote_production_candidate'
  ];
  v_marker constant text := '-- E1-20261010 production guard';
  r record;
  v_def text;
  v_new text;
  v_count int := 0;
begin
  -- Backups (all touched functions, every overload).
  insert into public.admin_function_backup_20261010(signature, definition, acl)
  select p.oid::regprocedure::text, pg_get_functiondef(p.oid), p.proacl::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = any(v_guard_names || v_internal_names || array['admin_environment_config_upsert'])
  on conflict (signature) do nothing;

  -- 3. Production guard injection.
  for r in
    select p.oid, p.oid::regprocedure::text sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
    where n.nspname = 'public' and p.proname = any(v_guard_names)
  loop
    v_def := pg_get_functiondef(r.oid);
    if position(v_marker in v_def) > 0 then
      continue;
    end if;
    if v_def !~* '\mlanguage plpgsql\M' then
      raise exception 'E1: % no es plpgsql', r.sig;
    end if;
    v_new := regexp_replace(
      v_def,
      '(AS \$function\$.*?\m)(begin)\M',
      E'\\1\\2\n  ' || v_marker || E'\n  perform public.admin_assert_environment(''production'');',
      'si'
    );
    if v_new = v_def then
      raise exception 'E1: no se encontró BEGIN en %', r.sig;
    end if;
    execute v_new;
    v_count := v_count + 1;
  end loop;
  raise notice 'E1: guard inyectado en % funciones', v_count;

  -- 4. Internal functions: callable only through validated wrappers.
  for r in
    select p.oid::regprocedure::text sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(v_internal_names)
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end
$mig$;

-- 5. Shadow/config store: caller must be allowed on the target environment.
do $cfg$
declare
  v_def text; v_new text; r record;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='admin_environment_config_upsert'
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('-- E1-20261010 environment guard' in v_def) > 0 then continue; end if;
    v_new := regexp_replace(
      v_def,
      '(AS \$function\$.*?\m)(begin)\M',
      E'\\1\\2\n  -- E1-20261010 environment guard\n  if not public.admin_environment_allowed(lower(trim(coalesce(p_environment, \'\')))) then\n    raise exception \'No autorizado para el entorno %\', p_environment;\n  end if;',
      'si'
    );
    if v_new = v_def then raise exception 'E1: BEGIN no encontrado en admin_environment_config_upsert'; end if;
    execute v_new;
  end loop;
end
$cfg$;
