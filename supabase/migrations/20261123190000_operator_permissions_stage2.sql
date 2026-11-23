-- Permisos finos de operadores, etapa 2: el resto de los módulos.
-- Catálogo completo para que el administrador pueda marcar cada acción. Las acciones
-- de escritura que los operadores ya tienen en el servidor ahora piden su permiso.
insert into public.admin_permission_catalog(key, module_key, group_label, label, sort_order, sensitive) values
  ('dashboard.edit_social_links','dashboard','Dashboard','Editar enlaces de redes sociales de la app',11,false),
  ('safety_sos.resolve','safety_sos','Seguridad / SOS','Resolver emergencias SOS',61,false),
  ('manual_dispatch.view','manual_dispatch','Despacho manual','Ver despacho manual',70,false),
  ('manual_dispatch.create','manual_dispatch','Despacho manual','Crear y asignar viajes manuales',71,false),
  ('delivery.view','delivery','Delivery','Ver entregas',80,false),
  ('delivery_orders.view','delivery_orders','Pedidos Delivery','Ver pedidos de delivery',82,false),
  ('delivery_phase2.view','delivery_phase2','Delivery Fase 2 / Express Plus','Ver Delivery Fase 2',84,false),
  ('marketplace.view','marketplace','Restaurantes','Ver restaurantes y comercios',86,false),
  ('marketplace.edit','marketplace','Restaurantes','Editar comercios y banners',87,false),
  ('driver_priority.view','driver_priority','Prioridad conductores','Ver prioridad de conductores',90,false),
  ('driver_priority.edit','driver_priority','Prioridad conductores','Cambiar la prioridad de conductores',91,false),
  ('payments.view','payments','Pagos / Billetera','Ver pagos y billeteras',100,false),
  ('payments.adjust_wallet','payments','Pagos / Billetera','Ajustar saldo de billeteras',101,true),
  ('payments.settle_debt','payments','Pagos / Billetera','Saldar deudas',102,true),
  ('payments.debt_limits','payments','Pagos / Billetera','Cambiar límites de deuda',103,true),
  ('fares.view','fares','Tarifas','Ver tarifas',110,false),
  ('fares.edit','fares','Tarifas','Crear y editar tarifas',111,false),
  ('subscriptions.view','subscriptions','Suscripciones','Ver suscripciones',120,false),
  ('subscriptions.edit_plans','subscriptions','Suscripciones','Crear y editar planes',121,false),
  ('dynamic_pricing.view','dynamic_pricing','Demanda y precios','Ver demanda y precios',130,false),
  ('dynamic_pricing.edit','dynamic_pricing','Demanda y precios','Cambiar demanda y precios',131,false),
  ('reports.view','reports','Reportes','Ver reportes',140,false),
  ('reports.export','reports','Reportes','Exportar reportes',141,true),
  ('notifications.view','notifications','Notificaciones / Avisos','Ver notificaciones y avisos',150,false),
  ('notifications.send','notifications','Notificaciones / Avisos','Enviar avisos y notificaciones',151,false),
  ('zones.view','zones','Zonas y cobertura','Ver zonas y cobertura',160,false),
  ('zones.edit','zones','Zonas y cobertura','Editar zonas y cobertura',161,false),
  ('services.view','services','Servicios','Ver servicios',170,false),
  ('services.edit','services','Servicios','Editar servicios de la zona',171,false),
  ('geo_safety.view','geo_safety','Cobertura y seguridad','Ver cobertura y seguridad',180,false),
  ('geo_safety.edit','geo_safety','Cobertura y seguridad','Editar cobertura y seguridad',181,false)
on conflict (key) do update set module_key=excluded.module_key, group_label=excluded.group_label,
  label=excluded.label, sort_order=excluded.sort_order, sensitive=excluded.sensitive;

-- Los operadores que ya tenían un módulo con acciones (tarifas, avisos, pagos, suscripciones,
-- restaurantes) conservan esas acciones: reciben los permisos de ese módulo.
update public.admin_users a
set allowed_permissions = (
  select array_agg(distinct k order by k) from unnest(
    a.allowed_permissions || coalesce((
      select array_agg(c.key) from public.admin_permission_catalog c
      where c.module_key = any(coalesce(a.allowed_modules, array[]::text[]))
        and c.module_key in ('payments','fares','subscriptions','notifications','marketplace',
                             'delivery','delivery_orders','delivery_phase2','manual_dispatch',
                             'driver_priority','dynamic_pricing','reports','zones','services','geo_safety')
    ), array[]::text[])) k)
where a.access_role = 'operator';

-- Exige un permiso para actuar. Administrador: siempre. Operador: solo su zona y su permiso.
create or replace function public.admin_require_permission(p_perm text, p_zone uuid default null)
returns void language plpgsql stable security definer set search_path to 'public' as $$
declare v_role text; v_zone uuid;
begin
  select a.access_role, a.zone_id into v_role, v_zone
  from public.admin_users a join public.users u on u.id = a.user_id
  where a.user_id = auth.uid() and a.active = true and u.account_status = 'active';
  if v_role = 'super_admin' then return; end if;
  if v_role = 'operator' and v_zone is not null and (p_zone is null or p_zone = v_zone)
     and public.admin_can(p_perm, v_zone) then
    return;
  end if;
  raise exception 'No tienes permiso para esta acción. Pídeselo al administrador.';
end;
$$;
revoke all on function public.admin_require_permission(text, uuid) from public, anon, authenticated;

do $mig$
declare r record; d text; i integer;
begin
  for r in select * from (values
    ('public.admin_operator_upsert_fare_rule(uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,numeric,boolean)', 'fares.edit', 'p_zone_id'),
    ('public.admin_send_announcement_v4(text,text,text,text,uuid,uuid)', 'notifications.send', 'p_zone_id'),
    ('public.admin_finance_adjust_wallet_v1(uuid,uuid,text,numeric,text,uuid)', 'payments.adjust_wallet', 'p_zone_id'),
    ('public.admin_finance_settle_debt_v1(uuid,uuid,text,uuid)', 'payments.settle_debt', 'p_zone_id'),
    ('public.admin_finance_settle_adjustment_debt_v1(uuid,uuid,text,uuid)', 'payments.settle_debt', 'p_zone_id'),
    ('public.admin_wallet_debt_limits_set_v1(uuid,numeric,numeric)', 'payments.debt_limits', 'p_zone_id'),
    ('public.admin_operator_upsert_subscription_plan(bigint,uuid,text,text,numeric,integer,jsonb,boolean,integer)', 'subscriptions.edit_plans', 'p_zone_id'),
    ('public.admin_resolve_emergency_v3(uuid,text)', 'safety_sos.resolve', 'null::uuid'),
    ('public.admin_landing_banner_save_v1(uuid,uuid,text,text,text,text,text,text,text,text,boolean,integer,timestamptz,timestamptz)', 'marketplace.edit', 'p_zone_id'),
    ('public.admin_app_social_links_save_v1(text,text,text)', 'dashboard.edit_social_links', 'null::uuid'),
    ('public.admin_operator_update_contact(text,uuid,text,text)', 'users.edit', 'public.admin_zone_of_user(p_user_id)')
  ) as t(sig, perm, zone) loop
    d := pg_get_functiondef(r.sig::regprocedure);
    if position('admin_require_permission' in d) > 0 then continue; end if;
    i := position(E'\nbegin\n' in d);
    if i = 0 then raise exception 'No se encontró el inicio de %', r.sig; end if;
    d := substr(d, 1, i + 6)
      || '  perform public.admin_require_permission(''' || r.perm || ''', ' || r.zone || ');' || E'\n'
      || substr(d, i + 7);
    execute d;
  end loop;
end
$mig$;

-- El catálogo indica si el módulo ya funciona para operadores en el servidor.
create or replace function public.admin_permission_catalog_v1()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('key',c.key,'module_key',c.module_key,
    'group_label',c.group_label,'label',c.label,'sensitive',c.sensitive,
    'ready', coalesce((select cap.runtime_ready from public.admin_operator_module_capabilities cap
                        where cap.module_key = c.module_key), false)) order by c.sort_order)
    from public.admin_permission_catalog c), '[]'::jsonb);
end $$;

-- Resolver emergencias SOS: un operador con el permiso puede, solo en su zona.
create or replace function public.admin_zone_of_emergency(p_id uuid)
returns uuid language sql stable security definer set search_path to 'public' as $$
  select coalesce(public.admin_zone_of_trip(e.trip_id), public.admin_zone_of_user(e.user_id))
  from public.emergency_events e where e.id = p_id;
$$;
revoke all on function public.admin_zone_of_emergency(uuid) from public, anon, authenticated;
do $mig$
declare d text;
begin
  d := pg_get_functiondef('public.admin_resolve_emergency_v3(uuid,text)'::regprocedure);
  if position('public.is_admin()' in d) > 0 then
    d := replace(d, 'not public.is_admin()', 'not public.admin_can(''safety_sos.resolve'', public.admin_zone_of_emergency(p_emergency_id))');
    execute d;
  end if;
end
$mig$;
