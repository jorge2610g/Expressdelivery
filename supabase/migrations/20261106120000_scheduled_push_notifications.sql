-- Notificaciones push programadas (2026-11-06).
--
-- El propietario quiere programar avisos por horario (desayuno, almuerzo,
-- cena...) para un solo día, todos los días o días concretos de la semana,
-- sin enviarlos a mano cada vez.
--
-- Diseño:
--   * notification_schedules guarda la programación (hora local + zona horaria).
--   * notification_schedule_runs guarda cada ejecución (enviada, saltada por
--     llegar tarde o con error).
--   * notification_schedules_run_due() lo invoca pg_cron cada minuto: avanza
--     next_run_at ANTES de despachar (no hay envíos duplicados) y despacha con
--     notification_campaign_dispatch_internal().
--   * notification_campaign_dispatch_internal() es una COPIA de la lógica de
--     inserción y audiencia de admin_send_announcement_v4. v4 NO se modifica en
--     esta migración para no tocar el envío manual que ya funciona. Si se cambia
--     la audiencia en una, debe cambiarse igual en la otra.
--   * Las RPC del panel aplican las mismas reglas de rol, módulo, zona y
--     entorno que admin_send_announcement_v4.
--
-- Esta migración NO se aplica sola: requiere autorización del propietario.

-- ---------------------------------------------------------------------------
-- 1. Tablas
-- ---------------------------------------------------------------------------

create table if not exists public.notification_schedules (
  id uuid primary key default gen_random_uuid(),
  channel text not null,
  -- Si se borra la zona o el socio se borra la programación: nunca se amplía
  -- la audiencia a todo el país por un SET NULL.
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  partner_id uuid references public.partner_organizations(id) on delete cascade,
  audience text not null,
  label text not null default '',
  title text not null,
  body text not null,
  kind text not null,
  run_at timestamptz,
  days_of_week smallint[],
  time_of_day time,
  timezone text not null default 'America/La_Paz',
  starts_on date,
  ends_on date,
  active boolean not null default true,
  next_run_at timestamptz,
  last_run_at timestamptz,
  created_by uuid not null,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_schedules_channel_check
    check (channel in ('preview','production')),
  constraint notification_schedules_audience_check
    check (audience in ('drivers','passengers','all')),
  constraint notification_schedules_label_check
    check (char_length(label) <= 40),
  constraint notification_schedules_title_check
    check (char_length(title) between 1 and 90),
  constraint notification_schedules_body_check
    check (char_length(body) between 1 and 1000),
  constraint notification_schedules_kind_check
    check (kind in ('once','daily','weekly')),
  constraint notification_schedules_timezone_format_check
    check (timezone ~ '^[A-Za-z][A-Za-z0-9_+/-]{1,63}$'),
  constraint notification_schedules_dates_check
    check (starts_on is null or ends_on is null or ends_on >= starts_on),
  -- Coherencia por tipo.
  constraint notification_schedules_once_check
    check (kind <> 'once' or (
      run_at is not null
      and days_of_week is null
      and starts_on is null
      and ends_on is null
    )),
  constraint notification_schedules_daily_check
    check (kind <> 'daily' or (
      time_of_day is not null
      and run_at is null
      and days_of_week is null
    )),
  constraint notification_schedules_weekly_check
    check (kind <> 'weekly' or (
      time_of_day is not null
      and run_at is null
      and days_of_week is not null
      and cardinality(days_of_week) between 1 and 7
      and days_of_week <@ array[1,2,3,4,5,6,7]::smallint[]
    )),
  -- Una programación inactiva no tiene próxima ejecución.
  constraint notification_schedules_next_run_check
    check (active or next_run_at is null)
);

create index if not exists notification_schedules_due_idx
  on public.notification_schedules(next_run_at)
  where active;

create index if not exists notification_schedules_scope_idx
  on public.notification_schedules(channel, zone_id, active);

create table if not exists public.notification_schedule_runs (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null
    references public.notification_schedules(id) on delete cascade,
  campaign_id uuid
    references public.notification_campaigns(id) on delete set null,
  scheduled_for timestamptz not null,
  ran_at timestamptz not null default now(),
  status text not null,
  recipients integer not null default 0,
  push_enabled integer not null default 0,
  error text,
  constraint notification_schedule_runs_status_check
    check (status in ('sent','skipped_late','error')),
  -- Una programación no puede ejecutarse dos veces para la misma hora.
  constraint notification_schedule_runs_once_per_slot
    unique (schedule_id, scheduled_for)
);

create index if not exists notification_schedule_runs_recent_idx
  on public.notification_schedule_runs(schedule_id, ran_at desc);

-- Solo las funciones SECURITY DEFINER leen o escriben estas tablas.
alter table public.notification_schedules enable row level security;
alter table public.notification_schedule_runs enable row level security;
revoke all on table public.notification_schedules from public, anon, authenticated;
revoke all on table public.notification_schedule_runs from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Cálculo de la siguiente fecha (función pura)
-- ---------------------------------------------------------------------------

-- Devuelve la primera ejecución estrictamente posterior a p_after, o null si
-- ya no quedan. La fecha y hora se interpretan en la zona horaria del registro
-- ("(fecha + hora) at time zone tz"), así el horario de verano de Chile queda
-- resuelto por la base de zonas horarias de PostgreSQL. starts_on y ends_on
-- son fechas locales e inclusivas.
create or replace function public.notification_schedule_next_run(
  p_kind text,
  p_run_at timestamptz,
  p_days_of_week smallint[],
  p_time_of_day time,
  p_timezone text,
  p_starts_on date,
  p_ends_on date,
  p_after timestamptz
)
returns timestamptz
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_after timestamptz := coalesce(p_after, now());
  v_day date;
  v_candidate timestamptz;
  i integer;
begin
  if p_kind = 'once' then
    if p_run_at is not null and p_run_at > v_after then
      return p_run_at;
    end if;
    return null;
  end if;

  if p_kind not in ('daily','weekly')
     or p_time_of_day is null
     or p_timezone is null then
    return null;
  end if;
  if p_kind = 'weekly' and coalesce(cardinality(p_days_of_week), 0) = 0 then
    return null;
  end if;

  -- Día local de partida. Se revisan 15 días: cubre cualquier semana aunque
  -- la hora de hoy ya haya pasado.
  v_day := (v_after at time zone p_timezone)::date;
  if p_starts_on is not null and p_starts_on > v_day then
    v_day := p_starts_on;
  end if;

  for i in 0..14 loop
    if p_ends_on is not null and v_day > p_ends_on then
      return null;
    end if;
    if p_kind = 'daily'
       or extract(isodow from v_day)::smallint = any(p_days_of_week) then
      v_candidate := (v_day + p_time_of_day) at time zone p_timezone;
      if v_candidate > v_after then
        return v_candidate;
      end if;
    end if;
    v_day := v_day + 1;
  end loop;
  return null;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Despacho interno (copia de la lógica de admin_send_announcement_v4)
-- ---------------------------------------------------------------------------

-- NO ejecutable por clientes. No comprueba el rol: lo hacen sus llamadores.
-- Mantener la consulta de audiencia idéntica a admin_send_announcement_v4.
create or replace function public.notification_campaign_dispatch_internal(
  p_channel text,
  p_title text,
  p_body text,
  p_audience text,
  p_zone_id uuid,
  p_partner_id uuid,
  p_created_by uuid,
  p_extra_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel),''),''));
  v_campaign uuid;
  v_count integer := 0;
  v_push integer := 0;
  v_title text := trim(coalesce(p_title,''));
  v_body text := trim(coalesce(p_body,''));
begin
  if v_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  if char_length(v_title)<1 or char_length(v_title)>90 then raise exception 'Título inválido'; end if;
  if char_length(v_body)<1 or char_length(v_body)>1000 then raise exception 'Mensaje inválido'; end if;
  if p_audience is null or p_audience not in ('drivers','passengers','all') then
    raise exception 'Audiencia inválida';
  end if;

  insert into public.notification_campaigns(
    title,body,audience,zone_id,partner_id,created_by,channel
  )
  values(
    v_title,v_body,p_audience,p_zone_id,p_partner_id,p_created_by,v_channel
  )
  returning id into v_campaign;

  with audience_users as (
    select u.id,
      (
        exists(select 1 from public.native_push_tokens n where n.user_id=u.id and n.active=true)
        or exists(select 1 from public.push_subscriptions s where s.user_id=u.id and s.active=true)
      ) as has_push
    from public.users u
    left join public.driver_profiles dp on dp.id=u.id
    where u.account_status='active'
      and (
        p_audience='all'
        or (p_audience='drivers' and dp.id is not null and dp.approval_status='approved')
        or (p_audience='passengers' and (u.active_mode='passenger' or dp.id is null or dp.approval_status<>'approved'))
      )
      and (p_zone_id is null or (case when p_audience='drivers' then dp.zone_id when p_audience='passengers' then u.last_zone_id when dp.id is not null and dp.approval_status='approved' then dp.zone_id else u.last_zone_id end)=p_zone_id)
      and (
        p_partner_id is null or exists(
          select 1
          from public.driver_partner_memberships m
          where m.driver_id=u.id and m.partner_id=p_partner_id and m.status='active'
        )
      )
      and (
        (v_channel='preview' and exists(
          select 1 from public.audit_test_group_members q
          where q.enabled=true and q.user_id=u.id
        ))
        or
        (v_channel='production' and not exists(
          select 1 from public.audit_test_group_members q
          where q.enabled=true and q.user_id=u.id
        ))
      )
  ),
  inserted as (
    insert into public.notifications(
      user_id,title,body,type,metadata,campaign_id,channel
    )
    select
      a.id,v_title,v_body,'admin_announcement',
      jsonb_strip_nulls(jsonb_build_object(
        'audience',p_audience,
        'zone_id',p_zone_id,
        'partner_id',p_partner_id,
        'campaign',true,
        'campaign_id',v_campaign,
        'environment',v_channel
      )) || coalesce(p_extra_metadata,'{}'::jsonb),
      v_campaign,
      v_channel
    from audience_users a
    returning id,user_id
  )
  select
    (select count(*)::int from inserted),
    (select count(*)::int from audience_users where has_push)
  into v_count,v_push;

  update public.notification_campaigns
  set recipients_targeted=coalesce(v_count,0),
      push_enabled_recipients=coalesce(v_push,0)
  where id=v_campaign;

  return jsonb_build_object(
    'campaign_id',v_campaign,
    'channel',v_channel,
    'recipients',coalesce(v_count,0),
    'push_enabled',coalesce(v_push,0),
    'audience',p_audience,
    'zone_id',p_zone_id,
    'partner_id',p_partner_id
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Ayudantes internos de las RPC del panel
-- ---------------------------------------------------------------------------

-- Mismas reglas que admin_send_announcement_v4: el monitor no puede; el
-- operador necesita el módulo notifications y queda en su zona; si no, debe
-- ser super administrador. Después se valida el entorno de la cuenta.
-- Devuelve la zona efectiva (siempre una zona concreta).
create or replace function public.notification_schedule_assert_access(
  p_channel text,
  p_zone_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel),''),'production'));
  v_zone uuid := p_zone_id;
begin
  if public.admin_zone_role_now()='zone_monitor' then
    raise exception 'El monitor no puede enviar notificaciones';
  end if;
  if public.admin_zone_role_now()='operator' then
    perform public.admin_operator_assert_module('notifications');
    v_zone := public.admin_effective_zone_id(p_zone_id);
  elsif not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  perform public.admin_assert_environment(public.normalize_runtime_channel(p_channel));
  if v_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  if v_zone is null then
    raise exception 'Selecciona país y zona antes de programar avisos';
  end if;
  if not exists(select 1 from public.service_zones z where z.id=v_zone) then
    raise exception 'Zona inválida';
  end if;
  return v_zone;
end;
$function$;

-- Zona horaria por defecto según el país de la zona.
create or replace function public.notification_schedule_default_timezone(
  p_zone_id uuid
)
returns text
language sql
stable
security definer
set search_path to 'public'
as $function$
  select case upper(coalesce(z.country_code, ''))
           when 'CL' then 'America/Santiago'
           when 'BO' then 'America/La_Paz'
           else case lower(coalesce(z.country, ''))
                  when 'chile' then 'America/Santiago'
                  else 'America/La_Paz'
                end
         end
  from public.service_zones z
  where z.id = p_zone_id
$function$;

-- Valida y normaliza la definición de horario. Lanza error si no es válida.
create or replace function public.notification_schedule_check_definition(
  p_kind text,
  p_run_on date,
  p_time_of_day time,
  p_days_of_week integer[],
  p_timezone text,
  p_starts_on date,
  p_ends_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_kind text := lower(trim(coalesce(p_kind,'')));
  v_time time;
  v_days smallint[];
  v_run_at timestamptz;
begin
  if v_kind not in ('once','daily','weekly') then
    raise exception 'Tipo de programación inválido';
  end if;
  if p_timezone is null or not exists(
    select 1 from pg_catalog.pg_timezone_names t where t.name = p_timezone
  ) then
    raise exception 'Zona horaria inválida';
  end if;
  if p_time_of_day is null then
    raise exception 'Indica la hora';
  end if;
  -- Siempre en minutos exactos.
  v_time := make_time(
    extract(hour from p_time_of_day)::int,
    extract(minute from p_time_of_day)::int,
    0
  );

  if v_kind = 'once' then
    if p_run_on is null then
      raise exception 'Indica la fecha';
    end if;
    v_run_at := (p_run_on + v_time) at time zone p_timezone;
    return jsonb_build_object(
      'kind', v_kind,
      'run_at', v_run_at,
      'time_of_day', v_time,
      'days_of_week', null,
      'starts_on', null,
      'ends_on', null
    );
  end if;

  if p_starts_on is not null and p_ends_on is not null and p_ends_on < p_starts_on then
    raise exception 'La fecha final es anterior a la inicial';
  end if;

  if v_kind = 'weekly' then
    if p_days_of_week is null or cardinality(p_days_of_week) = 0 then
      raise exception 'Elige al menos un día de la semana';
    end if;
    if exists(select 1 from unnest(p_days_of_week) d where d is null or d < 1 or d > 7) then
      raise exception 'Día de la semana inválido';
    end if;
    select array_agg(distinct d::smallint order by d::smallint)
      into v_days
    from unnest(p_days_of_week) d;
  end if;

  return jsonb_build_object(
    'kind', v_kind,
    'run_at', null,
    'time_of_day', v_time,
    'days_of_week', to_jsonb(v_days),
    'starts_on', p_starts_on,
    'ends_on', p_ends_on
  );
end;
$function$;

-- Registro de auditoría con la misma rama que admin_send_announcement_v4.
create or replace function public.notification_schedule_audit(
  p_action text,
  p_schedule_id uuid,
  p_details jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if public.admin_zone_role_now()='operator' then
    insert into public.admin_audit_log(admin_user_id,action,entity_type,entity_id,details)
    values(auth.uid(),p_action,'notification_schedules',p_schedule_id::text,
      coalesce(p_details,'{}'::jsonb));
  else
    perform public.admin_log_action(
      p_action,'notification_schedules',p_schedule_id::text,
      coalesce(p_details,'{}'::jsonb));
  end if;
end;
$function$;

-- Límite contra spam: máximo 50 programaciones activas por canal y zona.
create or replace function public.notification_schedule_assert_capacity(
  p_channel text,
  p_zone_id uuid,
  p_exclude_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  -- Serializa altas/activaciones concurrentes del mismo canal y zona.
  perform pg_advisory_xact_lock(
    hashtextextended('notification_schedules:'||p_channel||':'||p_zone_id::text, 0)
  );
  if (
    select count(*)
    from public.notification_schedules s
    where s.channel = p_channel
      and s.zone_id = p_zone_id
      and s.active
      and (p_exclude_id is null or s.id <> p_exclude_id)
  ) >= 50 then
    raise exception 'Máximo 50 programaciones activas por zona';
  end if;
end;
$function$;

-- Fila de programación para el panel.
create or replace function public.notification_schedule_row_json(
  p_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', s.id,
    'channel', s.channel,
    'zone_id', s.zone_id,
    'zone_name', z.name,
    'partner_id', s.partner_id,
    'partner_name', p.name,
    'audience', s.audience,
    'label', s.label,
    'title', s.title,
    'body', s.body,
    'kind', s.kind,
    'run_at', s.run_at,
    'run_on', case when s.run_at is not null
                   then to_char(s.run_at at time zone s.timezone, 'YYYY-MM-DD') end,
    'days_of_week', to_jsonb(s.days_of_week),
    'time_of_day', to_char(coalesce(s.time_of_day,
                     (s.run_at at time zone s.timezone)::time), 'HH24:MI'),
    'timezone', s.timezone,
    'starts_on', s.starts_on,
    'ends_on', s.ends_on,
    'active', s.active,
    'next_run_at', s.next_run_at,
    'next_run_local', case when s.next_run_at is not null
                   then to_char(s.next_run_at at time zone s.timezone, 'YYYY-MM-DD HH24:MI') end,
    'last_run_at', s.last_run_at,
    'created_at', s.created_at,
    'updated_at', s.updated_at,
    'recent_runs', coalesce((
      select jsonb_agg(jsonb_build_object(
          'scheduled_for', r.scheduled_for,
          'scheduled_local', to_char(r.scheduled_for at time zone s.timezone, 'YYYY-MM-DD HH24:MI'),
          'ran_at', r.ran_at,
          'status', r.status,
          'recipients', r.recipients,
          'push_enabled', r.push_enabled,
          'error', r.error,
          'campaign_id', r.campaign_id
        ) order by r.scheduled_for desc)
      from (
        select *
        from public.notification_schedule_runs r0
        where r0.schedule_id = s.id
        order by r0.scheduled_for desc
        limit 5
      ) r
    ), '[]'::jsonb)
  )
  from public.notification_schedules s
  left join public.service_zones z on z.id = s.zone_id
  left join public.partner_organizations p on p.id = s.partner_id
  where s.id = p_id
$function$;

-- ---------------------------------------------------------------------------
-- 5. RPC del panel
-- ---------------------------------------------------------------------------

create or replace function public.admin_notification_schedule_save_v1(
  p_channel text,
  p_zone_id uuid,
  p_id uuid,
  p_label text,
  p_title text,
  p_body text,
  p_audience text,
  p_partner_id uuid,
  p_kind text,
  p_run_on date,
  p_time_of_day time,
  p_days_of_week integer[],
  p_timezone text,
  p_starts_on date,
  p_ends_on date,
  p_active boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel),''),'production'));
  v_zone uuid;
  v_def jsonb;
  v_timezone text;
  v_label text := trim(coalesce(p_label,''));
  v_title text := trim(coalesce(p_title,''));
  v_body text := trim(coalesce(p_body,''));
  v_active boolean := coalesce(p_active, true);
  v_run_at timestamptz;
  v_days smallint[];
  v_time time;
  v_next timestamptz;
  v_existing public.notification_schedules%rowtype;
  v_id uuid;
begin
  v_zone := public.notification_schedule_assert_access(p_channel, p_zone_id);

  if char_length(v_label) > 40 then raise exception 'Etiqueta demasiado larga'; end if;
  if char_length(v_title)<1 or char_length(v_title)>90 then raise exception 'Título inválido'; end if;
  if char_length(v_body)<1 or char_length(v_body)>1000 then raise exception 'Mensaje inválido'; end if;
  if p_audience is null or p_audience not in ('drivers','passengers','all') then
    raise exception 'Audiencia inválida';
  end if;
  if p_partner_id is not null and not exists(
     select 1 from public.partner_organizations p
     where p.id=p_partner_id and p.zone_id=v_zone
  ) then raise exception 'El socio no pertenece a tu zona'; end if;

  v_timezone := coalesce(nullif(trim(p_timezone),''),
                         public.notification_schedule_default_timezone(v_zone));
  v_def := public.notification_schedule_check_definition(
    p_kind, p_run_on, p_time_of_day, p_days_of_week, v_timezone,
    p_starts_on, p_ends_on);
  v_run_at := (v_def->>'run_at')::timestamptz;
  v_time := case when v_def->>'kind' = 'once' then null
                 else (v_def->>'time_of_day')::time end;
  if jsonb_typeof(v_def->'days_of_week') = 'array' then
    select array_agg(value::smallint order by value::smallint)
      into v_days
    from jsonb_array_elements_text(v_def->'days_of_week');
  end if;

  v_next := public.notification_schedule_next_run(
    v_def->>'kind', v_run_at, v_days, v_time, v_timezone,
    (v_def->>'starts_on')::date, (v_def->>'ends_on')::date, now());

  if v_active and v_next is null then
    if v_def->>'kind' = 'once' then
      raise exception 'La fecha y hora elegidas ya pasaron';
    end if;
    raise exception 'No quedan fechas dentro del período elegido';
  end if;

  if p_id is not null then
    select * into v_existing
    from public.notification_schedules s
    where s.id = p_id
    for update;
    if not found or v_existing.channel <> v_channel or v_existing.zone_id <> v_zone then
      raise exception 'Programación no encontrada';
    end if;
  end if;

  if v_active then
    perform public.notification_schedule_assert_capacity(v_channel, v_zone, p_id);
  end if;

  if p_id is null then
    insert into public.notification_schedules(
      channel, zone_id, partner_id, audience, label, title, body, kind,
      run_at, days_of_week, time_of_day, timezone, starts_on, ends_on,
      active, next_run_at, created_by, updated_by
    )
    values(
      v_channel, v_zone, p_partner_id, p_audience, v_label, v_title, v_body,
      v_def->>'kind', v_run_at, v_days, v_time, v_timezone,
      (v_def->>'starts_on')::date, (v_def->>'ends_on')::date,
      v_active, case when v_active then v_next end, auth.uid(), auth.uid()
    )
    returning id into v_id;
  else
    update public.notification_schedules
    set partner_id = p_partner_id,
        audience = p_audience,
        label = v_label,
        title = v_title,
        body = v_body,
        kind = v_def->>'kind',
        run_at = v_run_at,
        days_of_week = v_days,
        time_of_day = v_time,
        timezone = v_timezone,
        starts_on = (v_def->>'starts_on')::date,
        ends_on = (v_def->>'ends_on')::date,
        active = v_active,
        next_run_at = case when v_active then v_next end,
        updated_by = auth.uid(),
        updated_at = now()
    where id = p_id
    returning id into v_id;
  end if;

  perform public.notification_schedule_audit(
    case when p_id is null then 'notification_schedule_create'
         else 'notification_schedule_update' end,
    v_id,
    jsonb_build_object(
      'environment', v_channel, 'zone_id', v_zone, 'partner_id', p_partner_id,
      'audience', p_audience, 'kind', v_def->>'kind', 'label', v_label,
      'title', v_title, 'timezone', v_timezone, 'active', v_active,
      'next_run_at', v_next));

  return public.notification_schedule_row_json(v_id);
end;
$function$;

create or replace function public.admin_notification_schedule_list_v1(
  p_channel text,
  p_zone_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel),''),'production'));
  v_zone uuid;
begin
  v_zone := public.notification_schedule_assert_access(p_channel, p_zone_id);
  return coalesce((
    select jsonb_agg(public.notification_schedule_row_json(s.id)
                     order by s.active desc, s.next_run_at nulls last, s.created_at desc)
    from public.notification_schedules s
    where s.channel = v_channel
      and s.zone_id = v_zone
  ), '[]'::jsonb);
end;
$function$;

create or replace function public.admin_notification_schedule_set_active_v1(
  p_channel text,
  p_zone_id uuid,
  p_id uuid,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel),''),'production'));
  v_zone uuid;
  v_row public.notification_schedules%rowtype;
  v_next timestamptz;
begin
  v_zone := public.notification_schedule_assert_access(p_channel, p_zone_id);
  if p_active is null then raise exception 'Estado inválido'; end if;

  select * into v_row
  from public.notification_schedules s
  where s.id = p_id
  for update;
  if not found or v_row.channel <> v_channel or v_row.zone_id <> v_zone then
    raise exception 'Programación no encontrada';
  end if;

  if p_active then
    v_next := public.notification_schedule_next_run(
      v_row.kind, v_row.run_at, v_row.days_of_week, v_row.time_of_day,
      v_row.timezone, v_row.starts_on, v_row.ends_on, now());
    if v_next is null then
      raise exception 'No quedan fechas futuras: edita la fecha u hora';
    end if;
    if v_row.kind = 'once' and exists(
      select 1 from public.notification_schedule_runs r
      where r.schedule_id = v_row.id and r.scheduled_for = v_row.run_at
    ) then
      raise exception 'Este aviso ya se envió: edita la fecha u hora';
    end if;
    perform public.notification_schedule_assert_capacity(v_channel, v_zone, v_row.id);
  end if;

  update public.notification_schedules
  set active = p_active,
      next_run_at = case when p_active then v_next end,
      updated_by = auth.uid(),
      updated_at = now()
  where id = v_row.id;

  perform public.notification_schedule_audit(
    case when p_active then 'notification_schedule_activate'
         else 'notification_schedule_pause' end,
    v_row.id,
    jsonb_build_object('environment', v_channel, 'zone_id', v_zone,
                       'next_run_at', v_next));

  return public.notification_schedule_row_json(v_row.id);
end;
$function$;

create or replace function public.admin_notification_schedule_delete_v1(
  p_channel text,
  p_zone_id uuid,
  p_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_channel text := lower(coalesce(nullif(trim(p_channel),''),'production'));
  v_zone uuid;
  v_row public.notification_schedules%rowtype;
begin
  v_zone := public.notification_schedule_assert_access(p_channel, p_zone_id);

  select * into v_row
  from public.notification_schedules s
  where s.id = p_id
  for update;
  if not found or v_row.channel <> v_channel or v_row.zone_id <> v_zone then
    raise exception 'Programación no encontrada';
  end if;

  delete from public.notification_schedules where id = v_row.id;

  perform public.notification_schedule_audit(
    'notification_schedule_delete',
    v_row.id,
    jsonb_build_object('environment', v_channel, 'zone_id', v_zone,
                       'label', v_row.label, 'title', v_row.title,
                       'kind', v_row.kind, 'audience', v_row.audience));

  return jsonb_build_object('deleted', true, 'id', v_row.id);
end;
$function$;

-- Próximas fechas (por defecto 5) sin guardar nada.
create or replace function public.admin_notification_schedule_preview_v1(
  p_channel text,
  p_zone_id uuid,
  p_kind text,
  p_run_on date,
  p_time_of_day time,
  p_days_of_week integer[],
  p_timezone text,
  p_starts_on date,
  p_ends_on date,
  p_count integer default 5
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_zone uuid;
  v_timezone text;
  v_def jsonb;
  v_days smallint[];
  v_time time;
  v_run_at timestamptz;
  v_after timestamptz := now();
  v_next timestamptz;
  v_result jsonb := '[]'::jsonb;
  v_limit integer := greatest(1, least(coalesce(p_count, 5), 10));
  i integer;
begin
  v_zone := public.notification_schedule_assert_access(p_channel, p_zone_id);
  v_timezone := coalesce(nullif(trim(p_timezone),''),
                         public.notification_schedule_default_timezone(v_zone));
  v_def := public.notification_schedule_check_definition(
    p_kind, p_run_on, p_time_of_day, p_days_of_week, v_timezone,
    p_starts_on, p_ends_on);
  v_run_at := (v_def->>'run_at')::timestamptz;
  v_time := case when v_def->>'kind' = 'once' then null
                 else (v_def->>'time_of_day')::time end;
  if jsonb_typeof(v_def->'days_of_week') = 'array' then
    select array_agg(value::smallint order by value::smallint)
      into v_days
    from jsonb_array_elements_text(v_def->'days_of_week');
  end if;

  for i in 1..v_limit loop
    v_next := public.notification_schedule_next_run(
      v_def->>'kind', v_run_at, v_days, v_time, v_timezone,
      (v_def->>'starts_on')::date, (v_def->>'ends_on')::date, v_after);
    exit when v_next is null;
    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'at', v_next,
      'local', to_char(v_next at time zone v_timezone, 'YYYY-MM-DD HH24:MI'),
      'weekday', extract(isodow from (v_next at time zone v_timezone))::int,
      'timezone', v_timezone));
    v_after := v_next;
  end loop;

  return jsonb_build_object('timezone', v_timezone, 'runs', v_result);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Ejecutor (pg_cron cada minuto)
-- ---------------------------------------------------------------------------

create or replace function public.notification_schedules_run_due()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r public.notification_schedules%rowtype;
  v_now timestamptz := clock_timestamp();
  v_due timestamptz;
  v_next timestamptz;
  v_owner uuid;
  v_run uuid;
  v_result jsonb;
  v_owner_revoked boolean;
  v_processed integer := 0;
begin
  for r in
    select *
    from public.notification_schedules s
    where s.active
      and s.next_run_at is not null
      and s.next_run_at <= v_now
    order by s.next_run_at
    limit 200
    for update skip locked
  loop
    v_due := r.next_run_at;
    v_processed := v_processed + 1;
    begin
      -- 1) Avanzar primero: aunque el despacho falle, no se repite el envío.
      if r.kind = 'once' then
        v_next := null;
      else
        v_next := public.notification_schedule_next_run(
          r.kind, r.run_at, r.days_of_week, r.time_of_day, r.timezone,
          r.starts_on, r.ends_on, greatest(v_now, v_due));
      end if;
      update public.notification_schedules
      set next_run_at = v_next,
          active = (r.kind <> 'once' and v_next is not null),
          last_run_at = v_now
      where id = r.id;

      -- 2) Reservar la ejecución (única por programación y hora).
      v_run := null;
      if r.last_run_at is null
         or date_trunc('minute', r.last_run_at) <> date_trunc('minute', v_now) then
        insert into public.notification_schedule_runs(
          schedule_id, scheduled_for, ran_at, status
        )
        values(
          r.id, v_due, v_now,
          case when v_now - v_due > interval '15 minutes'
               then 'skipped_late' else 'error' end
        )
        on conflict (schedule_id, scheduled_for) do nothing
        returning id into v_run;
      end if;

      -- 3) Despachar solo si se reservó y no llegó tarde.
      if v_run is not null and v_now - v_due <= interval '15 minutes' then
        v_owner := coalesce(r.updated_by, r.created_by);
        v_owner_revoked := false;
        begin
          -- La cuenta que programó el aviso debe seguir autorizada.
          if not exists(
            select 1
            from public.admin_users a
            join public.users u on u.id = a.user_id
            where a.user_id = v_owner
              and a.active = true
              and u.account_status = 'active'
              and (
                (r.channel = 'preview' and a.allow_preview and a.access_role = 'super_admin')
                or (r.channel = 'production' and a.allow_production)
              )
              and (
                a.access_role = 'super_admin'
                or (
                  a.access_role = 'operator'
                  and a.zone_id = r.zone_id
                  and 'notifications' = any(coalesce(a.allowed_modules, array[]::text[]))
                )
              )
          ) then
            -- Las variables PL/pgSQL no se deshacen con el bloque.
            v_owner_revoked := true;
            raise exception 'La cuenta que programó el aviso ya no tiene permiso';
          end if;

          v_result := public.notification_campaign_dispatch_internal(
            r.channel, r.title, r.body, r.audience, r.zone_id, r.partner_id,
            v_owner,
            jsonb_build_object('schedule_id', r.id, 'scheduled', true));

          update public.notification_schedule_runs
          set status = 'sent',
              campaign_id = (v_result->>'campaign_id')::uuid,
              recipients = coalesce((v_result->>'recipients')::int, 0),
              push_enabled = coalesce((v_result->>'push_enabled')::int, 0),
              error = null
          where id = v_run;
        exception when others then
          update public.notification_schedule_runs
          set status = 'error',
              error = left(sqlerrm, 500)
          where id = v_run;
          if v_owner_revoked then
            -- Se pausa: un administrador autorizado debe revisarla y activarla.
            update public.notification_schedules
            set active = false, next_run_at = null
            where id = r.id;
          end if;
        end;
      end if;
    exception when others then
      -- Error inesperado (p. ej. zona horaria ya inexistente): se pausa esta
      -- programación para no reintentar en bucle y se sigue con las demás.
      begin
        update public.notification_schedules
        set active = false, next_run_at = null, last_run_at = v_now
        where id = r.id;
        insert into public.notification_schedule_runs(
          schedule_id, scheduled_for, ran_at, status, error
        )
        values(r.id, v_due, v_now, 'error', left(sqlerrm, 500))
        on conflict (schedule_id, scheduled_for) do nothing;
      exception when others then
        null;
      end;
    end;
  end loop;
  return v_processed;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Permisos
-- ---------------------------------------------------------------------------

-- Funciones internas: ningún cliente puede ejecutarlas.
revoke all on function public.notification_schedule_next_run(text,timestamptz,smallint[],time,text,date,date,timestamptz)
  from public, anon, authenticated;
revoke all on function public.notification_campaign_dispatch_internal(text,text,text,text,uuid,uuid,uuid,jsonb)
  from public, anon, authenticated;
revoke all on function public.notification_schedule_assert_access(text,uuid)
  from public, anon, authenticated;
revoke all on function public.notification_schedule_default_timezone(uuid)
  from public, anon, authenticated;
revoke all on function public.notification_schedule_check_definition(text,date,time,integer[],text,date,date)
  from public, anon, authenticated;
revoke all on function public.notification_schedule_audit(text,uuid,jsonb)
  from public, anon, authenticated;
revoke all on function public.notification_schedule_assert_capacity(text,uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.notification_schedule_row_json(uuid)
  from public, anon, authenticated;
revoke all on function public.notification_schedules_run_due()
  from public, anon, authenticated;

-- RPC del panel: solo usuarios autenticados (y dentro validan rol y entorno).
revoke all on function public.admin_notification_schedule_save_v1(text,uuid,uuid,text,text,text,text,uuid,text,date,time,integer[],text,date,date,boolean)
  from public, anon;
revoke all on function public.admin_notification_schedule_list_v1(text,uuid)
  from public, anon;
revoke all on function public.admin_notification_schedule_set_active_v1(text,uuid,uuid,boolean)
  from public, anon;
revoke all on function public.admin_notification_schedule_delete_v1(text,uuid,uuid)
  from public, anon;
revoke all on function public.admin_notification_schedule_preview_v1(text,uuid,text,date,time,integer[],text,date,date,integer)
  from public, anon;

grant execute on function public.admin_notification_schedule_save_v1(text,uuid,uuid,text,text,text,text,uuid,text,date,time,integer[],text,date,date,boolean)
  to authenticated;
grant execute on function public.admin_notification_schedule_list_v1(text,uuid)
  to authenticated;
grant execute on function public.admin_notification_schedule_set_active_v1(text,uuid,uuid,boolean)
  to authenticated;
grant execute on function public.admin_notification_schedule_delete_v1(text,uuid,uuid)
  to authenticated;
grant execute on function public.admin_notification_schedule_preview_v1(text,uuid,text,date,time,integer[],text,date,date,integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Job de pg_cron (idempotente)
-- ---------------------------------------------------------------------------

create extension if not exists pg_cron with schema pg_catalog;
do $cron$
begin
  if exists(select 1 from cron.job
            where jobname = 'notification-schedules-every-minute') then
    perform cron.unschedule('notification-schedules-every-minute');
  end if;
  perform cron.schedule(
    'notification-schedules-every-minute',
    '* * * * *',
    $job$select public.notification_schedules_run_due()$job$
  );
end;
$cron$;
