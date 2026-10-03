-- Express Delivery / Market Phase 2 dispatch links and security hardening.

alter table public.delivery_requests
  add column if not exists marketplace_order_id uuid
    references public.marketplace_orders(id) on delete set null,
  add column if not exists customer_charge_amount numeric(12,2);

create unique index if not exists delivery_requests_marketplace_order_uidx
  on public.delivery_requests(marketplace_order_id)
  where marketplace_order_id is not null;

alter table public.delivery_requests
  drop constraint if exists delivery_requests_payment_method_check;

alter table public.delivery_requests
  add constraint delivery_requests_payment_method_check
  check (
    payment_method = any (
      array[
        'cash','pagorut','mercado_pago','santander',
        'mach','tenpo','card','wallet','transfer'
      ]::text[]
    )
  );

alter table public.marketplace_orders
  add column if not exists delivery_request_id uuid
    references public.delivery_requests(id) on delete set null,
  add column if not exists online_checkout_url text,
  add column if not exists provider_data jsonb not null default '{}'::jsonb;

alter table public.marketplace_zone_settings enable row level security;
alter table public.marketplace_plus_plans enable row level security;
alter table public.marketplace_plus_subscriptions enable row level security;
alter table public.marketplace_plus_payments enable row level security;
alter table public.marketplace_plus_merchant_benefits enable row level security;
alter table public.marketplace_merchant_users enable row level security;
alter table public.marketplace_orders enable row level security;
alter table public.marketplace_order_items enable row level security;
alter table public.marketplace_order_messages enable row level security;
alter table public.marketplace_order_financials enable row level security;

revoke all on table public.marketplace_zone_settings
  from public,anon,authenticated;
revoke all on table public.marketplace_plus_plans
  from public,anon,authenticated;
revoke all on table public.marketplace_plus_subscriptions
  from public,anon,authenticated;
revoke all on table public.marketplace_plus_payments
  from public,anon,authenticated;
revoke all on table public.marketplace_plus_merchant_benefits
  from public,anon,authenticated;
revoke all on table public.marketplace_merchant_users
  from public,anon,authenticated;
revoke all on table public.marketplace_orders
  from public,anon,authenticated;
revoke all on table public.marketplace_order_items
  from public,anon,authenticated;
revoke all on table public.marketplace_order_messages
  from public,anon,authenticated;
revoke all on table public.marketplace_order_financials
  from public,anon,authenticated;

create index if not exists marketplace_order_items_order_idx
  on public.marketplace_order_items(order_id);
create index if not exists marketplace_order_items_product_idx
  on public.marketplace_order_items(product_id);
create index if not exists marketplace_order_messages_sender_idx
  on public.marketplace_order_messages(sender_id);
create index if not exists marketplace_orders_zone_idx
  on public.marketplace_orders(zone_id);
create index if not exists marketplace_orders_delivery_request_idx
  on public.marketplace_orders(delivery_request_id);
create index if not exists marketplace_orders_transfer_reviewer_idx
  on public.marketplace_orders(transfer_reviewed_by);
create index if not exists marketplace_plus_payments_plan_idx
  on public.marketplace_plus_payments(plan_id);
create index if not exists marketplace_plus_subscriptions_plan_idx
  on public.marketplace_plus_subscriptions(plan_id);

revoke execute on function public.marketplace_compute_quote(
  uuid,uuid,jsonb,numeric,numeric,boolean,text
) from public,anon,authenticated;
grant execute on function public.marketplace_compute_quote(
  uuid,uuid,jsonb,numeric,numeric,boolean,text
) to service_role;

revoke execute on function public.marketplace_has_plus(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.marketplace_has_plus(uuid,uuid)
  to service_role;

revoke execute on function public.marketplace_activate_plus(
  uuid,uuid,text,text
) from public,anon,authenticated;
grant execute on function public.marketplace_activate_plus(
  uuid,uuid,text,text
) to service_role;

revoke execute on function public.marketplace_order_mark_paid(
  uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function public.marketplace_order_mark_paid(
  uuid,text,jsonb
) to service_role;

revoke execute on function public.marketplace_create_order(
  uuid,jsonb,numeric,numeric,boolean,text,text,numeric,numeric,text,text
) from public,anon;
grant execute on function public.marketplace_create_order(
  uuid,jsonb,numeric,numeric,boolean,text,text,numeric,numeric,text,text
) to authenticated;

revoke execute on function public.marketplace_quote_order(
  uuid,jsonb,numeric,numeric,boolean,text
) from public,anon;
grant execute on function public.marketplace_quote_order(
  uuid,jsonb,numeric,numeric,boolean,text
) to authenticated;

revoke execute on function public.marketplace_my_orders(integer)
  from public,anon;
grant execute on function public.marketplace_my_orders(integer)
  to authenticated;

revoke execute on function public.marketplace_order_detail(uuid)
  from public,anon;
grant execute on function public.marketplace_order_detail(uuid)
  to authenticated;

revoke execute on function public.marketplace_send_order_message(
  uuid,text,text,text
) from public,anon;
grant execute on function public.marketplace_send_order_message(
  uuid,text,text,text
) to authenticated;

revoke execute on function public.marketplace_review_transfer(
  uuid,boolean,text
) from public,anon;
grant execute on function public.marketplace_review_transfer(
  uuid,boolean,text
) to authenticated;

revoke execute on function public.marketplace_plus_state(text)
  from public,anon;
grant execute on function public.marketplace_plus_state(text)
  to authenticated;

revoke execute on function public.marketplace_order_set_status(uuid,text)
  from public,anon;
grant execute on function public.marketplace_order_set_status(uuid,text)
  to authenticated;

revoke execute on function public.marketplace_mark_driver_paid(uuid,text)
  from public,anon;
grant execute on function public.marketplace_mark_driver_paid(uuid,text)
  to authenticated;

revoke execute on function public.marketplace_my_merchant_access()
  from public,anon;
grant execute on function public.marketplace_my_merchant_access()
  to authenticated;

revoke execute on function public.marketplace_merchant_orders(uuid,integer)
  from public,anon;
grant execute on function public.marketplace_merchant_orders(uuid,integer)
  to authenticated;

revoke execute on function public.admin_marketplace_phase2_state()
  from public,anon;
grant execute on function public.admin_marketplace_phase2_state()
  to authenticated;

revoke execute on function public.admin_marketplace_set_plus_merchant_benefit(
  uuid,boolean,numeric,boolean,boolean,text
) from public,anon;
grant execute on function public.admin_marketplace_set_plus_merchant_benefit(
  uuid,boolean,numeric,boolean,boolean,text
) to authenticated;

revoke execute on function public.admin_marketplace_update_merchant_logistics(
  uuid,text,numeric,numeric,text
) from public,anon;
grant execute on function public.admin_marketplace_update_merchant_logistics(
  uuid,text,numeric,numeric,text
) to authenticated;

revoke execute on function public.admin_marketplace_assign_merchant_user(
  uuid,text,text
) from public,anon;
grant execute on function public.admin_marketplace_assign_merchant_user(
  uuid,text,text
) to authenticated;

revoke execute on function public.admin_marketplace_merchant_users(uuid)
  from public,anon;
grant execute on function public.admin_marketplace_merchant_users(uuid)
  to authenticated;

revoke execute on function public.admin_marketplace_set_merchant_user_active(
  uuid,uuid,boolean
) from public,anon;
grant execute on function public.admin_marketplace_set_merchant_user_active(
  uuid,uuid,boolean
) to authenticated;
