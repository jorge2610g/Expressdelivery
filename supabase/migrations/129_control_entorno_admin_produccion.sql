-- Migración: control_entorno_admin_produccion
-- Fecha: 2026-10-15
--
-- Reúne en un solo archivo los cambios de control de entorno del panel administrativo
-- que ya están aplicados en Producción (proyecto zgpijrznvaskgcmauwxx). Es idempotente:
-- cada bloque omite lo que ya está protegido y los REVOKE se pueden repetir sin efecto.
--
-- Regla del propietario: solo las cuentas de prueba administran usuarios, conductores y
-- zonas de prueba. Lo demás (pagos, suscripciones, tarifas, configuración compartida,
-- anuncios, despacho de viajes y reportes) queda solo para Producción.
--
-- 1. Acceso de administrador: admin_set_panel_access_v2 exige entorno production.
-- 2. Configuración compartida y tarifas: exigen entorno production (5 funciones).
-- 3. Lecturas con datos de pagos, socios, reportes, auditoría y suscripciones: exigen
--    entorno production (9 funciones). En ocho de ellas la marca E1b existía sin la línea
--    que la aplica; el bloque inserta la línea antes de la marca.
-- 4. Funciones que reciben p_channel (27): exigen que la cuenta tenga permiso para ese canal,
--    con admin_assert_environment(normalize_runtime_channel(p_channel)).
-- 5. Funciones antiguas o sin uso en apps, Edge Functions ni tareas (35): se quita EXECUTE
--    a public, anon y authenticated. service_role conserva acceso.
--
-- Respaldo previo: backup.funciones_panel_20261015 (signature, definition, acl).
-- Rollback: restaurar definition desde ese respaldo y reaplicar el acl guardado.
-- Verificado en Producción el 2026-10-15: la cuenta de producción conserva EXECUTE; ninguna
-- función con p_channel queda sin control, salvo admin_driver_kyc_bolivia_manual_decide
-- (solo devuelve un error y no toca datos).

create schema if not exists backup;

create table if not exists backup.funciones_panel_20261015 (
  signature text primary key,
  definition text not null,
  acl text,
  backed_up_at timestamptz not null default now()
);

-- 1 y 2: acceso de administrador y configuración compartida
do $control_escritura$
declare
  r record;
  v_def text;
  v_new text;
  v_marker constant text := '-- Control 2026-10-15: solo entorno Produccion';
  v_nombres text[] := array[
    'admin_set_panel_access_v2','admin_upsert_country_coverage_v2',
    'admin_upsert_driver_document_requirement','admin_delete_driver_document_requirement',
    'admin_marketplace_delivery_rate_components','admin_set_dynamic_pricing_qa_override'];
begin
  insert into backup.funciones_panel_20261015(signature, definition, acl)
  select p.oid::regprocedure::text, pg_get_functiondef(p.oid), p.proacl::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = any(v_nombres)
  on conflict (signature) do nothing;

  for r in
    select p.oid, p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(v_nombres)
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('admin_assert_environment(''production'')' in v_def) > 0 then
      continue;
    end if;
    if v_def !~* '\mlanguage plpgsql\M' then
      raise exception 'Control 2026-10-15: % no es plpgsql', r.sig;
    end if;
    v_new := regexp_replace(v_def, '(AS \$function\$.*?\m)(begin)\M',
      E'\\1\\2\n  ' || v_marker || E'\n  perform public.admin_assert_environment(''production'');', 'si');
    if v_new = v_def then
      raise exception 'Control 2026-10-15: no se encontró BEGIN en %', r.sig;
    end if;
    execute v_new;
  end loop;
end
$control_escritura$;

-- 3: lecturas con datos de pagos, socios, reportes, auditoría y suscripciones
do $control_lecturas$
declare
  r record;
  v_def text;
  v_new text;
  v_marker constant text := '-- E1b-20261010 production read guard';
  v_nombres text[] := array[
    'admin_audit_list','admin_driver_subscriptions','admin_marketplace_merchant_users',
    'admin_partner_dashboard','admin_partner_member_list','admin_payment_overview_v2',
    'admin_report_summary','admin_topup_requests','admin_subscription_payment_list_v2'];
begin
  insert into backup.funciones_panel_20261015(signature, definition, acl)
  select p.oid::regprocedure::text, pg_get_functiondef(p.oid), p.proacl::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = any(v_nombres)
  on conflict (signature) do nothing;

  for r in
    select p.oid, p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(v_nombres)
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('admin_assert_environment(''production'')' in v_def) > 0 then
      continue;
    end if;
    if v_def !~* '\mlanguage plpgsql\M' then
      raise exception 'Control 2026-10-15: % no es plpgsql', r.sig;
    end if;
    if position(v_marker in v_def) > 0 then
      v_new := replace(v_def, v_marker, 'perform public.admin_assert_environment(''production'');' || E'\n  ' || v_marker);
    else
      v_new := regexp_replace(v_def, '(AS \$function\$.*?\m)(begin)\M',
        E'\\1\\2\n  ' || v_marker || E'\n  perform public.admin_assert_environment(''production'');', 'si');
    end if;
    if v_new = v_def then
      raise exception 'Control 2026-10-15: no se pudo aplicar en %', r.sig;
    end if;
    execute v_new;
  end loop;
end
$control_lecturas$;

-- 4: funciones que reciben p_channel: la cuenta debe tener permiso para ese canal
do $control_canal$
declare
  r record;
  v_def text;
  v_new text;
  v_marker constant text := '-- Control 2026-10-15: el entorno debe estar permitido a esta cuenta';
  v_nombres text[] := array[
    'admin_assign_ride_v2','admin_assign_delivery_v2','admin_send_announcement_v4','admin_support_reply_v2',
    'admin_user_list_v4','admin_trip_list_v3','admin_trip_list_v4','admin_driver_list_v3',
    'admin_delivery_list_v3','admin_delivery_list_v4','admin_dashboard_state_v2','admin_report_summary_v2',
    'admin_marketplace_orders_v2','admin_driver_kyc_bolivia_manual_list','admin_driver_kyc_bolivia_settings',
    'admin_driver_priority_state_v2','admin_driver_priority_state_scoped','admin_driver_subscriptions_scoped',
    'admin_available_drivers_v2','admin_open_service_requests_v2','admin_notification_campaign_list_v2',
    'admin_notification_campaign_list_scoped','admin_push_audience_estimate_v2','admin_dynamic_pricing_qa_state_scoped',
    'admin_support_messages_v2','admin_support_threads_v2','admin_support_threads_scoped'];
begin
  insert into backup.funciones_panel_20261015(signature, definition, acl)
  select p.oid::regprocedure::text, pg_get_functiondef(p.oid), p.proacl::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = any(v_nombres)
  on conflict (signature) do nothing;

  for r in
    select p.oid, p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(v_nombres)
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('admin_assert_environment(' in v_def) > 0 then
      continue;
    end if;
    if v_def !~* '\mlanguage plpgsql\M' then
      raise exception 'Control 2026-10-15: % no es plpgsql', r.sig;
    end if;
    v_new := regexp_replace(v_def, '(AS \$function\$.*?\m)(begin)\M',
      E'\\1\\2\n  ' || v_marker || E'\n  perform public.admin_assert_environment(public.normalize_runtime_channel(p_channel));', 'si');
    if v_new = v_def then
      raise exception 'Control 2026-10-15: no se encontró BEGIN en %', r.sig;
    end if;
    execute v_new;
  end loop;
end
$control_canal$;

-- 5: funciones antiguas o sin uso: sin acceso para public, anon ni authenticated
do $control_revocar$
declare
  r record;
  v_nombres text[] := array[
    'admin_audit_load_state','admin_audit_load_snapshot','admin_available_drivers','admin_delivery_list_v2',
    'admin_dashboard_state','admin_driver_queue','admin_identity_pending_driver_ids','admin_identity_resolve',
    'admin_identity_settings_get','admin_identity_verification_list','admin_identity_verification_list_scoped',
    'admin_log_action','admin_marketplace_product_cross_sells','admin_marketplace_state','admin_marketplace_v2_state',
    'admin_notification_campaign_list','admin_open_service_requests','admin_panel_access_list',
    'admin_partner_driver_list','admin_partner_settlement_list','admin_payment_overview',
    'admin_push_audience_estimate','admin_release_gate_status','admin_stats','admin_support_threads',
    'admin_trip_list_v2','admin_upsert_zone','admin_upsert_zone_v2','admin_user_list','admin_zone_list',
    'admin_zone_list_v2','admin_user_runtime_environment','admin_user_list_v2','admin_user_list_v3',
    'admin_driver_list_v2'];
begin
  insert into backup.funciones_panel_20261015(signature, definition, acl)
  select p.oid::regprocedure::text, pg_get_functiondef(p.oid), p.proacl::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = any(v_nombres)
  on conflict (signature) do nothing;

  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(v_nombres)
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end
$control_revocar$;
