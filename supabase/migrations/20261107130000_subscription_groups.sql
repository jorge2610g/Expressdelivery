-- Grupos de suscripción: «General» (conductores sin sindicato) y cada sindicato.
--
-- Cada grupo tiene sus propios planes (precio y duración) y sus interruptores:
--   * mostrar (enabled): la app muestra la suscripción y permite comprarla.
--   * exigir (enforce_access): sin suscripción vigente no se puede conectar ni recibir ofertas.
-- Si «mostrar» está apagado, «exigir» también se apaga (no se puede exigir lo que no se muestra).
--
-- Reglas:
--   * El conductor pertenece a un sindicato si tiene membresía activa en un sindicato activo
--     de su misma zona. Si no, pertenece a «General».
--   * El tiempo de suscripción (driver_zone_subscriptions) no depende del grupo: quien ya tiene
--     tiempo lo conserva; cuando se acaba, compra con el precio de su grupo actual.
--   * Un sindicato nuevo copia la tarifa General (planes e interruptores) al crearse y después
--     se edita por separado. Cambiar la General no cambia los sindicatos existentes.
--   * La comisión del sindicato no cambia: sigue tomándose de la membresía al crear el pago.
--
-- Cambios:
--   1. driver_subscription_plans.partner_id (null = General).
--   2. Tabla driver_subscription_partner_settings (interruptores por sindicato).
--   3. Copia inicial para sindicatos existentes y para sindicatos nuevos (trigger).
--   4. Bloqueo, estado, catálogo y pagos (incluida billetera) usan el grupo del conductor.
--   5. Alta de planes generales solo toca planes General.
--   6. RPC de super admin para editar grupos, planes y borrar planes de un sindicato.
-- Solo archivo nuevo: no se aplica en producción sin autorización del propietario.

-- 1. Planes por grupo -------------------------------------------------------------

alter table public.driver_subscription_plans
  add column if not exists partner_id uuid
    references public.partner_organizations(id) on delete cascade;

drop index if exists public.driver_subscription_plans_zone_code_uidx;

create unique index if not exists driver_subscription_plans_general_code_uidx
  on public.driver_subscription_plans (zone_key, code)
  where partner_id is null;

create unique index if not exists driver_subscription_plans_partner_code_uidx
  on public.driver_subscription_plans (partner_id, code)
  where partner_id is not null;

-- 2. Interruptores por sindicato --------------------------------------------------

create table if not exists public.driver_subscription_partner_settings (
  partner_id uuid primary key
    references public.partner_organizations(id) on delete cascade,
  zone_id uuid not null
    references public.service_zones(id) on delete cascade,
  enabled boolean not null default false,
  enforce_access boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.driver_subscription_partner_settings enable row level security;
revoke all on table public.driver_subscription_partner_settings from public, anon, authenticated;

-- 3. Copia de la tarifa General a un sindicato ------------------------------------

create or replace function public.subscription_group_seed_partner_v1(p_partner_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_zone_id uuid;
  v_zone_key text;
  v_enabled boolean := false;
  v_enforce boolean := false;
begin
  select o.zone_id into v_zone_id
  from public.partner_organizations o
  where o.id = p_partner_id;

  if v_zone_id is null then
    return;
  end if;

  select z.zone_key into v_zone_key
  from public.service_zones z
  where z.id = v_zone_id;

  if v_zone_key is null then
    return;
  end if;

  select coalesce(s.enabled, false), coalesce(s.enforce_access, false)
    into v_enabled, v_enforce
  from public.driver_subscription_zone_settings s
  where s.zone_id = v_zone_id;

  insert into public.driver_subscription_partner_settings
    (partner_id, zone_id, enabled, enforce_access, updated_at)
  values
    (p_partner_id, v_zone_id, coalesce(v_enabled, false), coalesce(v_enforce, false), now())
  on conflict (partner_id) do nothing;

  insert into public.driver_subscription_plans
    (zone_key, currency_code, code, name, amount, days, benefits,
     active, sort_order, partner_id, updated_at)
  select g.zone_key, g.currency_code, g.code, g.name, g.amount, g.days, g.benefits,
         g.active, g.sort_order, p_partner_id, now()
  from public.driver_subscription_plans g
  where g.zone_key = v_zone_key
    and g.partner_id is null
  on conflict do nothing;
end;
$$;

revoke all on function public.subscription_group_seed_partner_v1(uuid) from public, anon, authenticated;

create or replace function public.trg_partner_subscription_group_seed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.subscription_group_seed_partner_v1(new.id);
  return new;
end;
$$;

revoke all on function public.trg_partner_subscription_group_seed() from public, anon, authenticated;

drop trigger if exists partner_subscription_group_seed on public.partner_organizations;
create trigger partner_subscription_group_seed
  after insert on public.partner_organizations
  for each row execute function public.trg_partner_subscription_group_seed();

-- Sindicatos que ya existen: copia inicial (idempotente).
select public.subscription_group_seed_partner_v1(o.id)
from public.partner_organizations o;

-- 4a. Grupo del conductor y sus interruptores -------------------------------------

create or replace function public.subscription_group_for_driver(p_driver_id uuid, p_zone_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.partner_id
  from public.driver_partner_memberships m
  join public.partner_organizations p on p.id = m.partner_id
  join public.driver_subscription_partner_settings s on s.partner_id = m.partner_id
  where m.driver_id = p_driver_id
    and m.status = 'active'
    and p.status = 'active'
    and p.zone_id = p_zone_id
    and s.zone_id = p_zone_id
  order by m.started_at desc nulls last
  limit 1;
$$;

revoke all on function public.subscription_group_for_driver(uuid, uuid) from public, anon, authenticated;

create or replace function public.subscription_group_flags(p_zone_id uuid, p_partner_id uuid)
returns table (enabled boolean, enforce_access boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_partner_id is null then
    return query
      select coalesce(z.enabled, false), coalesce(z.enforce_access, false)
      from public.driver_subscription_zone_settings z
      where z.zone_id = p_zone_id;
  else
    return query
      select coalesce(s.enabled, false), coalesce(s.enforce_access, false)
      from public.driver_subscription_partner_settings s
      where s.partner_id = p_partner_id;
  end if;
end;
$$;

revoke all on function public.subscription_group_flags(uuid, uuid) from public, anon, authenticated;

-- 4b. Bloqueo de despacho: usa el interruptor del grupo del conductor -------------

create or replace function public.driver_subscription_allows_dispatch(p_driver_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_zone_id uuid;
  v_group uuid;
  v_enforce boolean := false;
begin
  if p_driver_id is null then return false; end if;

  select dp.zone_id into v_zone_id
  from public.driver_profiles dp
  where dp.id = p_driver_id;

  if v_zone_id is null then return true; end if;

  v_group := public.subscription_group_for_driver(p_driver_id, v_zone_id);

  select f.enforce_access into v_enforce
  from public.subscription_group_flags(v_zone_id, v_group) f;

  if not coalesce(v_enforce, false) then
    return true;
  end if;

  return exists(
    select 1
    from public.driver_zone_subscriptions s
    join public.driver_subscription_plans p on p.id = s.plan_id
    join public.service_zones z on z.id = s.zone_id
    where s.driver_id = p_driver_id
      and s.zone_id = v_zone_id
      and s.status = 'active'
      and s.expires_at > now()
      and p.active = true
      and p.zone_key = z.zone_key
  );
end;
$$;

-- 4c. Estado de suscripción del conductor (app) -----------------------------------

create or replace function public.my_driver_subscription_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_zone_id uuid;
  v_zone_key text;
  v_zone_name text;
  v_zone_enabled boolean := false;
  v_zone_enforce boolean := false;
  v_group uuid;
  v_group_name text;
  v_global public.driver_subscription_settings%rowtype;
  v_sub public.driver_zone_subscriptions%rowtype;
  v_plan public.driver_subscription_plans%rowtype;
  v_usable boolean := false;
  v_display_status text := 'inactive';
begin
  if v_uid is null then raise exception 'Sesión requerida'; end if;

  select dp.zone_id, z.zone_key, z.name
  into v_zone_id, v_zone_key, v_zone_name
  from public.driver_profiles dp
  left join public.service_zones z on z.id = dp.zone_id
  where dp.id = v_uid;

  select * into v_global
  from public.driver_subscription_settings
  where id = true;

  if v_zone_id is not null then
    v_group := public.subscription_group_for_driver(v_uid, v_zone_id);

    select f.enabled, f.enforce_access
    into v_zone_enabled, v_zone_enforce
    from public.subscription_group_flags(v_zone_id, v_group) f;

    if v_group is not null then
      select o.name into v_group_name
      from public.partner_organizations o
      where o.id = v_group;
    end if;

    select * into v_sub
    from public.driver_zone_subscriptions
    where driver_id = v_uid
      and zone_id = v_zone_id;
  end if;

  if v_sub.plan_id is not null then
    select * into v_plan
    from public.driver_subscription_plans
    where id = v_sub.plan_id;
  end if;

  v_usable := coalesce(
    v_sub.status = 'active'
    and v_sub.expires_at > now()
    and v_plan.zone_key = v_zone_key,
    false
  );

  v_display_status := case
    when v_usable then 'active'
    when v_sub.status = 'active'
      and v_sub.expires_at is not null
      and v_sub.expires_at <= now()
    then 'expired'
    else coalesce(v_sub.status, 'inactive')
  end;

  return jsonb_build_object(
    'feature_enabled', coalesce(v_zone_enabled, false),
    'enforce_access', coalesce(v_zone_enforce, false),
    'provider', coalesce(v_global.provider, 'veripagos'),
    'provider_enabled', coalesce(v_global.provider_enabled, false),
    'qr_validity', coalesce(v_global.qr_validity, '0/00:15'),
    'zone_id', v_zone_id,
    'zone_key', v_zone_key,
    'zone_name', v_zone_name,
    'group_partner_id', v_group,
    'group_name', coalesce(v_group_name, 'General'),
    'usable', v_usable,
    'status', v_display_status,
    'plan_id', v_sub.plan_id,
    'plan_name', v_plan.name,
    'plan_code', v_plan.code,
    'plan_zone_key', v_plan.zone_key,
    'started_at', v_sub.started_at,
    'expires_at', v_sub.expires_at,
    'remaining_seconds', case
      when v_sub.expires_at is null then 0
      else greatest(0, extract(epoch from (v_sub.expires_at - now()))::bigint)
    end
  );
end;
$$;

-- 4d. Catálogo de planes para el conductor (solo planes de su grupo) --------------

create or replace function public.driver_subscription_catalog_for_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_zone_id uuid;
  v_zone_key text;
  v_zone_name text;
  v_currency text;
  v_group uuid;
  v_group_name text;
  v_enabled boolean := false;
  v_enforce boolean := false;
  v_global public.driver_subscription_settings%rowtype;
  v_plans jsonb;
  v_payment_provider_key text;
  v_payment_provider_label text;
  v_provider text;
  v_provider_enabled boolean := false;
  v_provider_configured boolean := false;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;

  select dp.zone_id into v_zone_id
  from public.driver_profiles dp
  where dp.id = v_uid;

  if v_zone_id is null then
    return jsonb_build_object(
      'zone', null, 'enabled', false, 'enforce_access', false,
      'provider', null, 'provider_enabled', false, 'provider_configured', false,
      'payment_provider_key', null, 'payment_provider_label', null,
      'group', null, 'plans', '[]'::jsonb
    );
  end if;

  select z.zone_key, z.name, z.currency_code
  into v_zone_key, v_zone_name, v_currency
  from public.service_zones z
  where z.id = v_zone_id;

  v_group := public.subscription_group_for_driver(v_uid, v_zone_id);

  select f.enabled, f.enforce_access
  into v_enabled, v_enforce
  from public.subscription_group_flags(v_zone_id, v_group) f;

  if v_group is not null then
    select o.name into v_group_name
    from public.partner_organizations o
    where o.id = v_group;
  end if;

  select * into v_global
  from public.driver_subscription_settings
  where id = true;

  select m.provider_key, c.display_name
  into v_payment_provider_key, v_payment_provider_label
  from public.zone_payment_methods m
  join public.payment_method_catalog c on c.provider_key = m.provider_key
  where m.zone_id = v_zone_id
    and m.enabled = true
    and m.use_subscriptions = true
  order by m.is_primary desc, m.sort_order, c.display_name
  limit 1;

  if v_payment_provider_key = 'veripagos_qr' then
    v_provider := 'veripagos';
    v_provider_configured := coalesce(v_global.provider_enabled, false);
    v_provider_enabled := coalesce(v_global.provider_enabled, false);
  elsif v_payment_provider_key = 'mercado_pago' then
    v_provider := 'mercado_pago';
    select exists(
      select 1
      from private.zone_payment_provider_settings p
      where p.zone_id = v_zone_id
        and p.provider = 'mercado_pago'
        and nullif(trim(p.access_token), '') is not null
        and nullif(trim(p.public_key), '') is not null
        and nullif(p.extra_config->>'verified_at', '') is not null
        and p.extra_config->>'site_id' = 'MLC'
    ) into v_provider_configured;
    v_provider_enabled := v_provider_configured;
  elsif v_payment_provider_key is not null then
    v_provider := v_payment_provider_key;
  end if;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.sort_order, p.id), '[]'::jsonb)
  into v_plans
  from public.driver_subscription_plans p
  where p.zone_key = v_zone_key
    and p.active = true
    and p.partner_id is not distinct from v_group;

  return jsonb_build_object(
    'zone', jsonb_build_object(
      'id', v_zone_id, 'zone_key', v_zone_key,
      'name', v_zone_name, 'currency_code', v_currency
    ),
    'enabled', coalesce(v_enabled, false),
    'enforce_access', coalesce(v_enforce, false),
    'provider', v_provider,
    'provider_enabled', coalesce(v_provider_enabled, false),
    'provider_configured', coalesce(v_provider_configured, false),
    'payment_provider_key', v_payment_provider_key,
    'payment_provider_label', v_payment_provider_label,
    'qr_validity', coalesce(v_global.qr_validity, '0/00:15'),
    'group', jsonb_build_object('partner_id', v_group, 'name', coalesce(v_group_name, 'General')),
    'plans', coalesce(v_plans, '[]'::jsonb)
  );
end;
$$;

-- 4e. Pago por QR/proveedor: el plan debe ser del grupo del conductor -------------

create or replace function public.service_create_driver_subscription_payment(
  p_driver_id uuid,
  p_plan_id bigint,
  p_provider text default 'veripagos',
  p_expires_at timestamptz default null
)
returns public.driver_subscription_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan public.driver_subscription_plans%rowtype;
  v_existing public.driver_subscription_payments%rowtype;
  v_payment public.driver_subscription_payments%rowtype;
  v_zone_key text;
  v_zone_id uuid;
  v_group uuid;
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'veripagos');
begin
  select * into v_plan
  from public.driver_subscription_plans
  where id = p_plan_id and active = true;
  if not found then raise exception 'Plan no disponible'; end if;

  select z.id, z.zone_key into v_zone_id, v_zone_key
  from public.driver_profiles dp
  join public.service_zones z on z.id = dp.zone_id
  where dp.id = p_driver_id;

  if v_zone_key is null then
    raise exception 'No se pudo determinar la zona del conductor';
  end if;
  if v_plan.zone_key <> v_zone_key then
    raise exception 'El plan no está disponible en tu zona actual';
  end if;

  v_group := public.subscription_group_for_driver(p_driver_id, v_zone_id);
  if v_plan.partner_id is distinct from v_group then
    raise exception 'Este plan no corresponde a tu grupo de suscripción';
  end if;

  -- Un conductor solo puede tener un pago pendiente vigente a la vez (cualquier plan o proveedor).
  select * into v_existing
  from public.driver_subscription_payments
  where driver_id = p_driver_id
    and status = 'pending'
    and (expires_at is null or expires_at > now())
  order by created_at desc
  limit 1;
  if found then
    if v_existing.plan_id = p_plan_id and v_existing.provider = v_provider then
      return v_existing;
    end if;
    raise exception 'Tienes un pago pendiente. Cancélalo antes de generar otro.';
  end if;

  insert into public.driver_subscription_payments(
    driver_id, plan_id, amount, currency_code, provider, status, expires_at, zone_key
  )
  values (
    p_driver_id, v_plan.id, v_plan.amount, v_plan.currency_code,
    v_provider, 'pending',
    coalesce(p_expires_at, now() + interval '30 minutes'),
    v_plan.zone_key
  )
  returning * into v_payment;

  return v_payment;
end;
$$;

-- 4f. Pago con Billetera Express (zona, cuenta y grupo del conductor) -------------

create or replace function public.pay_driver_subscription_with_wallet(p_plan_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_plan public.driver_subscription_plans%rowtype;
  v_zone public.service_zones%rowtype;
  v_group uuid;
  v_enabled boolean := false;
  v_wallet public.wallet_accounts%rowtype;
  v_payment public.driver_subscription_payments%rowtype;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Sesión requerida';
  end if;

  if not exists(select 1 from public.driver_profiles d where d.id = v_uid) then
    raise exception 'Perfil de conductor requerido';
  end if;

  select p.* into v_plan
  from public.driver_subscription_plans p
  where p.id = p_plan_id and p.active = true;
  if not found then raise exception 'Plan no disponible'; end if;

  select z.* into v_zone
  from public.driver_profiles d
  join public.service_zones z on z.id = d.zone_id
  where d.id = v_uid and z.active = true;
  if not found then
    raise exception 'No se pudo determinar la zona del conductor';
  end if;

  if v_plan.zone_key <> v_zone.zone_key then
    raise exception 'El plan no está disponible en tu zona actual';
  end if;

  v_group := public.subscription_group_for_driver(v_uid, v_zone.id);
  if v_plan.partner_id is distinct from v_group then
    raise exception 'Este plan no corresponde a tu grupo de suscripción';
  end if;

  select f.enabled into v_enabled
  from public.subscription_group_flags(v_zone.id, v_group) f;

  if not coalesce(v_enabled, false) then
    raise exception 'Las suscripciones no están habilitadas para tu grupo';
  end if;

  perform public.ensure_wallet();

  select * into v_wallet
  from public.wallet_accounts
  where user_id = v_uid
  for update;

  if upper(coalesce(v_wallet.currency, '')) <> upper(coalesce(v_plan.currency_code, '')) then
    raise exception
      'La billetera está en % y este plan se cobra en %. No se mezclan monedas.',
      v_wallet.currency, v_plan.currency_code;
  end if;

  if coalesce(v_wallet.balance, 0) < v_plan.amount then
    raise exception 'Saldo insuficiente en la billetera';
  end if;

  insert into public.driver_subscription_payments(
    driver_id, plan_id, amount, currency_code, provider, status,
    provider_data, paid_at, expires_at, zone_key
  )
  values (
    v_uid, v_plan.id, v_plan.amount, v_plan.currency_code,
    'wallet', 'pending',
    jsonb_build_object('source', 'express_wallet', 'balance_before', v_wallet.balance),
    now(), now() + interval '15 minutes', v_plan.zone_key
  )
  returning * into v_payment;

  update public.wallet_accounts
  set balance = balance - v_plan.amount,
      updated_at = now()
  where user_id = v_uid;

  insert into public.wallet_transactions(user_id, amount, type, status, reference, created_at)
  values (
    v_uid, -v_plan.amount, 'payment', 'completed',
    'driver_subscription:' || v_payment.id::text, now()
  );

  v_result := public.service_finalize_driver_subscription_payment(
    v_payment.id,
    'wallet-' || v_payment.id::text,
    jsonb_build_object(
      'source', 'express_wallet',
      'balance_before', v_wallet.balance,
      'balance_after', v_wallet.balance - v_plan.amount
    )
  );

  update public.driver_subscription_history
  set notes = 'Billetera Express',
      zone_key = v_plan.zone_key
  where payment_id = v_payment.id
    and action = 'payment_approved';

  insert into public.notifications(user_id, title, body, type, metadata)
  values (
    v_uid,
    'Suscripción activada',
    'Tu plan ' || v_plan.name || ' fue pagado con Billetera Express.',
    'driver_subscription',
    jsonb_build_object(
      'payment_id', v_payment.id,
      'plan_id', v_plan.id,
      'zone_key', v_plan.zone_key,
      'provider', 'wallet'
    )
  );

  return v_result || jsonb_build_object(
    'provider', 'wallet',
    'payment_id', v_payment.id,
    'balance_before', v_wallet.balance,
    'balance_after', v_wallet.balance - v_plan.amount,
    'currency_code', v_plan.currency_code
  );
end;
$$;

create or replace function public.pay_driver_subscription_with_country_wallet(p_plan_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_plan public.driver_subscription_plans%rowtype;
  v_zone public.service_zones%rowtype;
  v_group uuid;
  v_enabled boolean := false;
  v_wallet public.wallet_country_accounts%rowtype;
  v_payment public.driver_subscription_payments%rowtype;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Sesión requerida';
  end if;

  if not exists(select 1 from public.driver_profiles d where d.id = v_uid) then
    raise exception 'Perfil de conductor requerido';
  end if;

  select z.* into v_zone
  from public.driver_profiles d
  join public.service_zones z on z.id = d.zone_id
  where d.id = v_uid and z.active = true;
  if not found then raise exception 'No se pudo determinar la zona del conductor'; end if;

  select p.* into v_plan
  from public.driver_subscription_plans p
  where p.id = p_plan_id and p.active = true and p.zone_key = v_zone.zone_key;
  if not found then raise exception 'Plan no disponible en tu zona actual'; end if;

  v_group := public.subscription_group_for_driver(v_uid, v_zone.id);
  if v_plan.partner_id is distinct from v_group then
    raise exception 'Este plan no corresponde a tu grupo de suscripción';
  end if;

  select f.enabled into v_enabled
  from public.subscription_group_flags(v_zone.id, v_group) f;

  if not coalesce(v_enabled, false) then
    raise exception 'Las suscripciones no están habilitadas para tu grupo';
  end if;

  perform public.ensure_country_wallet_v2('production');

  select * into v_wallet
  from public.wallet_country_accounts
  where user_id = v_uid
    and country_code = v_zone.country_code
    and channel = 'production'
  for update;

  if upper(coalesce(v_wallet.currency, '')) <> upper(coalesce(v_plan.currency_code, '')) then
    raise exception 'La billetera del país está en % y este plan se cobra en %.',
      v_wallet.currency, v_plan.currency_code;
  end if;
  if coalesce(v_wallet.balance, 0) < v_plan.amount then
    raise exception 'Saldo insuficiente en la billetera';
  end if;

  insert into public.driver_subscription_payments(
    driver_id, plan_id, amount, currency_code,
    provider, status, provider_data, paid_at, expires_at, zone_key
  )
  values (
    v_uid, v_plan.id, v_plan.amount, v_plan.currency_code,
    'wallet', 'pending',
    jsonb_build_object(
      'source', 'country_wallet', 'country_code', v_zone.country_code,
      'channel', 'production', 'balance_before', v_wallet.balance
    ),
    now(), now() + interval '15 minutes', v_plan.zone_key
  )
  returning * into v_payment;

  insert into public.wallet_transactions(
    user_id, amount, type, status, reference, country_code, channel, created_at
  )
  values (
    v_uid, -v_plan.amount, 'payment', 'completed',
    'driver_subscription:' || v_payment.id::text,
    v_zone.country_code, 'production', now()
  );

  perform public.mirror_legacy_wallet_delta(v_uid, v_plan.currency_code, -v_plan.amount);

  v_result := public.service_finalize_driver_subscription_payment(
    v_payment.id,
    'country-wallet-' || v_payment.id::text,
    jsonb_build_object(
      'source', 'country_wallet', 'country_code', v_zone.country_code,
      'channel', 'production', 'balance_before', v_wallet.balance,
      'balance_after', v_wallet.balance - v_plan.amount
    )
  );

  return v_result || jsonb_build_object(
    'provider', 'wallet', 'payment_id', v_payment.id,
    'country_code', v_zone.country_code, 'channel', 'production',
    'balance_before', v_wallet.balance,
    'balance_after', v_wallet.balance - v_plan.amount,
    'currency_code', v_plan.currency_code
  );
end;
$$;

-- 5. Alta de planes General: solo toca planes sin sindicato ----------------------

create or replace function public.admin_upsert_driver_subscription_plan(
  p_id bigint,
  p_zone_key text,
  p_code text,
  p_name text,
  p_amount numeric,
  p_days integer,
  p_benefits jsonb,
  p_active boolean,
  p_sort_order integer
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_zone public.service_zones%rowtype;
  v_code text;
begin
  perform public.admin_assert_environment('production');
  -- E1-20261010 production guard
  perform public.is_admin();
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select * into v_zone
  from public.service_zones
  where zone_key = lower(trim(p_zone_key))
  limit 1;
  if not found then raise exception 'Zona no encontrada'; end if;

  v_code := lower(trim(coalesce(p_code, '')));
  if v_code !~ '^[a-z][a-z0-9_]{1,39}$' then
    raise exception 'Código de plan inválido';
  end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'Nombre requerido'; end if;
  if coalesce(p_amount, -1) < 0 then raise exception 'Precio inválido'; end if;
  if coalesce(p_days, 0) < 1 then raise exception 'Duración inválida'; end if;
  if jsonb_typeof(coalesce(p_benefits, '[]'::jsonb)) <> 'array' then
    raise exception 'Beneficios inválidos';
  end if;

  if p_id is null then
    insert into public.driver_subscription_plans(
      code, name, amount, days, currency_code, benefits, active, sort_order, zone_key, updated_at
    )
    values (
      v_code, trim(p_name), p_amount, p_days, v_zone.currency_code,
      coalesce(p_benefits, '[]'::jsonb), coalesce(p_active, true),
      coalesce(p_sort_order, 100), v_zone.zone_key, now()
    )
    returning id into v_id;
  else
    update public.driver_subscription_plans
    set code = v_code,
        name = trim(p_name),
        amount = p_amount,
        days = p_days,
        currency_code = v_zone.currency_code,
        benefits = coalesce(p_benefits, '[]'::jsonb),
        active = coalesce(p_active, true),
        sort_order = coalesce(p_sort_order, 100),
        updated_at = now()
    where id = p_id
      and zone_key = v_zone.zone_key
      and partner_id is null
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Plan no encontrado en esta zona'; end if;
  return v_id;
end;
$$;

create or replace function public.admin_operator_upsert_subscription_plan(
  p_id bigint,
  p_zone_id uuid,
  p_code text,
  p_name text,
  p_amount numeric,
  p_days integer,
  p_benefits jsonb,
  p_active boolean,
  p_sort_order integer
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v_zone uuid; v_key text; v_currency text; v_code text; v_id bigint;
begin
  perform public.admin_operator_assert_module('subscriptions');
  v_zone := public.admin_effective_zone_id(p_zone_id);
  select z.zone_key, z.currency_code into v_key, v_currency
  from public.service_zones z where z.id = v_zone and z.active = true;
  if v_key is null then raise exception 'Zona inactiva'; end if;
  v_code := lower(trim(coalesce(p_code, '')));
  if v_code !~ '^[a-z][a-z0-9_]{1,39}$' then raise exception 'Codigo invalido'; end if;
  if nullif(trim(coalesce(p_name, '')), '') is null then raise exception 'Nombre requerido'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'Monto invalido'; end if;
  if p_days is null or p_days < 1 or p_days > 3650 then raise exception 'Duracion invalida'; end if;
  if jsonb_typeof(coalesce(p_benefits, '[]'::jsonb)) <> 'array' then
    raise exception 'Beneficios invalidos';
  end if;
  if p_id is not null and not exists(
    select 1 from public.driver_subscription_plans p
    where p.id = p_id and p.zone_key = v_key and p.partner_id is null
  ) then raise exception 'Plan de otra zona o inexistente'; end if;

  if p_id is null then
    insert into public.driver_subscription_plans
      (zone_key, currency_code, code, name, amount, days, benefits, active, sort_order, updated_at)
    values (v_key, v_currency, v_code, trim(p_name), p_amount, p_days,
            coalesce(p_benefits, '[]'::jsonb), coalesce(p_active, true),
            coalesce(p_sort_order, 100), now())
    returning id into v_id;
  else
    update public.driver_subscription_plans
    set code = v_code, name = trim(p_name), amount = p_amount, days = p_days,
        currency_code = v_currency, benefits = coalesce(p_benefits, '[]'::jsonb),
        active = coalesce(p_active, true), sort_order = coalesce(p_sort_order, 100),
        updated_at = now()
    where id = p_id and zone_key = v_key and partner_id is null
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Plan no guardado'; end if;
  insert into public.admin_audit_log(admin_user_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'operator_subscription_plan_upsert', 'driver_subscription_plans', v_id::text,
          jsonb_build_object('zone_id', v_zone, 'amount', p_amount, 'currency', v_currency));
  return v_id;
end;
$$;

create or replace function public.admin_operator_subscription_overview(p_zone_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_zone uuid; v_key text; v_currency text; v_name text;
begin
  perform public.admin_operator_assert_module('subscriptions');
  v_zone := public.admin_effective_zone_id(p_zone_id);
  select z.zone_key, z.currency_code, z.name into v_key, v_currency, v_name
  from public.service_zones z where z.id = v_zone and z.active = true;
  if v_key is null then raise exception 'Zona inactiva'; end if;

  return jsonb_build_object(
    'zone_id', v_zone, 'zone_key', v_key, 'zone_name', v_name, 'currency_code', v_currency,
    'plans', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.sort_order, p.name)
      from public.driver_subscription_plans p
      where p.zone_key = v_key and p.partner_id is null
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select sp.id, sp.driver_id, sp.plan_id, sp.amount, sp.currency_code,
               sp.status, sp.provider, sp.created_at, sp.paid_at
        from public.driver_subscription_payments sp
        where sp.zone_key = v_key
        order by sp.created_at desc
        limit 100
      ) x
    ), '[]'::jsonb),
    'enabled', coalesce((select s.enabled from public.driver_subscription_zone_settings s where s.zone_id = v_zone), false),
    'enforce_access', coalesce((select s.enforce_access from public.driver_subscription_zone_settings s where s.zone_id = v_zone), false)
  );
end;
$$;

-- 6. Panel de super admin: grupos, interruptores y planes por sindicato ----------

create or replace function public.admin_subscription_groups_v1(p_zone_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_zone public.service_zones%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select * into v_zone
  from public.service_zones
  where zone_key = lower(trim(p_zone_key))
  limit 1;
  if not found then raise exception 'Zona no encontrada'; end if;

  return jsonb_build_object(
    'zone_key', v_zone.zone_key,
    'currency_code', v_zone.currency_code,
    'general', jsonb_build_object(
      'enabled', coalesce((select s.enabled from public.driver_subscription_zone_settings s where s.zone_id = v_zone.id), false),
      'enforce_access', coalesce((select s.enforce_access from public.driver_subscription_zone_settings s where s.zone_id = v_zone.id), false),
      'plans', coalesce((
        select jsonb_agg(to_jsonb(p) order by p.sort_order, p.id)
        from public.driver_subscription_plans p
        where p.zone_key = v_zone.zone_key and p.partner_id is null
      ), '[]'::jsonb)
    ),
    'partners', coalesce((
      select jsonb_agg(q.item order by q.name)
      from (
        select o.name,
               jsonb_build_object(
                 'partner_id', o.id,
                 'name', o.name,
                 'status', o.status,
                 'enabled', coalesce(s.enabled, false),
                 'enforce_access', coalesce(s.enforce_access, false),
                 'plans', coalesce((
                   select jsonb_agg(to_jsonb(p) order by p.sort_order, p.id)
                   from public.driver_subscription_plans p
                   where p.partner_id = o.id
                 ), '[]'::jsonb)
               ) as item
        from public.partner_organizations o
        left join public.driver_subscription_partner_settings s on s.partner_id = o.id
        where o.zone_id = v_zone.id
      ) q
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_subscription_partner_settings_set_v1(
  p_partner_id uuid,
  p_enabled boolean,
  p_enforce_access boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_zone_id uuid;
  v_row public.driver_subscription_partner_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select o.zone_id into v_zone_id
  from public.partner_organizations o
  where o.id = p_partner_id;
  if v_zone_id is null then raise exception 'Sindicato no encontrado o sin zona'; end if;

  perform public.subscription_group_seed_partner_v1(p_partner_id);

  update public.driver_subscription_partner_settings
  set enabled = coalesce(p_enabled, false),
      enforce_access = coalesce(p_enabled, false) and coalesce(p_enforce_access, false),
      updated_at = now(),
      updated_by = auth.uid()
  where partner_id = p_partner_id
  returning * into v_row;

  if v_row.enforce_access then
    update public.driver_profiles dp
    set online_status = 'offline', updated_at = now()
    where dp.zone_id = v_zone_id
      and dp.online_status = 'online'
      and not public.driver_subscription_allows_dispatch(dp.id);
  end if;

  perform public.admin_log_action(
    'save_subscription_group', 'driver_subscription_partner_settings', p_partner_id::text,
    jsonb_build_object('enabled', v_row.enabled, 'enforce_access', v_row.enforce_access)
  );

  return to_jsonb(v_row);
end;
$$;

create or replace function public.admin_subscription_partner_plan_upsert_v1(
  p_id bigint,
  p_partner_id uuid,
  p_code text,
  p_name text,
  p_amount numeric,
  p_days integer,
  p_active boolean,
  p_sort_order integer
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_zone_key text;
  v_currency text;
  v_code text;
  v_id bigint;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  select z.zone_key, z.currency_code into v_zone_key, v_currency
  from public.partner_organizations o
  join public.service_zones z on z.id = o.zone_id
  where o.id = p_partner_id;
  if v_zone_key is null then raise exception 'Sindicato no encontrado o sin zona'; end if;

  v_code := lower(trim(coalesce(p_code, '')));
  if v_code !~ '^[a-z][a-z0-9_]{1,39}$' then raise exception 'Código de plan inválido'; end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'Nombre requerido'; end if;
  if coalesce(p_amount, -1) < 0 then raise exception 'Precio inválido'; end if;
  if coalesce(p_days, 0) < 1 or coalesce(p_days, 0) > 3650 then raise exception 'Duración inválida'; end if;

  perform public.subscription_group_seed_partner_v1(p_partner_id);

  if p_id is null then
    insert into public.driver_subscription_plans
      (zone_key, currency_code, code, name, amount, days, benefits,
       active, sort_order, partner_id, updated_at)
    values
      (v_zone_key, v_currency, v_code, trim(p_name), p_amount, p_days, '[]'::jsonb,
       coalesce(p_active, true), coalesce(p_sort_order, 100), p_partner_id, now())
    returning id into v_id;
  else
    update public.driver_subscription_plans
    set code = v_code,
        name = trim(p_name),
        amount = p_amount,
        days = p_days,
        active = coalesce(p_active, true),
        sort_order = coalesce(p_sort_order, 100),
        updated_at = now()
    where id = p_id and partner_id = p_partner_id
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Plan no encontrado en este sindicato'; end if;

  perform public.admin_log_action(
    'save_subscription_plan', 'driver_subscription_plans', v_id::text,
    jsonb_build_object('partner_id', p_partner_id, 'amount', p_amount, 'days', p_days)
  );

  return v_id;
end;
$$;

create or replace function public.admin_subscription_partner_plan_delete_v1(
  p_id bigint,
  p_partner_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  begin
    delete from public.driver_subscription_plans
    where id = p_id and partner_id = p_partner_id;
  exception when foreign_key_violation then
    raise exception 'Este plan ya tiene pagos o suscripciones. Desactívalo en lugar de borrarlo.';
  end;

  if not found then raise exception 'Plan no encontrado en este sindicato'; end if;

  perform public.admin_log_action(
    'delete_subscription_plan', 'driver_subscription_plans', p_id::text,
    jsonb_build_object('partner_id', p_partner_id)
  );

  return jsonb_build_object('deleted', true, 'id', p_id);
end;
$$;

-- Permisos: helpers internos sin acceso directo; RPC solo para usuarios autenticados.
revoke all on function public.admin_subscription_groups_v1(text) from public, anon;
grant execute on function public.admin_subscription_groups_v1(text) to authenticated;

revoke all on function public.admin_subscription_partner_settings_set_v1(uuid, boolean, boolean) from public, anon;
grant execute on function public.admin_subscription_partner_settings_set_v1(uuid, boolean, boolean) to authenticated;

revoke all on function public.admin_subscription_partner_plan_upsert_v1(bigint, uuid, text, text, numeric, integer, boolean, integer) from public, anon;
grant execute on function public.admin_subscription_partner_plan_upsert_v1(bigint, uuid, text, text, numeric, integer, boolean, integer) to authenticated;

revoke all on function public.admin_subscription_partner_plan_delete_v1(bigint, uuid) from public, anon;
grant execute on function public.admin_subscription_partner_plan_delete_v1(bigint, uuid) to authenticated;
