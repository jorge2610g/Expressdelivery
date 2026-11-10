-- Asesores de ventas: registro de personas que terminan su registro con el código
-- del asesor, evidencia con código de verificación y pagos por registro terminado.
--   Pasajero: Bs 1 · Conductor: Bs 2 (cuando su solicitud queda aprobada).
-- Los pagos quedan «esperando evidencia» → «por pagar» (con foto aprobada) → «pagado».
-- Todas las tablas están cerradas: solo se accede por funciones (RPC).

-- 1) Asesores
create table if not exists public.sales_advisors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  full_name text not null check (char_length(trim(full_name)) between 2 and 80),
  code text not null unique check (code ~ '^[A-Z0-9-]{4,20}$'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid
);

-- 2) Montos (editables sin cambiar código)
create table if not exists public.sales_payout_rules (
  role text primary key check (role in ('passenger', 'driver')),
  amount numeric(12, 2) not null check (amount >= 0),
  currency text not null default 'BOB',
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.sales_payout_rules (role, amount, currency) values
  ('passenger', 1, 'BOB'),
  ('driver', 2, 'BOB')
on conflict (role) do nothing;

-- 3) Personas atribuidas (una sola vez por persona)
create table if not exists public.sales_attributions (
  id bigint generated always as identity primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  advisor_id uuid not null references public.sales_advisors(id),
  role text not null check (role in ('passenger', 'driver')),
  attributed_at timestamptz not null default now(),
  registered_at timestamptz,
  flag_reason text,
  created_at timestamptz not null default now()
);
create index if not exists sales_attributions_advisor_idx
  on public.sales_attributions (advisor_id, attributed_at desc);

-- 4) Código de verificación que la app muestra al terminar el registro
create table if not exists public.sales_verification_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  code text not null check (code ~ '^[0-9]{4}$'),
  issued_at timestamptz not null default now(),
  used_at timestamptz
);

-- 5) Evidencia (foto + código ingresado por el asesor)
create table if not exists public.sales_evidence (
  id bigint generated always as identity primary key,
  attribution_id bigint not null references public.sales_attributions(id),
  advisor_id uuid not null references public.sales_advisors(id),
  storage_path text not null,
  submitted_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text
);
create index if not exists sales_evidence_attribution_idx on public.sales_evidence (attribution_id);

-- 6) Pagos a asesores
create table if not exists public.sales_payouts (
  id bigint generated always as identity primary key,
  attribution_id bigint not null unique references public.sales_attributions(id),
  advisor_id uuid not null references public.sales_advisors(id),
  role text not null,
  amount numeric(12, 2) not null,
  currency text not null,
  status text not null default 'esperando_evidencia'
    check (status in ('esperando_evidencia', 'por_pagar', 'pagado', 'cancelado')),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  paid_at timestamptz,
  paid_by uuid,
  payment_reference text
);

alter table public.sales_advisors enable row level security;
alter table public.sales_payout_rules enable row level security;
alter table public.sales_attributions enable row level security;
alter table public.sales_verification_codes enable row level security;
alter table public.sales_evidence enable row level security;
alter table public.sales_payouts enable row level security;

-- 7) Asesor actual (sesión del portal)
create or replace function public.sales_current_advisor_id()
returns uuid
language sql
stable
security definer
set search_path to 'public'
as $$
  select a.id from public.sales_advisors a
  where a.user_id = auth.uid() and a.active
$$;

-- 8) Registro terminado: se evalúa al crear la cuenta (con código), al
--    aprobarse un conductor y cuando la app lo pide (pasajero).
create or replace function public.sales_refresh_registration(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  a public.sales_attributions%rowtype;
  v_has_driver boolean;
  v_role text;
  v_driver_approved boolean;
  v_name text;
  v_phone text;
  v_email_ok boolean;
  v_dups integer := 0;
  v_rule public.sales_payout_rules%rowtype;
begin
  select * into a from public.sales_attributions where user_id = p_user_id;
  if a.id is null or a.registered_at is not null or a.flag_reason is not null then
    return;
  end if;

  select exists (select 1 from public.driver_profiles dp where dp.id = p_user_id) into v_has_driver;
  v_role := case when v_has_driver then 'driver' else 'passenger' end;
  update public.sales_attributions set role = v_role where id = a.id;

  if v_role = 'driver' then
    select exists (
      select 1 from public.driver_profiles dp
      where dp.id = p_user_id and dp.approval_status = 'approved'
    ) into v_driver_approved;
    if not v_driver_approved then
      return; -- esperando aprobación
    end if;
  else
    select u.full_name, u.phone, au.email_confirmed_at is not null
      into v_name, v_phone, v_email_ok
    from public.users u
    join auth.users au on au.id = u.id
    where u.id = p_user_id;
    if not (coalesce(v_email_ok, false)
            and nullif(trim(coalesce(v_name, '')), '') is not null
            and nullif(trim(coalesce(v_phone, '')), '') is not null) then
      return; -- perfil o correo incompletos
    end if;
    select count(*) into v_dups
    from public.users u2
    where u2.phone = v_phone and u2.id <> p_user_id;
    if v_dups > 0 then
      update public.sales_attributions
        set flag_reason = 'Teléfono repetido en otra cuenta'
        where id = a.id;
      return;
    end if;
  end if;

  update public.sales_attributions set registered_at = now() where id = a.id;

  insert into public.sales_verification_codes (user_id, code)
    values (p_user_id, lpad(floor(random() * 10000)::int::text, 4, '0'))
    on conflict (user_id) do nothing;

  select * into v_rule from public.sales_payout_rules where role = v_role and active;
  if v_rule.role is not null then
    insert into public.sales_payouts (attribution_id, advisor_id, role, amount, currency, status)
      values (a.id, a.advisor_id, v_role, v_rule.amount, v_rule.currency, 'esperando_evidencia')
      on conflict (attribution_id) do nothing;
  end if;
end
$$;

-- 9) Disparadores
create or replace function public.sales_attribute_on_signup()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_code text := upper(trim(coalesce(new.raw_user_meta_data->>'sales_code', '')));
  v_advisor uuid;
begin
  if v_code = '' then
    return new;
  end if;
  select id into v_advisor from public.sales_advisors where code = v_code and active;
  if v_advisor is null then
    return new; -- código inválido: no bloquea el registro
  end if;
  insert into public.sales_attributions (user_id, advisor_id, role)
    values (new.id, v_advisor, 'passenger')
    on conflict (user_id) do nothing;
  return new;
end
$$;

drop trigger if exists sales_attribute_on_signup on auth.users;
create trigger sales_attribute_on_signup
  after insert on auth.users
  for each row execute function public.sales_attribute_on_signup();

create or replace function public.sales_on_driver_approved()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.approval_status = 'approved' and old.approval_status is distinct from 'approved' then
    perform public.sales_refresh_registration(new.id);
  end if;
  return new;
end
$$;

drop trigger if exists sales_on_driver_approved on public.driver_profiles;
create trigger sales_on_driver_approved
  after update of approval_status on public.driver_profiles
  for each row execute function public.sales_on_driver_approved();

-- 10) La app del pasajero pide la evaluación al terminar su registro
create or replace function public.sales_check_my_registration()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;
  perform public.sales_refresh_registration(auth.uid());
end
$$;

-- 11) La app muestra el código de verificación (solo si ya terminó el registro)
create or replace function public.sales_my_verification_code()
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select c.code
  from public.sales_verification_codes c
  join public.sales_attributions a on a.user_id = c.user_id
  where c.user_id = auth.uid()
    and a.registered_at is not null
    and c.used_at is null
    and c.issued_at > now() - interval '7 days'
$$;

-- 12) Portal del asesor: su resumen
create or replace function public.sales_advisor_me()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_advisor uuid := public.sales_current_advisor_id();
  v_row public.sales_advisors%rowtype;
begin
  if v_advisor is null then
    raise exception 'No autorizado';
  end if;
  select * into v_row from public.sales_advisors where id = v_advisor;
  return jsonb_build_object(
    'advisor', jsonb_build_object('id', v_row.id, 'name', v_row.full_name, 'code', v_row.code),
    'totals', jsonb_build_object(
      'attributed', (select count(*) from public.sales_attributions a where a.advisor_id = v_advisor),
      'registered', (select count(*) from public.sales_attributions a where a.advisor_id = v_advisor and a.registered_at is not null),
      'to_pay', (select coalesce(sum(p.amount), 0) from public.sales_payouts p where p.advisor_id = v_advisor and p.status = 'por_pagar'),
      'paid', (select coalesce(sum(p.amount), 0) from public.sales_payouts p where p.advisor_id = v_advisor and p.status = 'pagado')
    )
  );
end
$$;

-- 13) Portal del asesor: lista de personas con su etapa (sin datos personales completos)
create or replace function public.sales_advisor_people()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_advisor uuid := public.sales_current_advisor_id();
begin
  if v_advisor is null then
    raise exception 'No autorizado';
  end if;
  return (
    select coalesce(jsonb_agg(x.row order by x.attributed_at desc), '[]'::jsonb)
    from (
      select
        at.attributed_at,
        jsonb_build_object(
          'attribution_id', at.id,
          'first_name', split_part(trim(coalesce(u.full_name, '')), ' ', 1),
          'role', at.role,
          'attributed_at', at.attributed_at,
          'registered_at', at.registered_at,
          'stage', case
            when at.flag_reason is not null then 'en_revision'
            when at.registered_at is null and at.role = 'driver' then 'esperando_aprobacion'
            when at.registered_at is null then 'cuenta_creada'
            when p.status = 'pagado' then 'pagado'
            when p.status = 'por_pagar' then 'aprobado_para_pago'
            when e.status = 'pending' then 'foto_en_revision'
            when e.status = 'rejected' then 'foto_rechazada'
            else 'falta_foto'
          end,
          'amount', p.amount,
          'currency', p.currency
        ) as row
      from public.sales_attributions at
      left join public.users u on u.id = at.user_id
      left join public.sales_payouts p on p.attribution_id = at.id
      left join lateral (
        select ev.status from public.sales_evidence ev
        where ev.attribution_id = at.id
        order by ev.submitted_at desc limit 1
      ) e on true
      where at.advisor_id = v_advisor
    ) x
  );
end
$$;

-- 14) Portal del asesor: enviar la foto con el código de la persona
create or replace function public.sales_submit_evidence(
  p_attribution_id bigint,
  p_code text,
  p_storage_path text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_advisor uuid := public.sales_current_advisor_id();
  a public.sales_attributions%rowtype;
  c public.sales_verification_codes%rowtype;
begin
  if v_advisor is null then
    raise exception 'No autorizado';
  end if;
  select * into a from public.sales_attributions
    where id = p_attribution_id and advisor_id = v_advisor;
  if a.id is null then
    raise exception 'Registro no encontrado';
  end if;

  perform public.sales_refresh_registration(a.user_id);
  select * into a from public.sales_attributions where id = a.id;

  if a.flag_reason is not null then
    raise exception 'Este registro está en revisión';
  end if;
  if a.registered_at is null then
    raise exception 'Esta persona todavía no termina su registro';
  end if;

  select * into c from public.sales_verification_codes where user_id = a.user_id;
  if c.user_id is null or c.used_at is not null or c.issued_at < now() - interval '7 days' then
    raise exception 'El código ya no es válido';
  end if;
  if c.code <> trim(coalesce(p_code, '')) then
    raise exception 'El código no coincide';
  end if;
  if p_storage_path is null or split_part(p_storage_path, '/', 1) <> v_advisor::text then
    raise exception 'Foto inválida';
  end if;

  insert into public.sales_evidence (attribution_id, advisor_id, storage_path)
    values (a.id, v_advisor, p_storage_path);
  update public.sales_verification_codes set used_at = now() where user_id = a.user_id;

  return jsonb_build_object('ok', true, 'status', 'pending');
end
$$;

-- 15) Admin: crear o editar asesor
create or replace function public.admin_sales_advisor_upsert(
  p_id uuid,
  p_full_name text,
  p_code text,
  p_user_id uuid,
  p_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id uuid;
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_id is null then
    insert into public.sales_advisors (full_name, code, user_id, active, created_by)
      values (trim(p_full_name), v_code, p_user_id, coalesce(p_active, true), auth.uid())
      returning id into v_id;
  else
    update public.sales_advisors
      set full_name = trim(p_full_name), code = v_code, user_id = p_user_id, active = coalesce(p_active, true)
      where id = p_id
      returning id into v_id;
  end if;
  perform public.admin_log_action('sales_advisor_upsert', 'sales_advisors', v_id::text,
    jsonb_build_object('code', v_code, 'active', coalesce(p_active, true)));
  return v_id;
end
$$;

-- 16) Admin: revisar la foto
create or replace function public.admin_sales_review_evidence(
  p_evidence_id bigint,
  p_approve boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  e public.sales_evidence%rowtype;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  select * into e from public.sales_evidence where id = p_evidence_id and status = 'pending' for update;
  if e.id is null then
    raise exception 'Evidencia no encontrada o ya revisada';
  end if;

  update public.sales_evidence
    set status = case when p_approve then 'approved' else 'rejected' end,
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        review_note = nullif(trim(coalesce(p_note, '')), '')
    where id = p_evidence_id;

  if p_approve then
    update public.sales_payouts
      set status = 'por_pagar', approved_at = now()
      where attribution_id = e.attribution_id and status = 'esperando_evidencia';
  else
    -- Se reabre el código para que el asesor vuelva a enviar la foto.
    update public.sales_verification_codes
      set used_at = null
      where user_id = (select a.user_id from public.sales_attributions a where a.id = e.attribution_id);
  end if;

  perform public.admin_log_action(
    case when p_approve then 'sales_evidence_approved' else 'sales_evidence_rejected' end,
    'sales_evidence', p_evidence_id::text,
    jsonb_strip_nulls(jsonb_build_object('attribution_id', e.attribution_id, 'note', nullif(trim(coalesce(p_note, '')), ''))));
end
$$;

-- 17) Admin: quitar la marca de revisión (teléfono repetido) y evaluar de nuevo
create or replace function public.admin_sales_clear_flag(p_attribution_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  update public.sales_attributions set flag_reason = null where id = p_attribution_id;
  perform public.sales_refresh_registration((select user_id from public.sales_attributions where id = p_attribution_id));
  perform public.admin_log_action('sales_flag_cleared', 'sales_attributions', p_attribution_id::text, '{}'::jsonb);
end
$$;

-- 18) Admin: marcar pago como pagado con referencia
create or replace function public.admin_sales_mark_paid(p_payout_id bigint, p_reference text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ref text := trim(coalesce(p_reference, ''));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if char_length(v_ref) < 3 then
    raise exception 'Escribe la referencia de la transferencia';
  end if;
  update public.sales_payouts
    set status = 'pagado', paid_at = now(), paid_by = auth.uid(), payment_reference = v_ref
    where id = p_payout_id and status = 'por_pagar';
  if not found then
    raise exception 'El pago no está por pagar';
  end if;
  perform public.admin_log_action('sales_payout_paid', 'sales_payouts', p_payout_id::text,
    jsonb_build_object('reference', v_ref));
end
$$;

-- 19) Admin: resumen por asesor y por día (últimos 30 días)
create or replace function public.admin_sales_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  return jsonb_build_object(
    'advisors', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'name', a.full_name, 'code', a.code, 'active', a.active,
        'attributed', (select count(*) from public.sales_attributions x where x.advisor_id = a.id),
        'registered', (select count(*) from public.sales_attributions x where x.advisor_id = a.id and x.registered_at is not null),
        'to_pay', (select coalesce(sum(p.amount), 0) from public.sales_payouts p where p.advisor_id = a.id and p.status = 'por_pagar'),
        'paid', (select coalesce(sum(p.amount), 0) from public.sales_payouts p where p.advisor_id = a.id and p.status = 'pagado')
      ) order by a.created_at), '[]'::jsonb)
      from public.sales_advisors a
    ),
    'by_day', (
      select coalesce(jsonb_agg(d.row order by d.day desc, d.advisor_name), '[]'::jsonb)
      from (
        select
          x.day,
          a.full_name as advisor_name,
          jsonb_build_object(
            'day', x.day,
            'advisor_id', a.id,
            'advisor', a.full_name,
            'attributed', count(*),
            'registered', count(*) filter (where x.registered_at is not null)
          ) as row
        from (
          select at.advisor_id, at.registered_at, at.attributed_at::date as day
          from public.sales_attributions at
          where at.attributed_at > now() - interval '30 days'
        ) x
        join public.sales_advisors a on a.id = x.advisor_id
        group by x.day, a.id, a.full_name
      ) d
    ),
    'evidence_pending', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'evidence_id', ev.id,
        'attribution_id', ev.attribution_id,
        'advisor', a.full_name,
        'first_name', split_part(trim(coalesce(u.full_name, '')), ' ', 1),
        'role', at.role,
        'submitted_at', ev.submitted_at,
        'storage_path', ev.storage_path
      ) order by ev.submitted_at), '[]'::jsonb)
      from public.sales_evidence ev
      join public.sales_attributions at on at.id = ev.attribution_id
      join public.sales_advisors a on a.id = ev.advisor_id
      left join public.users u on u.id = at.user_id
      where ev.status = 'pending'
    ),
    'payouts_to_pay', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'payout_id', p.id,
        'advisor', a.full_name,
        'role', p.role,
        'amount', p.amount,
        'currency', p.currency,
        'approved_at', p.approved_at
      ) order by p.approved_at), '[]'::jsonb)
      from public.sales_payouts p
      join public.sales_advisors a on a.id = p.advisor_id
      where p.status = 'por_pagar'
    )
  );
end
$$;

-- 20) Bucket privado para las fotos
insert into storage.buckets (id, name, public)
  values ('sales-evidence', 'sales-evidence', false)
  on conflict (id) do nothing;

drop policy if exists sales_evidence_advisor_insert on storage.objects;
create policy sales_evidence_advisor_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'sales-evidence'
    and exists (
      select 1 from public.sales_advisors a
      where a.user_id = auth.uid() and a.active
        and (storage.foldername(name))[1] = a.id::text
    )
  );

drop policy if exists sales_evidence_admin_read on storage.objects;
create policy sales_evidence_admin_read on storage.objects
  for select to authenticated
  using (bucket_id = 'sales-evidence' and public.is_admin());

-- 21) Permisos: solo sesiones con cuenta
revoke all on function public.sales_current_advisor_id() from public, anon;
revoke all on function public.sales_refresh_registration(uuid) from public, anon, authenticated;
revoke all on function public.sales_attribute_on_signup() from public, anon, authenticated;
revoke all on function public.sales_on_driver_approved() from public, anon, authenticated;
revoke all on function public.sales_check_my_registration() from public, anon;
revoke all on function public.sales_my_verification_code() from public, anon;
revoke all on function public.sales_advisor_me() from public, anon;
revoke all on function public.sales_advisor_people() from public, anon;
revoke all on function public.sales_submit_evidence(bigint, text, text) from public, anon;
revoke all on function public.admin_sales_advisor_upsert(uuid, text, text, uuid, boolean) from public, anon;
revoke all on function public.admin_sales_review_evidence(bigint, boolean, text) from public, anon;
revoke all on function public.admin_sales_clear_flag(bigint) from public, anon;
revoke all on function public.admin_sales_mark_paid(bigint, text) from public, anon;
revoke all on function public.admin_sales_overview() from public, anon;

grant execute on function public.sales_check_my_registration() to authenticated;
grant execute on function public.sales_my_verification_code() to authenticated;
grant execute on function public.sales_advisor_me() to authenticated;
grant execute on function public.sales_advisor_people() to authenticated;
grant execute on function public.sales_submit_evidence(bigint, text, text) to authenticated;
grant execute on function public.admin_sales_advisor_upsert(uuid, text, text, uuid, boolean) to authenticated;
grant execute on function public.admin_sales_review_evidence(bigint, boolean, text) to authenticated;
grant execute on function public.admin_sales_clear_flag(bigint) to authenticated;
grant execute on function public.admin_sales_mark_paid(bigint, text) to authenticated;
grant execute on function public.admin_sales_overview() to authenticated;
