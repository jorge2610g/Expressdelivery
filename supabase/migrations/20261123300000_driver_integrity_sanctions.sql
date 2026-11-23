-- Sanciones por irregularidades en viajes (solo Producción).
--   Ciclo 1: 3 avisos; la siguiente irregularidad suspende la cuenta 1 día.
--   Ciclo 2: otros 3 avisos; la siguiente irregularidad avisa al administrador (ciclo 3).
--   Ciclo 3: sin más acciones automáticas; el administrador decide
--            (inhabilitar de forma permanente o temporal, o reiniciar avisos).
-- Si el administrador descarta un aviso, la acción que generó se revierte.

create table if not exists public.driver_integrity_state (
  driver_id uuid primary key,
  cycle smallint not null default 1 check (cycle between 1 and 3),
  warnings_in_cycle smallint not null default 0 check (warnings_in_cycle between 0 and 3),
  suspended_until timestamptz,
  suspension_count smallint not null default 0,
  escalated_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.driver_integrity_state enable row level security;
revoke all on public.driver_integrity_state from anon, authenticated;

alter table public.trip_integrity_flags
  add column if not exists action_taken text
    check (action_taken in ('warning','suspension','escalation','none')),
  add column if not exists action_number smallint;

-- Motivos en lenguaje sencillo para el conductor.
create or replace function public.trip_integrity_reasons_text(p_reasons jsonb)
returns text
language sql
immutable
set search_path to 'public'
as $$
  select coalesce(string_agg(
    case r
      when 'termino_antes_de_lo_previsto' then 'terminó antes de lo previsto'
      when 'inicio_lejos_del_origen' then 'empezó lejos del punto de origen'
      when 'fin_lejos_del_destino' then 'terminó lejos del destino'
      when 'recorrido_mucho_menor_a_la_ruta' then 'el recorrido fue mucho menor que la ruta'
      when 'velocidad_imposible' then 'la ubicación tuvo saltos imposibles'
      when 'origen_y_destino_casi_iguales' then 'origen y destino casi iguales'
      when 'misma_pareja_repetida' then 'viajes repetidos con el mismo pasajero'
      when 'muchos_viajes_cortos_seguidos' then 'muchos viajes cortos seguidos'
      else r end, ', '), 'irregularidad detectada')
  from jsonb_array_elements_text(p_reasons) as r;
$$;

create or replace function public.driver_integrity_notify(
  p_user uuid, p_title text, p_body text, p_kind text, p_trip uuid default null)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform set_config('app.runtime_channel', 'production', true);
  insert into public.notifications(user_id, title, body, type, metadata)
  values (p_user, p_title, p_body, 'admin_announcement',
          jsonb_strip_nulls(jsonb_build_object('kind', p_kind, 'trip_id', p_trip,
                                               'channel', 'production')));
exception when others then
  null; -- avisar nunca debe impedir completar un viaje
end $$;
revoke all on function public.driver_integrity_notify(uuid, text, text, text, uuid) from public, anon, authenticated;

-- Aplica la sanción que corresponde a un viaje marcado.
create or replace function public.driver_integrity_apply(p_trip_id uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  f public.trip_integrity_flags%rowtype;
  s public.driver_integrity_state%rowtype;
  v_action text := 'none'; v_number smallint; v_name text; v_until timestamptz;
  v_reasons text; v_admin uuid;
begin
  select * into f from public.trip_integrity_flags where trip_id = p_trip_id for update;
  if f.id is null or f.action_taken is not null then return f.action_taken; end if;
  -- Solo se sanciona en Producción; en Prueba solo se marca.
  if f.channel <> 'production' then
    update public.trip_integrity_flags set action_taken = 'none' where id = f.id;
    return 'none';
  end if;

  insert into public.driver_integrity_state(driver_id) values (f.driver_id)
    on conflict (driver_id) do nothing;
  select * into s from public.driver_integrity_state where driver_id = f.driver_id for update;
  v_reasons := public.trip_integrity_reasons_text(f.reasons);

  if s.suspended_until is not null and s.suspended_until > now() then
    v_action := 'none';
  elsif s.cycle in (1, 2) and s.warnings_in_cycle < 3 then
    v_action := 'warning';
    v_number := s.warnings_in_cycle + 1;
    update public.driver_integrity_state
       set warnings_in_cycle = v_number, updated_at = now() where driver_id = s.driver_id;
    perform public.driver_integrity_notify(f.driver_id,
      'Aviso ' || v_number || ' de 3 · irregularidad en tu viaje',
      'Detectamos una irregularidad en uno de tus viajes (' || v_reasons || '). ' ||
      case when v_number >= 3
        then 'Este es tu último aviso: si ocurre otra irregularidad, ' ||
             case when s.cycle = 1 then 'tu cuenta será suspendida por un día.'
                  else 'tu cuenta pasará a revisión del administrador.' end
        else 'Si se repite, tu cuenta puede ser sancionada.' end,
      'trip_integrity_warning', f.trip_id);
  elsif s.cycle = 1 then
    v_action := 'suspension';
    v_until := now() + interval '1 day';
    v_number := s.suspension_count + 1;
    update public.driver_integrity_state
       set cycle = 2, warnings_in_cycle = 0, suspended_until = v_until,
           suspension_count = suspension_count + 1, updated_at = now()
     where driver_id = s.driver_id;
    -- Se desconecta si no tiene un viaje activo.
    update public.driver_profiles dp set online_status = 'offline', updated_at = now()
     where dp.id = f.driver_id and dp.online_status = 'online'
       and not exists (select 1 from public.trips t where t.driver_id = dp.id
                        and t.status not in ('completed','cancelled'));
    perform public.driver_integrity_notify(f.driver_id,
      'Cuenta suspendida por un día',
      'Estás suspendido por un día por irregularidad en tu cuenta (' || v_reasons ||
      '). Podrás volver a conectarte pasado ese tiempo. Después tendrás 3 avisos más ' ||
      'antes de que un administrador revise tu cuenta.',
      'trip_integrity_suspension', f.trip_id);
  elsif s.cycle = 2 then
    v_action := 'escalation';
    update public.driver_integrity_state
       set cycle = 3, escalated_at = now(), updated_at = now() where driver_id = s.driver_id;
    perform public.driver_integrity_notify(f.driver_id,
      'Tu cuenta está en revisión',
      'Detectamos irregularidades repetidas en tus viajes. Un administrador de Express ' ||
      'revisará tu cuenta y te avisará la decisión.',
      'trip_integrity_review', f.trip_id);
    select coalesce(nullif(trim(full_name), ''), 'Un conductor') into v_name
      from public.users where id = f.driver_id;
    for v_admin in select au.user_id from public.admin_users au
                    where au.active and au.access_role = 'super_admin' loop
      perform public.driver_integrity_notify(v_admin,
        'Conductor para revisión por irregularidades',
        v_name || ' repitió irregularidades después de una suspensión. ' ||
        'Revísalo en Operaciones › Viajes sospechosos.',
        'trip_integrity_admin_alert', f.trip_id);
    end loop;
  end if;

  update public.trip_integrity_flags
     set action_taken = v_action, action_number = v_number where id = f.id;
  return v_action;
end $$;
revoke all on function public.driver_integrity_apply(uuid) from public, anon, authenticated;

-- La revisión de cada viaje aplica la sanción justo después de marcarlo.
do $$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'trip_integrity_evaluate';
  if v_def is null or position('on conflict (trip_id) do nothing;' in v_def) = 0 then
    raise exception 'trip_integrity_evaluate no tiene la forma esperada';
  end if;
  if position('driver_integrity_apply' in v_def) = 0 then
    v_def := replace(v_def, 'on conflict (trip_id) do nothing;',
      E'on conflict (trip_id) do nothing;\n  perform public.driver_integrity_apply(t.id);');
    execute v_def;
  end if;
end $$;

-- Una cuenta suspendida no puede conectarse.
create or replace function public.block_suspended_driver_online()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_until timestamptz;
begin
  if new.online_status = 'online' and old.online_status is distinct from 'online' then
    select suspended_until into v_until from public.driver_integrity_state
     where driver_id = new.id;
    if v_until is not null and v_until > now() then
      raise exception 'Estás suspendido por irregularidad en tu cuenta. Podrás conectarte de nuevo el %.',
        to_char(v_until at time zone 'America/La_Paz', 'DD/MM/YYYY HH24:MI');
    end if;
  end if;
  return new;
end $$;
revoke all on function public.block_suspended_driver_online() from public, anon, authenticated;

drop trigger if exists block_suspended_driver_online on public.driver_profiles;
create trigger block_suspended_driver_online
  before update of online_status on public.driver_profiles
  for each row execute function public.block_suspended_driver_online();

-- Estado para la app del conductor (avisos y suspensión vigente).
create or replace function public.driver_integrity_status_v1()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $$
declare s public.driver_integrity_state%rowtype;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  select * into s from public.driver_integrity_state where driver_id = auth.uid();
  if s.driver_id is null then
    return jsonb_build_object('suspended', false, 'cycle', 1, 'warnings', 0);
  end if;
  return jsonb_build_object(
    'suspended', s.suspended_until is not null and s.suspended_until > now(),
    'suspended_until', s.suspended_until, 'cycle', s.cycle,
    'warnings', s.warnings_in_cycle, 'under_review', s.cycle = 3);
end $$;
revoke all on function public.driver_integrity_status_v1() from public, anon;
grant execute on function public.driver_integrity_status_v1() to authenticated;

-- Al descartar un aviso se revierte la acción que generó.
create or replace function public.admin_trip_integrity_review(
  p_flag_id uuid, p_decision text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare f public.trip_integrity_flags%rowtype; v_context jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Acceso a viajes sospechosos no autorizado';
  end if;
  if p_decision not in ('cleared','confirmed') then
    raise exception 'Decisión no válida';
  end if;
  select * into f from public.trip_integrity_flags where id = p_flag_id for update;
  if f.id is null then raise exception 'Viaje marcado no encontrado'; end if;
  if f.channel not in ('preview','production') or not public.admin_environment_allowed(f.channel) then
    raise exception 'Acceso a viajes sospechosos no autorizado';
  end if;
  v_context := public.admin_access_context();
  if v_context->>'zone_id' is not null and (v_context->>'zone_id')::uuid <> f.zone_id then
    raise exception 'Zona administrativa no autorizada';
  end if;
  if p_decision = 'cleared' and f.review_status <> 'cleared' then
    if f.action_taken = 'warning' then
      update public.driver_integrity_state
         set warnings_in_cycle = greatest(0, warnings_in_cycle - 1), updated_at = now()
       where driver_id = f.driver_id;
    elsif f.action_taken = 'suspension' then
      update public.driver_integrity_state
         set cycle = 1, warnings_in_cycle = 3, suspended_until = null,
             suspension_count = greatest(0, suspension_count - 1), updated_at = now()
       where driver_id = f.driver_id;
      perform public.driver_integrity_notify(f.driver_id, 'Suspensión levantada',
        'Revisamos tu viaje y no hubo irregularidad. Tu cuenta vuelve a estar activa.',
        'trip_integrity_cleared', f.trip_id);
    elsif f.action_taken = 'escalation' then
      update public.driver_integrity_state
         set cycle = 2, warnings_in_cycle = 3, escalated_at = null, updated_at = now()
       where driver_id = f.driver_id;
    end if;
  end if;
  update public.trip_integrity_flags
     set review_status = p_decision, reviewed_by = auth.uid(), reviewed_at = now(),
         review_note = nullif(trim(coalesce(p_note, '')), '')
   where id = f.id;
  return jsonb_build_object('ok', true, 'review_status', p_decision);
end $function$;
