-- Make the trusted-server-only RLS intent explicit. service_role is the only
-- non-owner role permitted by policy; table grants remain independently
-- required and anon/authenticated still have none.
create policy zone_cancellation_fee_rules_service_role
  on public.zone_cancellation_fee_rules
  for all to service_role
  using (true) with check (true);

create policy driver_subscription_provider_settings_service_role
  on private.driver_subscription_provider_settings
  for all to service_role
  using (true) with check (true);

create policy zone_payment_provider_settings_service_role
  on private.zone_payment_provider_settings
  for all to service_role
  using (true) with check (true);
