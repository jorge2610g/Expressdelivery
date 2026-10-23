-- Finance and payment-provider configuration is accessed only by the
-- authorization-checked SECURITY DEFINER RPCs and trusted service_role code.
-- The client roles have no direct table grants and must not gain them later.
alter table public.zone_cancellation_fee_rules enable row level security;
alter table private.driver_subscription_provider_settings enable row level security;
alter table private.zone_payment_provider_settings enable row level security;

revoke all privileges on table public.zone_cancellation_fee_rules
  from anon, authenticated;
revoke all privileges on table private.driver_subscription_provider_settings
  from anon, authenticated;
revoke all privileges on table private.zone_payment_provider_settings
  from anon, authenticated;
