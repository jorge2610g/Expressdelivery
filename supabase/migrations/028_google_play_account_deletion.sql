-- Google Play account deletion compliance.
-- Applied to production on 2026-10-01 and stored here for reproducibility.

create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_deleted_at timestamptz := clock_timestamp();
begin
  if v_uid is null then
    raise exception 'Sesión no disponible.'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.admin_users
    where user_id = v_uid
  ) then
    raise exception 'Las cuentas administrativas deben solicitar eliminación a soporte.'
      using errcode = '42501';
  end if;

  delete from public.app_error_logs
  where user_id = v_uid;

  delete from public.app_flow_events
  where actor_user_id = v_uid
     or passenger_id = v_uid
     or driver_id = v_uid;

  delete from public.native_push_tokens
  where user_id = v_uid;

  delete from public.trip_status_history
  where changed_by = v_uid;

  delete from public.delivery_status_history
  where changed_by = v_uid;

  update public.wallet_topup_requests
  set resolved_by = null
  where resolved_by = v_uid;

  delete from public.payment_transactions
  where payer_id = v_uid;

  update public.payment_transactions
  set payee_id = null
  where payee_id = v_uid;

  delete from public.driver_offers
  where driver_id = v_uid;

  delete from public.trips
  where passenger_id = v_uid
     or driver_id = v_uid;

  delete from public.ride_requests
  where passenger_id = v_uid;

  delete from public.delivery_requests
  where customer_id = v_uid;

  delete from public.build_jobs
  where created_by = v_uid;

  delete from public.users
  where id = v_uid;

  delete from auth.users
  where id = v_uid;

  return jsonb_build_object(
    'deleted', true,
    'user_id', v_uid,
    'deleted_at', v_deleted_at
  );
end;
$$;

revoke all on function public.delete_my_account() from public;
revoke all on function public.delete_my_account() from anon;
grant execute on function public.delete_my_account() to authenticated;
