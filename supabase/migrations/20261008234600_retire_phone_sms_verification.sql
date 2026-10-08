-- Express migration 2026-10-08: permanently retire phone-number SMS OTP gates
-- in both production and QA without dropping users or their phone numbers.
-- Existing phone numbers may still be needed for safety/trusted contacts;
-- private voice remains the customer-to-driver communication channel.
update public.app_settings set
 sms_verification_passenger_enabled=false,
 sms_verification_driver_enabled=false,
 sms_provider_verified_at=null,
 sms_verification_rollout_at=null,
 updated_at=now()
where id=true;

update public.admin_environment_config
set payload=coalesce(payload,'{}'::jsonb)||
  jsonb_build_object(
   'sms_verification_passenger_enabled',false,
   'sms_verification_driver_enabled',false,
   'sms_provider_verified_at',null,
   'sms_verification_rollout_at',null)
where environment='preview' and module='app_settings'
 and record_key='default';

-- Old installed APKs must not be blocked by an unused phone-OTP gate.
create or replace function public.phone_verification_required_for_user(
 p_user_id uuid,p_role text,p_channel text default 'production'
) returns boolean
language sql stable security definer set search_path=public as $$
 select false
$$;

create or replace function public.phone_verification_enabled(
 p_role text,p_channel text default 'production'
) returns boolean
language sql stable security definer set search_path=public as $$
 select false
$$;

-- Remove the obsolete server-enforced check for ride acceptance/online state.
drop trigger if exists ride_requests_require_verified_phone
 on public.ride_requests;
drop trigger if exists driver_profiles_require_verified_phone_online
 on public.driver_profiles;
drop trigger if exists driver_offers_require_verified_phone
 on public.driver_offers;

-- Admin cannot inadvertently re-enable SMS for the production environment.
alter table public.app_settings
 drop constraint if exists express_sms_otp_decommissioned;
alter table public.app_settings
 add constraint express_sms_otp_decommissioned
 check(
   sms_verification_passenger_enabled is not true
   and sms_verification_driver_enabled is not true
 );

-- Keep previous migration history and historical audit data only.
-- The old phone-otp Edge function is removed separately after rollout of
-- the replacement APK, so older APKs cannot unexpectedly lock their users.
