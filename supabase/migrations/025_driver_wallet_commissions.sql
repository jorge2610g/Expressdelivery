-- Driver wallet commissions and transparent settlement ledger.
-- Keeps current launch commission (configured in app_settings) and applies
-- whatever percentage the admin sets later without changing the app.

alter table public.payment_transactions
  add column if not exists commission_percent numeric not null default 0,
  add column if not exists commission_amount numeric not null default 0,
  add column if not exists driver_net_amount numeric;

alter table public.wallet_accounts
  drop constraint if exists wallet_accounts_balance_check;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_type_check
  check (type in ('topup','payment','refund','earning','adjustment','commission'));

create or replace function public.settle_wallet_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_balance numeric;
  v_commission_percent numeric := 0;
  v_commission numeric := 0;
  v_net numeric := 0;
begin
  select coalesce(s.commission_percent, 0)
    into v_commission_percent
  from public.app_settings s
  limit 1;

  v_commission := round(coalesce(new.amount, 0) * v_commission_percent / 100.0, 2);
  v_net := coalesce(new.amount, 0) - v_commission;

  update public.payment_transactions
  set commission_percent = v_commission_percent,
      commission_amount = v_commission,
      driver_net_amount = case when new.payee_id is null then null else v_net end
  where id = new.id;

  if new.payee_id is null then
    return new;
  end if;

  -- Cash is received directly by the driver. Only the Express commission is
  -- reflected in the driver wallet, allowing a negative balance to represent
  -- commission debt until future wallet/card earnings cover it.
  if new.method = 'cash' and new.status = 'paid' then
    insert into public.wallet_accounts(user_id)
    values (new.payee_id)
    on conflict (user_id) do nothing;

    if v_commission > 0 then
      update public.wallet_accounts
      set balance = balance - v_commission,
          updated_at = now()
      where user_id = new.payee_id;

      insert into public.wallet_transactions(
        user_id, amount, type, status, reference, trip_id, delivery_id
      )
      values (
        new.payee_id,
        -v_commission,
        'commission',
        'completed',
        'Comisión Express por servicio en efectivo',
        new.trip_id,
        new.delivery_id
      );
    end if;

    return new;
  end if;

  -- Wallet payments: charge the passenger the gross amount, then credit the
  -- driver gross earning and deduct commission as a separate visible movement.
  if new.method = 'wallet' and new.status = 'pending' then
    insert into public.wallet_accounts(user_id)
    values (new.payer_id)
    on conflict (user_id) do nothing;

    select balance
      into v_balance
    from public.wallet_accounts
    where user_id = new.payer_id
    for update;

    if coalesce(v_balance, 0) < new.amount then
      insert into public.notifications(user_id, title, body, type)
      values (
        new.payer_id,
        'Saldo insuficiente',
        'Tu pago con Billetera Express quedó pendiente porque no tienes saldo suficiente.',
        'wallet_insufficient'
      );
      return new;
    end if;

    update public.wallet_accounts
    set balance = balance - new.amount,
        updated_at = now()
    where user_id = new.payer_id;

    insert into public.wallet_transactions(
      user_id, amount, type, status, reference, trip_id, delivery_id
    )
    values (
      new.payer_id,
      -new.amount,
      'payment',
      'completed',
      'Pago de servicio Express',
      new.trip_id,
      new.delivery_id
    );

    insert into public.wallet_accounts(user_id)
    values (new.payee_id)
    on conflict (user_id) do nothing;

    update public.wallet_accounts
    set balance = balance + v_net,
        updated_at = now()
    where user_id = new.payee_id;

    insert into public.wallet_transactions(
      user_id, amount, type, status, reference, trip_id, delivery_id
    )
    values (
      new.payee_id,
      new.amount,
      'earning',
      'completed',
      'Ingreso bruto por servicio Express',
      new.trip_id,
      new.delivery_id
    );

    if v_commission > 0 then
      insert into public.wallet_transactions(
        user_id, amount, type, status, reference, trip_id, delivery_id
      )
      values (
        new.payee_id,
        -v_commission,
        'commission',
        'completed',
        'Comisión Express',
        new.trip_id,
        new.delivery_id
      );
    end if;

    update public.payment_transactions
    set status = 'paid',
        paid_at = now()
    where id = new.id;

    insert into public.notifications(user_id, title, body, type)
    values (
      new.payer_id,
      'Pago completado',
      'El pago con Billetera Express fue procesado correctamente.',
      'wallet_paid'
    );

    insert into public.notifications(user_id, title, body, type)
    values (
      new.payee_id,
      'Ganancia acreditada',
      'El importe neto del servicio fue acreditado en tu Billetera Express.',
      'wallet_earning'
    );
  end if;

  return new;
end;
$function$;
