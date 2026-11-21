-- Billeteras del panel de administración: resumen, lista, detalle con ganancias
-- por conductor y retiros. Solo lectura salvo la resolución de retiros.
-- Recargas y ajustes manuales reutilizan admin_topup_requests,
-- admin_resolve_wallet_topup y admin_finance_adjust_wallet_v1.

-- ---------------------------------------------------------------- retiros
create table if not exists public.wallet_withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  channel text not null default 'production'
    check (channel in ('preview','production')),
  country_code text not null,
  currency text not null,
  amount numeric not null check (amount > 0),
  method text,
  destination text,
  status text not null default 'pending'
    check (status in ('pending','paid','rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.users(id),
  resolution_note text,
  wallet_transaction_id uuid
);
create index if not exists wallet_withdrawal_requests_status_idx
  on public.wallet_withdrawal_requests (status, created_at desc);
create index if not exists wallet_withdrawal_requests_user_idx
  on public.wallet_withdrawal_requests (user_id, created_at desc);
alter table public.wallet_withdrawal_requests enable row level security;
revoke all on public.wallet_withdrawal_requests from anon, authenticated;

-- ------------------------------------------------------- alcance del admin
create or replace function public.admin_wallet_scope_v1(p_zone_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_role text; v_channel text; v_zone uuid; v_country text;
  v_currency text; v_tz text;
begin
  select a.access_role into v_role
  from public.admin_users a
  join public.users u on u.id = a.user_id
  where a.user_id = auth.uid() and a.active = true and u.account_status = 'active';
  if coalesce(v_role,'') not in ('super_admin','operator') then
    raise exception 'No autorizado para consultar billeteras';
  end if;
  if v_role = 'operator' then
    perform public.admin_operator_assert_module('payments');
  end if;
  v_channel := public.admin_current_runtime_environment();
  perform public.admin_assert_environment(v_channel);
  v_zone := public.admin_effective_zone_id(p_zone_id);
  select z.country_code, upper(z.currency_code), coalesce(z.timezone,'America/La_Paz')
    into v_country, v_currency, v_tz
  from public.service_zones z where z.id = v_zone;
  if v_country is null then raise exception 'Zona no encontrada'; end if;
  return jsonb_build_object('role',v_role,'channel',v_channel,'zone_id',v_zone,
    'country_code',v_country,'currency_code',v_currency,'timezone',v_tz);
end;
$$;
revoke all on function public.admin_wallet_scope_v1(uuid) from public, anon, authenticated;

-- -------------------------------------------------------------- resumen
create or replace function public.admin_wallets_overview_v1(p_zone_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  s jsonb; v_zone uuid; v_channel text; v_country text; v_currency text; v_tz text;
  v_day timestamptz; r jsonb;
begin
  s := public.admin_wallet_scope_v1(p_zone_id);
  v_zone := (s->>'zone_id')::uuid; v_channel := s->>'channel';
  v_country := s->>'country_code'; v_currency := s->>'currency_code'; v_tz := s->>'timezone';
  v_day := date_trunc('day', now() at time zone v_tz) at time zone v_tz;

  with scope as (
    select u.id, (dp.id is not null) as is_driver
    from public.users u
    left join public.driver_profiles dp on dp.id = u.id
    where u.account_status = 'active'
      and (dp.zone_id = v_zone or (dp.id is null and u.last_zone_id = v_zone))
      and (v_channel <> 'preview' or public.is_active_audit_user(u.id))
      and (v_channel <> 'production' or not public.is_active_audit_user(u.id))
  ), bal as (
    select sc.is_driver, w.balance
    from scope sc
    join public.wallet_country_accounts w
      on w.user_id = sc.id and w.country_code = v_country and w.channel = v_channel
  )
  select jsonb_build_object(
    'channel', v_channel, 'zone_id', v_zone, 'currency_code', v_currency,
    'total_balance', coalesce((select sum(balance) from bal),0),
    'driver_payable', coalesce((select sum(greatest(balance,0)) from bal where is_driver),0),
    'client_balance', coalesce((select sum(greatest(balance,0)) from bal where not is_driver),0),
    'debt_total', coalesce((select sum(-least(balance,0)) from bal),0),
    'pending_withdrawals', jsonb_build_object(
      'count', (select count(*) from public.wallet_withdrawal_requests q
                 where q.status='pending' and q.channel=v_channel and q.country_code=v_country
                   and q.user_id in (select id from scope)),
      'amount', coalesce((select sum(q.amount) from public.wallet_withdrawal_requests q
                 where q.status='pending' and q.channel=v_channel and q.country_code=v_country
                   and q.user_id in (select id from scope)),0)),
    'pending_topups', jsonb_build_object(
      'count', (select count(*) from public.wallet_topup_requests t
                 where t.status='pending' and t.channel=v_channel and t.country_code=v_country
                   and t.user_id in (select id from scope)),
      'amount', coalesce((select sum(t.amount) from public.wallet_topup_requests t
                 where t.status='pending' and t.channel=v_channel and t.country_code=v_country
                   and t.user_id in (select id from scope)),0)),
    'processed_today', (
      (select count(*) from public.wallet_topup_requests t
        where t.status in ('approved','rejected') and t.resolved_at >= v_day
          and t.channel=v_channel and t.country_code=v_country
          and t.user_id in (select id from scope))
      + (select count(*) from public.wallet_withdrawal_requests q
        where q.status in ('paid','rejected') and q.resolved_at >= v_day
          and q.channel=v_channel and q.country_code=v_country
          and q.user_id in (select id from scope)))
  ) into r;
  return r;
end;
$$;

-- ---------------------------------------------------------------- lista
create or replace function public.admin_wallets_list_v1(
  p_zone_id uuid,
  p_role text default 'all',
  p_filter text default 'all',
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  s jsonb; v_zone uuid; v_channel text; v_country text; v_currency text;
  v_role text := lower(trim(coalesce(p_role,'all')));
  v_filter text := lower(trim(coalesce(p_filter,'all')));
  v_search text := nullif(trim(coalesce(p_search,'')),'');
  v_limit integer := greatest(1, least(coalesce(p_limit,50), 200));
  v_offset integer := greatest(0, coalesce(p_offset,0));
  r jsonb;
begin
  if v_role not in ('all','driver','passenger') then raise exception 'Filtro de usuario inválido'; end if;
  if v_filter not in ('all','debt','balance') then raise exception 'Filtro de saldo inválido'; end if;
  s := public.admin_wallet_scope_v1(p_zone_id);
  v_zone := (s->>'zone_id')::uuid; v_channel := s->>'channel';
  v_country := s->>'country_code'; v_currency := s->>'currency_code';

  with base as (
    select u.id as user_id, u.full_name, u.phone, au.email,
      case when dp.id is null then 'passenger' else 'driver' end as role,
      coalesce(w.balance,0) as balance,
      coalesce(w.currency, v_currency) as currency_code,
      (select count(*) from public.wallet_transactions t
        where t.user_id=u.id and t.country_code=v_country and t.channel=v_channel) as tx_count,
      (select count(*) from public.wallet_withdrawal_requests q
        where q.user_id=u.id and q.status='pending' and q.channel=v_channel) as pending_withdrawals,
      greatest(w.updated_at,
        (select max(t.created_at) from public.wallet_transactions t
          where t.user_id=u.id and t.country_code=v_country and t.channel=v_channel)) as last_activity
    from public.users u
    left join auth.users au on au.id = u.id
    left join public.driver_profiles dp on dp.id = u.id
    left join public.wallet_country_accounts w
      on w.user_id = u.id and w.country_code = v_country and w.channel = v_channel
    where u.account_status = 'active'
      and (dp.zone_id = v_zone or (dp.id is null and u.last_zone_id = v_zone))
      and (v_channel <> 'preview' or public.is_active_audit_user(u.id))
      and (v_channel <> 'production' or not public.is_active_audit_user(u.id))
      and (v_role = 'all' or (v_role = 'driver' and dp.id is not null)
           or (v_role = 'passenger' and dp.id is null))
      and (v_search is null or u.full_name ilike '%'||v_search||'%'
           or coalesce(u.phone,'') ilike '%'||v_search||'%'
           or coalesce(au.email,'') ilike '%'||v_search||'%')
  ), filtered as (
    select * from base
    where v_filter = 'all'
       or (v_filter = 'debt' and balance < 0)
       or (v_filter = 'balance' and balance > 0)
  )
  select jsonb_build_object(
    'currency_code', v_currency,
    'total', (select count(*) from filtered),
    'rows', coalesce((
      select jsonb_agg(to_jsonb(x)) from (
        select * from filtered
        order by last_activity desc nulls last, full_name
        limit v_limit offset v_offset
      ) x), '[]'::jsonb)
  ) into r;
  return r;
end;
$$;

-- -------------------------------------------------------------- detalle
create or replace function public.admin_wallet_detail_v1(p_zone_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  s jsonb; v_zone uuid; v_channel text; v_country text; v_currency text; v_tz text;
  v_day timestamptz; v_week timestamptz; v_month timestamptz;
  v_is_driver boolean; v_user record; v_acc record; r jsonb;
begin
  s := public.admin_wallet_scope_v1(p_zone_id);
  v_zone := (s->>'zone_id')::uuid; v_channel := s->>'channel';
  v_country := s->>'country_code'; v_currency := s->>'currency_code'; v_tz := s->>'timezone';
  v_day := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  v_week := v_day - interval '6 days';
  v_month := date_trunc('month', now() at time zone v_tz) at time zone v_tz;

  select u.id, u.full_name, u.phone, au.email, u.avatar_url, u.last_zone_id,
         dp.id as driver_id, dp.zone_id as driver_zone, dp.online_status, dp.completed_trips, dp.rating
    into v_user
  from public.users u
  left join auth.users au on au.id = u.id
  left join public.driver_profiles dp on dp.id = u.id
  where u.id = p_user_id and u.account_status = 'active';
  if not found then raise exception 'Usuario no encontrado o inactivo'; end if;
  v_is_driver := v_user.driver_id is not null;
  if coalesce(case when v_is_driver then v_user.driver_zone else v_user.last_zone_id end,
              '00000000-0000-0000-0000-000000000000'::uuid) is distinct from v_zone then
    raise exception 'El usuario no pertenece a la zona seleccionada';
  end if;
  if (v_channel='preview' and not public.is_active_audit_user(p_user_id))
     or (v_channel='production' and public.is_active_audit_user(p_user_id)) then
    raise exception 'La cuenta pertenece a otro entorno';
  end if;

  select w.balance, w.currency, w.created_at, w.updated_at into v_acc
  from public.wallet_country_accounts w
  where w.user_id = p_user_id and w.country_code = v_country and w.channel = v_channel;

  select jsonb_build_object(
    'user', jsonb_build_object('id',v_user.id,'full_name',v_user.full_name,'phone',v_user.phone,
      'email',v_user.email,'avatar_url',v_user.avatar_url,
      'role',case when v_is_driver then 'driver' else 'passenger' end,
      'online_status',v_user.online_status,'rating',v_user.rating,
      'completed_trips',v_user.completed_trips),
    'currency_code', coalesce(v_acc.currency, v_currency),
    'balance', coalesce(v_acc.balance,0),
    'created_at', v_acc.created_at,
    'last_activity', greatest(v_acc.updated_at,
      (select max(t.created_at) from public.wallet_transactions t
        where t.user_id=p_user_id and t.country_code=v_country and t.channel=v_channel)),
    'tx_count', (select count(*) from public.wallet_transactions t
        where t.user_id=p_user_id and t.country_code=v_country and t.channel=v_channel),
    'pending_withdrawals', jsonb_build_object(
      'count',(select count(*) from public.wallet_withdrawal_requests q
        where q.user_id=p_user_id and q.status='pending' and q.channel=v_channel),
      'amount',coalesce((select sum(q.amount) from public.wallet_withdrawal_requests q
        where q.user_id=p_user_id and q.status='pending' and q.channel=v_channel),0)),
    'settle', jsonb_build_object(
      'net', coalesce(v_acc.balance,0),
      'direction', case when coalesce(v_acc.balance,0) > 0 then 'express_owes_user'
                        when coalesce(v_acc.balance,0) < 0 then 'user_owes_express'
                        else 'settled' end),
    'earnings', case when not v_is_driver then null else jsonb_build_object(
      'today', public.admin_wallet_earnings_v1(p_user_id, v_channel, v_day),
      'week', public.admin_wallet_earnings_v1(p_user_id, v_channel, v_week),
      'month', public.admin_wallet_earnings_v1(p_user_id, v_channel, v_month)) end,
    'recent_transactions', coalesce((
      select jsonb_agg(to_jsonb(x)) from (
        select t.id, t.type, t.amount, t.status, t.reference, t.created_at
        from public.wallet_transactions t
        where t.user_id=p_user_id and t.country_code=v_country and t.channel=v_channel
        order by t.created_at desc limit 20) x), '[]'::jsonb)
  ) into r;
  return r;
end;
$$;

-- Ganancias de un conductor desde una fecha: viajes y entregas completados.
create or replace function public.admin_wallet_earnings_v1(
  p_driver_id uuid, p_channel text, p_since timestamptz
)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select jsonb_build_object(
    'trips', (select count(*) from public.trips t
      where t.driver_id=p_driver_id and t.status='completed'
        and t.channel=p_channel and t.completed_at >= p_since),
    'trips_total', coalesce((select sum(t.final_fare) from public.trips t
      where t.driver_id=p_driver_id and t.status='completed'
        and t.channel=p_channel and t.completed_at >= p_since),0),
    'deliveries', (select count(*) from public.delivery_requests d
      where d.courier_id=p_driver_id and d.status='delivered'
        and d.channel=p_channel and d.completed_at >= p_since),
    'deliveries_total', coalesce((select sum(d.proposed_fare) from public.delivery_requests d
      where d.courier_id=p_driver_id and d.status='delivered'
        and d.channel=p_channel and d.completed_at >= p_since),0));
$$;
revoke all on function public.admin_wallet_earnings_v1(uuid,text,timestamptz) from public, anon, authenticated;

-- --------------------------------------------------------------- retiros
create or replace function public.admin_wallet_withdrawals_v1(
  p_zone_id uuid, p_status text default 'pending', p_search text default null, p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  s jsonb; v_zone uuid; v_channel text; v_country text; v_currency text;
  v_status text := lower(trim(coalesce(p_status,'pending')));
  v_search text := nullif(trim(coalesce(p_search,'')),'');
  r jsonb;
begin
  if v_status not in ('pending','paid','rejected','all') then raise exception 'Estado inválido'; end if;
  s := public.admin_wallet_scope_v1(p_zone_id);
  v_zone := (s->>'zone_id')::uuid; v_channel := s->>'channel';
  v_country := s->>'country_code'; v_currency := s->>'currency_code';
  select jsonb_build_object('currency_code', v_currency, 'rows', coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb))
    into r
  from (
    select q.id, q.user_id, u.full_name, u.phone, au.email, q.amount, q.currency,
           q.method, q.destination, q.status, q.created_at, q.resolved_at, q.resolution_note,
           coalesce(w.balance,0) as balance
    from public.wallet_withdrawal_requests q
    join public.users u on u.id = q.user_id
    left join auth.users au on au.id = u.id
    left join public.driver_profiles dp on dp.id = u.id
    left join public.wallet_country_accounts w
      on w.user_id = q.user_id and w.country_code = q.country_code and w.channel = q.channel
    where q.channel = v_channel and q.country_code = v_country
      and (dp.zone_id = v_zone or (dp.id is null and u.last_zone_id = v_zone))
      and (v_status = 'all' or q.status = v_status)
      and (v_search is null or u.full_name ilike '%'||v_search||'%'
           or coalesce(u.phone,'') ilike '%'||v_search||'%'
           or coalesce(au.email,'') ilike '%'||v_search||'%')
    order by case when q.status='pending' then 0 else 1 end, q.created_at desc
    limit greatest(1, least(coalesce(p_limit,100),300))
  ) x;
  return r;
end;
$$;

create or replace function public.admin_resolve_wallet_withdrawal_v1(
  p_zone_id uuid, p_request_id uuid, p_action text, p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  s jsonb; v_channel text; v_country text; v_zone uuid;
  v_req public.wallet_withdrawal_requests%rowtype;
  v_balance numeric; v_tx uuid; v_note text := nullif(trim(coalesce(p_note,'')),'');
begin
  if p_action not in ('pay','reject') then raise exception 'Acción inválida'; end if;
  s := public.admin_wallet_scope_v1(p_zone_id);
  v_zone := (s->>'zone_id')::uuid; v_channel := s->>'channel'; v_country := s->>'country_code';
  if p_action = 'reject' and v_note is null then
    raise exception 'Indica el motivo del rechazo';
  end if;

  select * into v_req from public.wallet_withdrawal_requests where id = p_request_id for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  if v_req.channel <> v_channel or v_req.country_code <> v_country then
    raise exception 'La solicitud pertenece a otro entorno o país';
  end if;
  if not exists (
    select 1 from public.users u
    left join public.driver_profiles dp on dp.id = u.id
    where u.id = v_req.user_id
      and (dp.zone_id = v_zone or (dp.id is null and u.last_zone_id = v_zone))
  ) then
    raise exception 'El usuario no pertenece a la zona seleccionada';
  end if;
  if v_req.status <> 'pending' then raise exception 'La solicitud ya fue resuelta'; end if;

  if p_action = 'pay' then
    perform pg_advisory_xact_lock(hashtextextended('wallet-withdrawal:'||v_req.user_id::text,0));
    select coalesce(w.balance,0) into v_balance
    from public.wallet_country_accounts w
    where w.user_id = v_req.user_id and w.country_code = v_country and w.channel = v_channel
    for update;
    if coalesce(v_balance,0) < v_req.amount then
      raise exception 'El saldo (%) no alcanza para pagar el retiro (%)',
        coalesce(v_balance,0), v_req.amount;
    end if;
    insert into public.wallet_transactions(user_id, amount, type, status, reference, country_code, channel)
    values (v_req.user_id, -v_req.amount, 'adjustment', 'completed',
            'Retiro pagado'||coalesce(': '||v_note,''), v_country, v_channel)
    returning id into v_tx;
    if v_channel = 'production' then
      perform public.mirror_legacy_wallet_delta(v_req.user_id, v_req.currency, -v_req.amount);
    end if;
  end if;

  update public.wallet_withdrawal_requests
     set status = case when p_action='pay' then 'paid' else 'rejected' end,
         resolved_at = now(), resolved_by = auth.uid(),
         resolution_note = v_note, wallet_transaction_id = v_tx
   where id = p_request_id;

  perform set_config('app.runtime_channel', v_channel, true);
  insert into public.notifications(user_id, title, body, type, metadata)
  values (
    v_req.user_id,
    case when p_action='pay' then 'Retiro pagado' else 'Retiro rechazado' end,
    case when p_action='pay'
      then 'Se pagó tu retiro de '||v_req.currency||' '||trim(to_char(v_req.amount,'FM999999990.00'))||'.'
      else 'Tu solicitud de retiro no fue aprobada. Contacta a soporte si necesitas ayuda.' end,
    'wallet_withdrawal',
    jsonb_build_object('country_code',v_country,'currency',v_req.currency,'channel',v_channel));

  perform public.admin_log_action(
    case when p_action='pay' then 'wallet_withdrawal_paid' else 'wallet_withdrawal_rejected' end,
    'wallet_withdrawal', p_request_id::text,
    jsonb_build_object('user_id',v_req.user_id,'amount',v_req.amount,'currency',v_req.currency,
      'zone_id',v_zone,'note',v_note));
  return jsonb_build_object('ok', true, 'status', case when p_action='pay' then 'paid' else 'rejected' end);
end;
$$;

-- El conductor o pasajero pide un retiro de su propio saldo.
create or replace function public.request_wallet_withdrawal_v1(
  p_amount numeric, p_method text default null, p_destination text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid(); v_country text; v_currency text; v_channel text;
  v_balance numeric; v_id uuid;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000000 then raise exception 'Importe inválido'; end if;
  v_channel := coalesce((select b.environment from public.account_runtime_bindings b where b.user_id=v_uid),'production');
  select z.country_code, upper(z.currency_code) into v_country, v_currency
  from public.users u
  left join public.driver_profiles dp on dp.id = u.id
  join public.service_zones z on z.id = coalesce(dp.zone_id, u.last_zone_id)
  where u.id = v_uid;
  if v_country is null then raise exception 'No se pudo determinar tu país'; end if;
  select coalesce(w.balance,0) into v_balance from public.wallet_country_accounts w
   where w.user_id=v_uid and w.country_code=v_country and w.channel=v_channel;
  if coalesce(v_balance,0) < p_amount then raise exception 'Tu saldo no alcanza para este retiro'; end if;
  if exists (select 1 from public.wallet_withdrawal_requests q
              where q.user_id=v_uid and q.status='pending' and q.channel=v_channel) then
    raise exception 'Ya tienes un retiro pendiente';
  end if;
  insert into public.wallet_withdrawal_requests(user_id, channel, country_code, currency, amount, method, destination)
  values (v_uid, v_channel, v_country, v_currency, p_amount,
          left(nullif(trim(coalesce(p_method,'')),''),60),
          left(nullif(trim(coalesce(p_destination,'')),''),300))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- --------------------------------------------------------------- permisos
do $$
declare f text;
begin
  foreach f in array array[
    'admin_wallets_overview_v1(uuid)',
    'admin_wallets_list_v1(uuid,text,text,text,integer,integer)',
    'admin_wallet_detail_v1(uuid,uuid)',
    'admin_wallet_withdrawals_v1(uuid,text,text,integer)',
    'admin_resolve_wallet_withdrawal_v1(uuid,uuid,text,text)',
    'request_wallet_withdrawal_v1(numeric,text,text)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
