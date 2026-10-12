begin;
-- Transfer orders wait for explicit restaurant acceptance, before receipt or payment.
alter table public.marketplace_orders drop constraint marketplace_orders_status_check;
alter table public.marketplace_orders add constraint marketplace_orders_status_check
 check(status in ('pending','awaiting_merchant','awaiting_transfer','payment_review',
 'confirmed','preparing','ready','searching_driver','driver_assigned',
 'picked_up','delivering','delivered','cancelled'));
alter table public.marketplace_orders drop constraint marketplace_orders_payment_status_check;
alter table public.marketplace_orders add constraint marketplace_orders_payment_status_check
 check(payment_status in ('pending','awaiting_merchant','awaiting_receipt',
 'under_review','paid','rejected','refunded'));
commit;