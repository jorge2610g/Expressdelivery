-- Permisos finos para operadores de zona (fase 1: dashboard, operación en vivo,
-- viajes, conductores, usuarios y seguridad). El administrador completo conserva todo.
alter table public.admin_users add column if not exists allowed_permissions text[] not null default '{}';

create table if not exists public.admin_permission_catalog (
  key text primary key,
  module_key text not null,
  group_label text not null,
  label text not null,
  sort_order integer not null default 0,
  sensitive boolean not null default false
);
alter table public.admin_permission_catalog enable row level security;
revoke all on public.admin_permission_catalog from public, anon, authenticated;

insert into public.admin_permission_catalog(key, module_key, group_label, label, sort_order, sensitive) values
  ('dashboard.view','dashboard','Dashboard','Ver dashboard',10,false),
  ('live_operations.view','live_operations','Operación en vivo','Ver operación en vivo',20,false),
  ('trips.view','trips','Viajes','Ver viajes',30,false),
  ('trips.cancel','trips','Viajes','Cancelar viajes',31,false),
  ('trips.reassign','trips','Viajes','Reasignar conductor',32,false),
  ('trips.release','trips','Viajes','Liberar viaje',33,false),
  ('trips.start','trips','Viajes','Iniciar viaje',34,false),
  ('trips.complete','trips','Viajes','Completar viaje',35,false),
  ('drivers.view','drivers','Conductores','Ver conductores',40,false),
  ('drivers.view_documents','drivers','Conductores','Ver cédula, licencia y fotos del vehículo',41,true),
  ('drivers.edit','drivers','Conductores','Editar ficha del conductor',42,false),
  ('drivers.approve','drivers','Conductores','Aprobar conductores',43,false),
  ('drivers.reject','drivers','Conductores','Rechazar conductores',44,false),
  ('drivers.suspend','drivers','Conductores','Suspender / marcar pendiente',45,false),
  ('drivers.review_documents','drivers','Conductores','Revisar y aprobar documentos',46,true),
  ('drivers.work_permissions','drivers','Conductores','Permisos de trabajo por servicio',47,false),
  ('users.view','users','Usuarios','Ver usuarios',50,false),
  ('users.edit','users','Usuarios','Editar usuarios',51,false),
  ('users.suspend','users','Usuarios','Suspender / activar cuentas',52,false),
  ('safety_sos.view','safety_sos','Seguridad / SOS','Ver seguridad y SOS',60,false)
on conflict (key) do update set module_key=excluded.module_key, group_label=excluded.group_label,
  label=excluded.label, sort_order=excluded.sort_order, sensitive=excluded.sensitive;

-- Operadores existentes: conservan lo que ya ven (un "Ver" por módulo asignado).
update public.admin_users a
set allowed_permissions = coalesce((
  select array_agg(distinct c.key order by c.key)
  from public.admin_permission_catalog c
  where c.key = c.module_key || '.view' and c.module_key = any(coalesce(a.allowed_modules, array[]::text[]))
), array[]::text[])
where a.access_role = 'operator' and cardinality(a.allowed_permissions) = 0;

-- Zona de un usuario / de un viaje.
create or replace function public.admin_zone_of_user(p_id uuid)
returns uuid language sql stable security definer set search_path to 'public' as $$
  select case when d.id is not null then d.zone_id else u.last_zone_id end
  from public.users u left join public.driver_profiles d on d.id = u.id where u.id = p_id;
$$;
create or replace function public.admin_zone_of_trip(p_id uuid)
returns uuid language sql stable security definer set search_path to 'public' as $$
  select rr.zone_id from public.trips t join public.ride_requests rr on rr.id = t.ride_request_id where t.id = p_id;
$$;
revoke all on function public.admin_zone_of_user(uuid) from public, anon, authenticated;
revoke all on function public.admin_zone_of_trip(uuid) from public, anon, authenticated;

-- ¿Puede quien llama hacer esta acción en esta zona? Administrador: siempre.
-- Operador: solo en su zona, solo en producción y solo con el permiso marcado.
create or replace function public.admin_can(p_perm text, p_zone uuid default null)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists(
    select 1 from public.admin_users a join public.users u on u.id = a.user_id
    where a.user_id = auth.uid() and a.active = true and u.account_status = 'active'
      and (
        a.access_role = 'super_admin'
        or (
          a.access_role = 'operator' and a.zone_id is not null and p_zone is not null
          and a.zone_id = p_zone and p_perm = any(a.allowed_permissions)
          and coalesce(public.admin_environment_allowed('production'), false)
          and public.admin_current_runtime_environment() = 'production'
        )
      )
  );
$$;
revoke all on function public.admin_can(text, uuid) from public, anon;
grant execute on function public.admin_can(text, uuid) to authenticated, service_role;

-- Cada acción del panel pasa a pedir su permiso (el administrador sigue pudiendo todo).
do $mig$
declare r record; d text;
begin
  for r in select * from (values
    ('public.admin_set_driver_approval(uuid,text)',
     $e$public.admin_can(case p_status when 'approved' then 'drivers.approve' when 'rejected' then 'drivers.reject' else 'drivers.suspend' end, public.admin_zone_of_user(p_user_id))$e$),
    ('public.admin_set_account_status(uuid,text)',
     $e$public.admin_can(case when exists(select 1 from public.driver_profiles x where x.id = p_user_id) then 'drivers.suspend' else 'users.suspend' end, public.admin_zone_of_user(p_user_id))$e$),
    ('public.admin_update_driver_profile(uuid,text,text,text,text,text,uuid,text,text,text,text,text,text,text,integer)',
     $e$public.admin_can('drivers.edit', public.admin_zone_of_user(p_user_id)) and (public.is_admin() or ((p_zone_id is null or p_zone_id = public.admin_zone_of_user(p_user_id)) and (p_approval_status is null or p_approval_status = (select approval_status from public.driver_profiles where id = p_user_id)) and (p_account_status is null or p_account_status = (select account_status from public.users where id = p_user_id))))$e$),
    ('public.admin_update_user_profile(uuid,text,text,text,text,uuid)',
     $e$public.admin_can('users.edit', public.admin_zone_of_user(p_user_id)) and (public.is_admin() or ((p_zone_id is null or p_zone_id = public.admin_zone_of_user(p_user_id)) and (p_account_status is null or p_account_status = (select account_status from public.users where id = p_user_id))))$e$),
    ('public.admin_upsert_driver_document(uuid,uuid,text,text,text,text,timestamptz,text)',
     $e$public.admin_can('drivers.review_documents', public.admin_zone_of_user(p_driver_id))$e$),
    ('public.admin_driver_document_review_part_v2(uuid,text,text,text,integer,text)',
     $e$public.admin_can('drivers.review_documents', public.admin_zone_of_user((select x.driver_id from public.driver_documents x where x.id = p_document_id)))$e$),
    ('public.admin_driver_license_review_part(uuid,text,text,text,integer,text)',
     $e$public.admin_can('drivers.review_documents', public.admin_zone_of_user((select x.driver_id from public.driver_documents x where x.id = p_document_id)))$e$),
    ('public.admin_driver_kyc_bolivia_manual_review_part(uuid,text,text,text,integer,text)',
     $e$public.admin_can('drivers.review_documents', public.admin_zone_of_user((select x.driver_id from public.driver_documents x where x.id = p_document_id)))$e$),
    ('public.admin_driver_document_part_replace_v1(uuid,text,text,text)',
     $e$public.admin_can('drivers.review_documents', public.admin_zone_of_user((select x.driver_id from public.driver_documents x where x.id = p_document_id)))$e$),
    ('public.admin_driver_set_profile_photo_v1(uuid,text,text)',
     $e$public.admin_can('drivers.edit', public.admin_zone_of_user(p_driver_id))$e$),
    ('public.admin_driver_work_permission_list(uuid,text)',
     $e$public.admin_can('drivers.work_permissions', public.admin_zone_of_user(p_driver_id))$e$),
    ('public.admin_set_driver_work_permission(uuid,text,text,text)',
     $e$public.admin_can('drivers.work_permissions', public.admin_zone_of_user(p_driver_id))$e$),
    ('public.admin_trip_action_v1(uuid,text,text,uuid,text)',
     $e$public.admin_can('trips.' || p_action, public.admin_zone_of_trip(p_trip_id))$e$)
  ) as t(sig, expr) loop
    d := pg_get_functiondef(r.sig::regprocedure);
    if position('public.is_admin()' in d) = 0 then
      raise exception 'La función % ya no usa is_admin()', r.sig;
    end if;
    d := replace(d, 'public.is_admin()', '(' || r.expr || ')');
    execute d;
  end loop;
end
$mig$;

-- Ficha del conductor para operadores: cédula, licencia y vehículo solo con permiso.
do $mig$
declare d text;
begin
  d := pg_get_functiondef('public.admin_driver_detail(uuid)'::regprocedure);
  d := replace(d, 'public.admin_driver_detail(', 'public.admin_driver_detail_core(');
  d := regexp_replace(d, 'if not public\.is_admin\(\) then\s+raise exception ''No autorizado'';\s+end if;', '');
  if position('is_admin' in d) > 0 then raise exception 'No se pudo quitar la validación del núcleo'; end if;
  execute d;
end
$mig$;
revoke all on function public.admin_driver_detail_core(uuid) from public, anon, authenticated;

create or replace function public.admin_operator_driver_detail(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_result jsonb; v_core jsonb;
begin
  perform public.admin_operator_assert_record('drivers','driver',p_user_id);
  select jsonb_build_object(
    'user',jsonb_build_object('id',u.id,'full_name',u.full_name,'email',au.email,
      'phone',u.phone,'account_status',u.account_status,'last_zone_id',u.last_zone_id),
    'driver',jsonb_build_object('id',d.id,'zone_id',d.zone_id,
      'approval_status',d.approval_status,'online_status',d.online_status,
      'city',d.city,'vehicle_summary',d.vehicle_summary,
      'rating',d.rating,'completed_trips',d.completed_trips),
    'vehicles','[]'::jsonb,'documents','[]'::jsonb,
    'identity_verifications','[]'::jsonb,'subscription',null,'qa',null,
    'partner',null,'recent_trips','[]'::jsonb,
    'rating_summary',jsonb_build_object('role','driver','count',0,'average',d.rating)
  ) into v_result
  from public.driver_profiles d join public.users u on u.id=d.id
  left join auth.users au on au.id=d.id where d.id=p_user_id;
  if public.admin_can('drivers.view_documents', public.admin_zone_of_user(p_user_id)) then
    v_core := public.admin_driver_detail_core(p_user_id);
    v_result := v_result || jsonb_build_object(
      'vehicles', coalesce(v_core->'vehicles','[]'::jsonb),
      'documents', coalesce(v_core->'documents','[]'::jsonb),
      'identity_verifications', coalesce(v_core->'identity_verifications','[]'::jsonb));
  end if;
  return v_result;
end;
$$;

-- Archivos de conductores (cédula, licencia, fotos): también para el operador con permiso.
drop policy if exists driver_onboarding_read_operator_permission on storage.objects;
create policy driver_onboarding_read_operator_permission on storage.objects
  for select to authenticated
  using (
    bucket_id = 'driver-onboarding'
    and (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and public.admin_can('drivers.view_documents', public.admin_zone_of_user(((storage.foldername(name))[1])::uuid))
  );

-- Catálogo para el panel.
create or replace function public.admin_permission_catalog_v1()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('key',key,'module_key',module_key,
    'group_label',group_label,'label',label,'sensitive',sensitive) order by sort_order) from public.admin_permission_catalog), '[]'::jsonb);
end $$;
revoke all on function public.admin_permission_catalog_v1() from public, anon;
grant execute on function public.admin_permission_catalog_v1() to authenticated;

-- Guardar permisos de un operador (solo administrador). Los módulos con permisos
-- finos se derivan de los "Ver"; el resto de módulos conserva su selección.
create or replace function public.admin_set_operator_permissions_v1(p_user_id uuid, p_permissions text[])
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_perms text[]; v_catalog_modules text[]; v_modules text[]; v_current text[];
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if not exists(select 1 from public.admin_users where user_id = p_user_id and access_role = 'operator') then
    raise exception 'El usuario no es operador';
  end if;
  select coalesce(array_agg(distinct c.key order by c.key), array[]::text[]) into v_perms
  from public.admin_permission_catalog c where c.key = any(coalesce(p_permissions, array[]::text[]));
  -- Quien opera en vivo o ve SOS necesita el dashboard y ver conductores.
  if 'live_operations.view' = any(v_perms) or 'safety_sos.view' = any(v_perms) then
    v_perms := (select array_agg(distinct k order by k) from unnest(v_perms || array['dashboard.view','drivers.view']) k);
  end if;
  -- Una acción sin "Ver" de su módulo no tiene sentido: se completa.
  v_perms := (select array_agg(distinct k order by k) from unnest(v_perms || coalesce((
    select array_agg(distinct c2.module_key || '.view') from public.admin_permission_catalog c2
    where c2.key = any(v_perms) and (c2.module_key || '.view') in (select key from public.admin_permission_catalog)), array[]::text[])) k);
  select array_agg(distinct module_key) into v_catalog_modules from public.admin_permission_catalog;
  select coalesce(allowed_modules, array[]::text[]) into v_current from public.admin_users where user_id = p_user_id;
  select array_agg(distinct m order by m) into v_modules from unnest(
    array(select x from unnest(v_current) x where not (x = any(v_catalog_modules)))
    || array(select split_part(k, '.', 1) from unnest(v_perms) k where k like '%.view')
    || array['users']) m;
  update public.admin_users set allowed_permissions = v_perms, allowed_modules = v_modules, updated_at = now()
  where user_id = p_user_id;
  perform public.admin_log_action('set_operator_permissions','admin_user',p_user_id::text,
    jsonb_build_object('permissions', v_perms));
  return jsonb_build_object('ok', true, 'permissions', v_perms, 'modules', v_modules);
end $$;
revoke all on function public.admin_set_operator_permissions_v1(uuid, text[]) from public, anon;
grant execute on function public.admin_set_operator_permissions_v1(uuid, text[]) to authenticated;

-- El panel recibe los permisos del operador junto con sus módulos.
do $mig$
declare d text;
begin
  d := pg_get_functiondef('public.admin_access_context()'::regprocedure);
  if position('allowed_permissions' in d) = 0 then
    if position($k$    'assigned_modules', case when v_admin.access_role = 'operator'$k$ in d) = 0 then
      raise exception 'admin_access_context cambió de forma';
    end if;
    d := replace(d, $k$    'assigned_modules', case when v_admin.access_role = 'operator'$k$,
      $k$    'allowed_permissions', case when v_admin.access_role = 'super_admin' then '["*"]'::jsonb
      when v_admin.access_role = 'operator' then to_jsonb(coalesce(v_admin.allowed_permissions, array[]::text[]))
      else '[]'::jsonb end,
    'assigned_modules', case when v_admin.access_role = 'operator'$k$);
    execute d;
  end if;
end
$mig$;

-- La lista de accesos del panel devuelve también los permisos finos.
create or replace function public.admin_panel_access_list()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(t) order by t.access_role desc, t.email)
    from (
      select a.user_id, au.email, u.full_name, a.access_role, a.active, a.zone_id,
             z.name as zone_name, z.city, z.country, z.country_code,
             b.environment as runtime_environment, a.allowed_modules, a.allowed_permissions, a.updated_at
      from public.admin_users a
      join public.users u on u.id = a.user_id
      left join auth.users au on au.id = a.user_id
      left join public.service_zones z on z.id = a.zone_id
      left join public.account_runtime_bindings b on b.user_id = a.user_id
    ) t
  ), '[]'::jsonb);
end;
$$;
