-- Preview-only QR flow for marketplace orders. Preview QR payloads are
-- synthetic and are never sent to VeriPagos or treated as real bank payments.
begin;

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

  if new.payment_method='transfer'
     and upper(coalesce(v_country,''))='BO'
     and new.channel in ('production','preview') then
    new.payment_method:='global_qr';
    new.status:='awaiting_payment';
    new.payment_status:='qr_pending';
    new.collector:='express';
    new.payment_expires_at:=now()+interval '30 minutes';
    if new.channel='preview' then
      new.provider_data:=coalesce(new.provider_data,'{}'::jsonb)
        ||jsonb_build_object('preview_test_qr',true);
    end if;
  end if;

  return new;
end;
$$;

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
     or v_order.channel not in ('production','preview')
     or v_order.currency_code<>'BOB' then
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

commit;
