-- Reactiva la verificación por SMS solo para cuentas nuevas de Bolivia (+591).
-- Los interruptores siguen apagados hasta activarlos a propósito.
alter table public.app_settings drop constraint if exists express_sms_otp_decommissioned;

create or replace function public.phone_signup_verification_v1()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_uid uuid := auth.uid();
  u public.users%rowtype;
  s public.app_settings%rowtype;
  v_enabled boolean;
begin
  if v_uid is null then return jsonb_build_object('required', false); end if;
  select * into u from public.users where id = v_uid;
  select * into s from public.app_settings where id = true;
  v_enabled := case when u.active_mode = 'driver'
                    then coalesce(s.sms_verification_driver_enabled, false)
                    else coalesce(s.sms_verification_passenger_enabled, false) end;
  return jsonb_build_object(
    'required', v_enabled
      and s.sms_verification_rollout_at is not null
      and u.created_at >= s.sms_verification_rollout_at
      and u.phone_verified_at is null
      and coalesce(u.phone, '') like '+591%',
    'phone', u.phone,
    'country_code', 'BO');
end $$;
revoke all on function public.phone_signup_verification_v1() from public, anon;
grant execute on function public.phone_signup_verification_v1() to authenticated;
