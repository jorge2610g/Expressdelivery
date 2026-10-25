-- Express Delivery Global QR (VeriPagos). QR payments use the existing
-- global provider configuration and remain unavailable to Preview accounts.
begin;

alter table public.marketplace_orders
  add column if not exists payment_expires_at timestamptz;

alter table public.marketplace_orders
  drop constraint if exists marketplace_orders_payment_method_check;
alter table public.marketplace_orders
  add constraint marketplace_orders_payment_method_check
  check (payment_method in ('cash','transfer','mercado_pago','wallet','global_qr'));

alter table public.marketplace_orders
  drop constraint if exists marketplace_orders_status_check;
alter table public.marketplace_orders
  add constraint marketplace_orders_status_check
  check (status in (
    'pending','awaiting_payment','awaiting_merchant','awaiting_transfer',
    'payment_review','confirmed','preparing','ready','searching_driver',
    'driver_assigned','picked_up','delivering','delivered','cancelled'
  ));

alter table public.marketplace_orders
  drop constraint if exists marketplace_orders_payment_status_check;
alter table public.marketplace_orders
  add constraint marketplace_orders_payment_status_check
  check (payment_status in (
    'pending','qr_pending','awaiting_merchant','awaiting_receipt',
    'under_review','paid','rejected','refunded','cancelled','expired','disabled'
  ));

drop index if exists public.marketplace_one_pending_global_qr_per_customer;
create unique index marketplace_one_pending_global_qr_per_customer
  on public.marketplace_orders(customer_id,channel)
  where payment_method='global_qr' and payment_status='qr_pending';

create or replace function public.marketplace_prepare_global_qr_order()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_country text;
begin
  perform pg_advisory_xact_lock(hashtextextended(
    new.customer_id::text||':'||coalesce(new.channel,''), 190625));

  -- A timed-out QR is closed before testing the one-pending-order guard.
  update public.marketplace_orders
  set payment_status='expired',status='cancelled',updated_at=now()
  where customer_id=new.customer_id
    and channel=new.channel
    and payment_method='global_qr'
    and payment_status='qr_pending'
    and payment_expires_at is not null
    and payment_expires_at<=now();

  if exists (
    select 1 from public.marketplace_orders o
    where o.customer_id=new.customer_id
      and o.channel=new.channel
      and o.payment_method='global_qr'
      and o.payment_status='qr_pending'
  ) then
    raise exception 'Tienes un QR Global pendiente. Cancélalo o espera que venza antes de hacer otro pedido.';
  end if;

  select country_code into v_country
  from public.service_zones where id=new.zone_id;

  -- In Bolivia, production transfer orders now collect through Express QR.
  -- Preview retains its safe merchant-transfer simulation.
  if new.payment_method='transfer'
     and upper(coalesce(v_country,''))='BO'
     and new.channel='production' then
    new.payment_method:='global_qr';
    new.status:='awaiting_payment';
    new.payment_status:='qr_pending';
    new.collector:='express';
    new.payment_expires_at:=now()+interval '30 minutes';
  end if;

  return new;
end;
$$;

-- QR payloads are private to the customer who is paying. Merchant users and
-- delivery drivers can see order state but never receive a reusable QR.
create or replace function public.marketplace_order_detail(p_order_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_allowed boolean:=false;
  v_order_json jsonb;
begin
  if v_uid is null then raise exception 'No autorizado'; end if;
  select * into v_order from public.marketplace_orders where id=p_order_id;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if not exists(
    select 1 from public.account_runtime_bindings arb
    where arb.user_id=v_uid and arb.environment=v_order.channel
  ) then raise exception 'Pedido de otro entorno no autorizado'; end if;
  v_allowed:=v_order.customer_id=v_uid or v_order.assigned_driver_id=v_uid
    or public.is_admin() or exists(
      select 1 from public.marketplace_merchant_users mu
      where mu.merchant_id=v_order.merchant_id and mu.user_id=v_uid
        and mu.active=true
    );
  if not v_allowed then raise exception 'No autorizado'; end if;

  v_order_json:=to_jsonb(v_order)-'express_margin'-'driver_base_payout'
    -'driver_distance_payout'-'driver_priority_bonus'
    -'driver_pickup_payout'-'driver_dropoff_payout';
  if v_order.customer_id<>v_uid then
    v_order_json:=v_order_json-'online_checkout_url'-'provider_data'
      -'provider_reference';
  elsif v_order.payment_method='global_qr'
      and v_order.payment_status<>'qr_pending' then
    -- Once released/paid/expired, the old QR is no longer shown to the customer.
    v_order_json:=v_order_json-'online_checkout_url';
  end if;
  return jsonb_build_object(
    'order',v_order_json,
    'merchant',(select to_jsonb(m)-'transfer_instructions'
      from public.marketplace_merchants m
      where m.id=v_order.merchant_id),
    'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb)
      from public.marketplace_order_items i where i.order_id=p_order_id),
    'messages',(select coalesce(jsonb_agg(to_jsonb(msg) order by msg.created_at),
      '[]'::jsonb) from public.marketplace_order_messages msg
      where msg.order_id=p_order_id),
    'financials',(select case
      when public.is_admin() then to_jsonb(f)
      when exists(select 1 from public.marketplace_merchant_users mu
        where mu.merchant_id=v_order.merchant_id and mu.user_id=v_uid
          and mu.active) then jsonb_build_object(
            'customer_total',f.customer_total,
            'merchant_products_amount',f.merchant_products_amount,
            'driver_payout',f.driver_payout,'driver_tip',f.driver_tip,
            'merchant_owes_driver',f.merchant_owes_driver,
            'merchant_owes_express',f.merchant_owes_express,
            'driver_owes_merchant',f.driver_owes_merchant,
            'settlement_status',f.settlement_status)
      else '{}'::jsonb end
      from public.marketplace_order_financials f where f.order_id=p_order_id)
  );
end;
$$;

drop trigger if exists marketplace_orders_prepare_global_qr
  on public.marketplace_orders;
create trigger marketplace_orders_prepare_global_qr
before insert on public.marketplace_orders
for each row execute function public.marketplace_prepare_global_qr_order();

-- If a customer starts another checkout while a QR order is already pending,
-- route the app back to the existing order instead of surfacing a DB error or
-- generating another QR. Runtime channel keeps Preview and Production apart.
create or replace function public.marketplace_pending_global_qr_order()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text;
  v_order public.marketplace_orders%rowtype;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;
  select arb.environment into v_channel
  from public.account_runtime_bindings arb
  where arb.user_id=v_uid;
  if v_channel is null then
    return null;
  end if;
  select * into v_order
  from public.marketplace_orders o
  where o.customer_id=v_uid and o.channel=v_channel
    and o.payment_method='global_qr' and o.payment_status='qr_pending'
  order by o.created_at desc
  limit 1;
  if not found then return null; end if;
  return jsonb_build_object('id',v_order.id,'status',v_order.status,
    'payment_status',v_order.payment_status,
    'payment_expires_at',v_order.payment_expires_at);
end;
$$;

revoke all on function public.marketplace_pending_global_qr_order()
  from public,anon;
grant execute on function public.marketplace_pending_global_qr_order()
  to authenticated;

create or replace function public.service_marketplace_global_qr_claim(
  p_order_id uuid,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.marketplace_orders%rowtype;
  v_role text:=current_setting('request.jwt.claim.role',true);
begin
  if coalesce(v_role,'')<>'service_role' then
    raise exception 'Solo disponible para el servicio de pagos';
  end if;
  select * into v_order from public.marketplace_orders
  where id=p_order_id for update;
  if not found or v_order.payment_method<>'global_qr'
     or v_order.channel<>'production' then
    raise exception 'Pedido QR no válido';
  end if;
  if v_order.payment_status='paid' then
    return jsonb_build_object('state','paid','order',to_jsonb(v_order));
  end if;
  if v_order.payment_status<>'qr_pending' or v_order.status<>'awaiting_payment' then
    raise exception 'El pago QR ya no está pendiente';
  end if;
  if v_order.payment_expires_at<=now() then
    update public.marketplace_orders set payment_status='expired',status='cancelled',
      updated_at=now() where id=v_order.id returning * into v_order;
    return jsonb_build_object('state','expired','order',to_jsonb(v_order));
  end if;
  if v_order.provider_reference is not null
     and nullif(v_order.online_checkout_url,'') is not null then
    return jsonb_build_object('state','ready','order',to_jsonb(v_order));
  end if;
  if nullif(v_order.provider_data->>'global_qr_generation_started_at','') is not null then
    return jsonb_build_object('state','generating','order',to_jsonb(v_order));
  end if;
  update public.marketplace_orders
  set payment_expires_at=least(coalesce(payment_expires_at,p_expires_at),p_expires_at),
      provider_data=coalesce(provider_data,'{}'::jsonb)||jsonb_build_object(
        'global_qr_generation_started_at',now()),updated_at=now()
  where id=v_order.id returning * into v_order;
  return jsonb_build_object('state','claimed','order',to_jsonb(v_order));
end;
$$;

create or replace function public.service_marketplace_global_qr_save(
  p_order_id uuid,
  p_provider_reference text,
  p_qr_payload text,
  p_provider_data jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_order public.marketplace_orders%rowtype;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then
    raise exception 'Solo disponible para el servicio de pagos';
  end if;
  update public.marketplace_orders
  set provider_reference=p_provider_reference,
      online_checkout_url=p_qr_payload,
      provider_data=(coalesce(provider_data,'{}'::jsonb)-'global_qr_generation_started_at')
        ||coalesce(p_provider_data,'{}'::jsonb),
      updated_at=now()
  where id=p_order_id and payment_method='global_qr'
    and payment_status='qr_pending' and status='awaiting_payment'
    and payment_expires_at>now()
  returning * into v_order;
  if not found then raise exception 'El pedido QR ya no está pendiente'; end if;
  return to_jsonb(v_order);
end;
$$;

create or replace function public.service_marketplace_global_qr_finish(
  p_order_id uuid,
  p_status text,
  p_provider_reference text default null,
  p_provider_data jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_order public.marketplace_orders%rowtype;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then
    raise exception 'Solo disponible para el servicio de pagos';
  end if;
  if p_status not in ('paid','cancelled','expired','disabled') then
    raise exception 'Estado de QR no válido';
  end if;
  select * into v_order from public.marketplace_orders
  where id=p_order_id and payment_method='global_qr' for update;
  if not found then raise exception 'Pedido QR no encontrado'; end if;

  if v_order.payment_status='paid' then
    return jsonb_build_object('state','paid','order',to_jsonb(v_order));
  end if;
  if v_order.payment_status in ('cancelled','expired','disabled') and p_status<>'paid' then
    return jsonb_build_object('state',v_order.payment_status,'order',to_jsonb(v_order));
  end if;

  if p_status='paid' then
    update public.marketplace_orders
    set payment_status='paid',
        status=case when status='awaiting_payment' then 'pending' else status end,
        provider_reference=coalesce(p_provider_reference,provider_reference),
        provider_data=(coalesce(provider_data,'{}'::jsonb)-'global_qr_generation_started_at')
          ||coalesce(p_provider_data,'{}'::jsonb),updated_at=now()
    where id=v_order.id returning * into v_order;
  else
    update public.marketplace_orders
    set payment_status=p_status,status='cancelled',updated_at=now(),
        provider_data=(coalesce(provider_data,'{}'::jsonb)-'global_qr_generation_started_at')
          ||coalesce(p_provider_data,'{}'::jsonb)
    where id=v_order.id returning * into v_order;
  end if;
  return jsonb_build_object('state',v_order.payment_status,'order',to_jsonb(v_order));
end;
$$;

revoke all on function public.service_marketplace_global_qr_claim(uuid,timestamptz)
  from public,anon,authenticated;
revoke all on function public.service_marketplace_global_qr_save(uuid,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function public.service_marketplace_global_qr_finish(uuid,text,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.service_marketplace_global_qr_claim(uuid,timestamptz)
  to service_role;
grant execute on function public.service_marketplace_global_qr_save(uuid,text,text,jsonb)
  to service_role;
grant execute on function public.service_marketplace_global_qr_finish(uuid,text,text,jsonb)
  to service_role;

commit;
