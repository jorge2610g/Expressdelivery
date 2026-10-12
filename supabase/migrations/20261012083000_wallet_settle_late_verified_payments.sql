-- Honor provider-verified funds even if the displayed checkout has expired.
CREATE OR REPLACE FUNCTION public.service_finalize_verified_wallet_gateway(p_checkout_id uuid, p_provider_order_id text, p_verified_amount numeric, p_verified_currency text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item public.wallet_gateway_checkouts%rowtype;
  v_topup_id uuid;
begin
  if coalesce(auth.role(),'')<>'service_role' then
    raise exception 'Solo disponible para el servicio de pagos';
  end if;
  select * into v_item from public.wallet_gateway_checkouts
  where id=p_checkout_id for update;
  if not found then raise exception 'Operación no encontrada'; end if;
  if v_item.status='paid' then
    return jsonb_build_object('paid',true,'already_processed',true);
  end if;
  if v_item.status<>'pending' then
    raise exception 'Recarga no pendiente';
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
    raise exception 'Las cuentas de prueba no pueden recibir dinero real';
  end if;
  update public.wallet_gateway_checkouts
  set status='paid',paid_at=now() where id=v_item.id;

  insert into public.wallet_topup_requests(
    user_id,amount,currency,country_code,channel,method,
    provider_reference,status,resolved_at
  ) values(
    v_item.user_id,v_item.amount,v_item.currency_code,v_item.country_code,
    v_item.channel,v_item.provider,v_item.provider_order_id,'approved',now()
  ) returning id into v_topup_id;

  perform set_config('app.runtime_channel','production',true);
  insert into public.wallet_transactions(
    user_id,amount,type,status,reference,country_code,channel
  ) values(
    v_item.user_id,v_item.amount,'topup','completed',
    'Recarga pasarela:'||v_item.id::text,v_item.country_code,'production'
  );
  -- The wallet_transactions AFTER INSERT trigger updates the country wallet.
  -- The legacy wallet mirror is needed only in Production.
  perform public.mirror_legacy_wallet_delta(
    v_item.user_id,v_item.currency_code,v_item.amount
  );
  insert into public.notifications(user_id,title,body,type,metadata,channel)
  values(
    v_item.user_id,'Recarga confirmada',
    'Se acreditaron '||v_item.currency_code||' '||
       trim(to_char(v_item.amount,'FM999999990.00'))||' en tu billetera.',
    'wallet_topup',jsonb_build_object(
      'checkout_id',v_item.id,'provider',v_item.provider,
      'country_code',v_item.country_code,'channel','production'
    ),'production'
  );
  return jsonb_build_object(
    'paid',true,'already_processed',false,
    'topup_id',v_topup_id,'checkout_id',v_item.id
  );
end;
$function$
;

-- Preview bindings must never read or own real payment checkout rows,
-- including when an audit test group is disabled.
-- Runtime bindings have no direct authenticated SELECT grants.
-- Resolve them through an owner-only, self-scoped helper inside the RLS
-- policy; do not grant clients unrestricted access to the binding table.
create or replace function public.is_production_runtime_user(p_user_id uuid)
returns boolean
language sql stable security definer
set search_path=public
as $helper$
  select p_user_id is not null
     and (p_user_id=auth.uid() or auth.role()='service_role')
     and exists (
       select 1 from public.account_runtime_bindings b
       where b.user_id=p_user_id and b.environment='production'
     );
$helper$;
revoke all on function public.is_production_runtime_user(uuid)
  from public,anon;
grant execute on function public.is_production_runtime_user(uuid)
  to authenticated,service_role;

drop policy if exists wallet_gateway_owner_read
  on public.wallet_gateway_checkouts;
create policy wallet_gateway_owner_read
  on public.wallet_gateway_checkouts for select to authenticated
  using (
    user_id=auth.uid()
    and channel='production'
    and public.is_production_runtime_user(auth.uid())
    and not public.is_active_audit_user(auth.uid())
  );
