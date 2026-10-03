-- Cover the foreign keys introduced by driver_zone_subscriptions.
create index if not exists driver_zone_subscriptions_plan_idx
  on public.driver_zone_subscriptions(plan_id);
create index if not exists driver_zone_subscriptions_last_payment_idx
  on public.driver_zone_subscriptions(last_payment_id);
