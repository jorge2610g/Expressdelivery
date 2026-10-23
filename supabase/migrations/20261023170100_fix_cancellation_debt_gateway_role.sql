-- Fix real cancellation-debt payments being rejected during final settlement.
-- The Edge Function authenticates the customer, uses its server-only client
-- for this RPC, and EXECUTE is granted only to service_role below. The extra
-- request.jwt.claim.role comparison was incompatible with the configured
-- server API key and rejected valid settlements after the provider had
-- already confirmed payment.
-- Keep the channel, audit-user, production-binding, provider reference,
-- amount, currency, and unpaid-debt checks inside this SECURITY DEFINER RPC.

create or replace function public.service_finalize_verified_cancellation_debt_gateway(
  p_checkout_id uuid,
  p_provider_order_id text,
  p_verified_amount numeric,
  p_verified_currency text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_item public.wallet_gateway_checkouts%rowtype;
  v_total numeric;
  v_count integer;
begin
  select * into v_item
  from public.wallet_gateway_checkouts
  where id=p_checkout_id
  for update;

  if not found or v_item.purpose<>'cancellation_debt' then
    raise exception 'Pago de deuda no encontrado';
  end if;
  if v_item.status='paid' then
    return jsonb_build_object('paid',true,'already_processed',true);
  end if;
  if v_item.status<>'pending' then
    raise exception 'Pago no pendiente';
  end if;
  if v_item.provider_order_id is null
     or v_item.provider_order_id<>p_provider_order_id
     or v_item.amount<>round(p_verified_amount,2)
     or v_item.currency_code<>upper(trim(p_verified_currency)) then
    raise exception 'No coinciden referencia, monto o moneda verificados';
  end if;
  if v_item.channel<>'production'
     or public.is_active_audit_user(v_item.user_id)
     or not exists (
       select 1 from public.account_runtime_bindings b
       where b.user_id=v_item.user_id and b.environment='production'
     ) then
    raise exception 'Las cuentas Preview no pueden realizar pagos reales';
  end if;

  perform 1
  from public.cancellation_fee_debts
  where id=any(v_item.cancellation_debt_ids)
    and user_id=v_item.user_id
    and channel=v_item.channel
    and country_code=v_item.country_code
    and paid_at is null
  for update;

  select coalesce(sum(amount),0),count(*)
  into v_total,v_count
  from public.cancellation_fee_debts
  where id=any(v_item.cancellation_debt_ids)
    and user_id=v_item.user_id
    and channel=v_item.channel
    and country_code=v_item.country_code
    and paid_at is null;
  if v_count=0 or v_total<>v_item.amount then
    raise exception 'El monto de la deuda cambió; genera un nuevo QR';
  end if;

  update public.cancellation_fee_debts
  set paid_at=now(),payment_checkout_id=v_item.id
  where id=any(v_item.cancellation_debt_ids)
    and user_id=v_item.user_id
    and channel=v_item.channel
    and country_code=v_item.country_code
    and paid_at is null;
  update public.wallet_gateway_checkouts
  set status='paid',paid_at=now()
  where id=v_item.id;

  insert into public.notifications(user_id,title,body,type,metadata,channel)
  values(
    v_item.user_id,
    'Deuda de cancelación pagada',
    'Se confirmó el pago de tu deuda por cancelación.',
    'cancellation_fee_paid',
    jsonb_build_object(
      'checkout_id',v_item.id,
      'country_code',v_item.country_code,
      'channel','production'
    ),
    'production'
  );

  return jsonb_build_object(
    'paid',true,
    'already_processed',false,
    'checkout_id',v_item.id,
    'amount',v_item.amount
  );
end;
$$;

revoke all on function public.service_finalize_verified_cancellation_debt_gateway(
  uuid,text,numeric,text
) from public,anon,authenticated;
grant execute on function public.service_finalize_verified_cancellation_debt_gateway(
  uuid,text,numeric,text
) to service_role;
