-- Conductores con avisos, suspendidos o en revisión (para decisión del administrador).
create or replace function public.admin_driver_integrity_list(p_zone_id uuid, p_channel text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_context jsonb;
begin
  if auth.uid() is null or not public.is_admin()
     or p_channel not in ('preview','production')
     or not public.admin_environment_allowed(p_channel) then
    raise exception 'Acceso a viajes sospechosos no autorizado';
  end if;
  v_context := public.admin_access_context();
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid <> p_zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  return (
    select coalesce(jsonb_agg(x order by (x->>'sort') desc, (x->>'updated_at') desc), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'driver_id', s.driver_id,
        'driver_name', coalesce(nullif(trim(u.full_name), ''), 'Conductor'),
        'approval_status', dp.approval_status,
        'cycle', s.cycle, 'warnings', s.warnings_in_cycle,
        'suspended_until', s.suspended_until,
        'suspended', s.suspended_until is not null and s.suspended_until > now(),
        'suspension_count', s.suspension_count, 'escalated_at', s.escalated_at,
        'updated_at', s.updated_at,
        'open_flags', (select count(*) from public.trip_integrity_flags f
                        where f.driver_id = s.driver_id and f.review_status = 'open'),
        'sort', case when s.cycle = 3 then 3 when s.suspended_until > now() then 2 else 1 end
      ) as x
      from public.driver_integrity_state s
      join public.driver_profiles dp on dp.id = s.driver_id
      join public.users u on u.id = s.driver_id
      where dp.zone_id = p_zone_id
        and coalesce((select b.environment from public.account_runtime_bindings b
                       where b.user_id = s.driver_id), 'production') = p_channel
        and (s.cycle > 1 or s.warnings_in_cycle > 0 or s.suspended_until > now())
      limit 200
    ) q
  );
end $function$;

-- Decisiones del administrador sobre un conductor sancionado.
--   suspend_days: suspende N días; reset: reinicia avisos; lift: levanta la suspensión.
-- La inhabilitación permanente usa admin_set_driver_approval_v2(..., 'suspended', ...).
create or replace function public.admin_driver_integrity_action(
  p_driver_id uuid, p_action text, p_days integer default null, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_zone uuid; v_context jsonb; v_until timestamptz;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Acceso a viajes sospechosos no autorizado';
  end if;
  select zone_id into v_zone from public.driver_profiles where id = p_driver_id;
  if v_zone is null then raise exception 'Conductor no encontrado'; end if;
  v_context := public.admin_access_context();
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid <> v_zone then
    raise exception 'Zona administrativa no autorizada';
  end if;
  insert into public.driver_integrity_state(driver_id) values (p_driver_id)
    on conflict (driver_id) do nothing;
  if p_action = 'suspend_days' then
    if p_days is null or p_days < 1 or p_days > 365 then raise exception 'Días no válidos'; end if;
    v_until := now() + make_interval(days => p_days);
    update public.driver_integrity_state
       set suspended_until = v_until, suspension_count = suspension_count + 1, updated_at = now()
     where driver_id = p_driver_id;
    update public.driver_profiles dp set online_status = 'offline', updated_at = now()
     where dp.id = p_driver_id and dp.online_status = 'online'
       and not exists (select 1 from public.trips t where t.driver_id = dp.id
                        and t.status not in ('completed','cancelled'));
    perform public.driver_integrity_notify(p_driver_id,
      'Cuenta suspendida por ' || p_days || case when p_days = 1 then ' día' else ' días' end,
      'Un administrador de Express suspendió tu cuenta por irregularidad en tus viajes. ' ||
      coalesce(nullif(trim(p_note), '') || ' ', '') ||
      'Podrás conectarte de nuevo pasado ese tiempo.',
      'trip_integrity_suspension');
  elsif p_action = 'reset' then
    update public.driver_integrity_state
       set cycle = 1, warnings_in_cycle = 0, suspended_until = null, escalated_at = null,
           updated_at = now() where driver_id = p_driver_id;
    perform public.driver_integrity_notify(p_driver_id, 'Avisos reiniciados',
      'Un administrador revisó tu cuenta y reinició tus avisos. Recuerda que los viajes deben ' ||
      'seguir la ruta y terminar en el destino.', 'trip_integrity_cleared');
  elsif p_action = 'lift' then
    update public.driver_integrity_state
       set suspended_until = null, updated_at = now() where driver_id = p_driver_id;
    perform public.driver_integrity_notify(p_driver_id, 'Suspensión levantada',
      'Un administrador levantó la suspensión de tu cuenta.', 'trip_integrity_cleared');
  else
    raise exception 'Acción no válida';
  end if;
  return jsonb_build_object('ok', true, 'action', p_action, 'suspended_until', v_until);
end $function$;

revoke all on function public.admin_driver_integrity_list(uuid, text) from public, anon;
revoke all on function public.admin_driver_integrity_action(uuid, text, integer, text) from public, anon;
grant execute on function public.admin_driver_integrity_list(uuid, text) to authenticated;
grant execute on function public.admin_driver_integrity_action(uuid, text, integer, text) to authenticated;
