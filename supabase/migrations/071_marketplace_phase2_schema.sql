-- Express Delivery / Market Phase 2 schema.
-- Preview-only until the release gate approves Production.

create table if not exists public.marketplace_zone_settings (
  zone_id uuid primary key references public.service_zones(id) on delete cascade,
  preview_enabled boolean not null default true,
  production_enabled boolean not null default false,
  customer_base_fee numeric(12,2) not null default 0,
  customer_per_km numeric(12,2) not null default 0,
  customer_min_fee numeric(12,2) not null default 0,
  driver_base_payout numeric(12,2) not null default 0,
  driver_per_km numeric(12,2) not null default 0,
  driver_min_payout numeric(12,2) not null default 0,
  priority_enabled boolean not null default true,
  priority_customer_fee numeric(12,2) not null default 0,
  priority_driver_bonus numeric(12,2) not null default 0,
  tips_enabled boolean not null default true,
  cash_enabled boolean not null default true,
  transfer_enabled boolean not null default false,
  online_enabled boolean not null default true,
  plus_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

insert into public.marketplace_zone_settings(
  zone_id,preview_enabled,production_enabled,
  customer_base_fee,customer_per_km,customer_min_fee,
  driver_base_payout,driver_per_km,driver_min_payout,
  priority_customer_fee,priority_driver_bonus,
  transfer_enabled,plus_enabled
)
select
  z.id,true,false,
  case when z.currency_code='CLP' then 2000 else 10 end,
  0,
  case when z.currency_code='CLP' then 2000 else 10 end,
  case when z.currency_code='CLP' then 1500 else 7.5 end,
  0,
  case when z.currency_code='CLP' then 1500 else 7.5 end,
  case when z.currency_code='CLP' then 500 else 2 end,
  case when z.currency_code='CLP' then 300 else 1 end,
  true,true
from public.service_zones z
where z.zone_key in ('iquique','trinidad')
on conflict(zone_id) do nothing;

alter table public.marketplace_merchants
  add column if not exists address text,
  add column if not exists latitude numeric,
  add column if not exists longitude numeric,
  add column if not exists transfer_instructions text;

create table if not exists public.marketplace_plus_plans (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  name text not null default 'Express Plus',
  monthly_price numeric(12,2) not null default 0,
  currency_code text not null,
  active boolean not null default false,
  preview_visible boolean not null default true,
  production_visible boolean not null default false,
  free_delivery boolean not null default true,
  included_priority_deliveries integer not null default 0,
  default_discount_percent numeric(6,2) not null default 0,
  description text,
  updated_at timestamptz not null default now(),
  unique(zone_id,name)
);

insert into public.marketplace_plus_plans(
  zone_id,name,monthly_price,currency_code,active,
  preview_visible,production_visible,free_delivery,
  included_priority_deliveries,default_discount_percent,description
)
select
  z.id,'Express Plus',0,z.currency_code,false,true,false,true,0,0,
  'Suscripción mensual con beneficios configurables por zona y comercio.'
from public.service_zones z
where z.zone_key in ('iquique','trinidad')
on conflict(zone_id,name) do nothing;

create table if not exists public.marketplace_plus_subscriptions (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.marketplace_plus_plans(id),
  status text not null default 'active'
    check(status in ('pending','active','cancelled','expired')),
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  auto_renew boolean not null default false,
  provider text,
  provider_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_plus_subscriptions_customer_idx
  on public.marketplace_plus_subscriptions(customer_id,status,expires_at desc);

create table if not exists public.marketplace_plus_payments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id),
  plan_id uuid not null references public.marketplace_plus_plans(id),
  amount numeric(12,2) not null,
  currency_code text not null,
  provider text not null default 'mercado_pago',
  status text not null default 'pending'
    check(status in ('pending','approved','rejected','cancelled','expired')),
  provider_reference text,
  checkout_url text,
  provider_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  paid_at timestamptz
);

create index if not exists marketplace_plus_payments_customer_idx
  on public.marketplace_plus_payments(customer_id,created_at desc);

create table if not exists public.marketplace_plus_merchant_benefits (
  merchant_id uuid primary key references public.marketplace_merchants(id) on delete cascade,
  enabled boolean not null default false,
  discount_percent numeric(6,2) not null default 0,
  free_delivery boolean not null default false,
  exclusive_promo boolean not null default false,
  funded_by text not null default 'express'
    check(funded_by in ('express','merchant')),
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_merchant_users (
  merchant_id uuid not null references public.marketplace_merchants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'manager',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(merchant_id,user_id)
);

create table if not exists public.marketplace_orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id),
  merchant_id uuid not null references public.marketplace_merchants(id),
  zone_id uuid not null references public.service_zones(id),
  assigned_driver_id uuid references auth.users(id),
  channel text not null default 'production'
    check(channel in ('preview','production')),
  status text not null default 'pending'
    check(status in (
      'pending','awaiting_transfer','payment_review','confirmed','preparing',
      'ready','searching_driver','driver_assigned','picked_up','delivering',
      'delivered','cancelled'
    )),
  payment_method text not null
    check(payment_method in ('cash','transfer','mercado_pago','wallet')),
  payment_status text not null default 'pending'
    check(payment_status in (
      'pending','awaiting_receipt','under_review','paid','rejected','refunded'
    )),
  currency_code text not null,
  subtotal numeric(12,2) not null default 0,
  product_discount numeric(12,2) not null default 0,
  customer_delivery_fee numeric(12,2) not null default 0,
  priority_fee numeric(12,2) not null default 0,
  tip_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  driver_base_payout numeric(12,2) not null default 0,
  driver_distance_payout numeric(12,2) not null default 0,
  driver_priority_bonus numeric(12,2) not null default 0,
  driver_payout numeric(12,2) not null default 0,
  express_margin numeric(12,2) not null default 0,
  merchant_products_amount numeric(12,2) not null default 0,
  collector text not null default 'driver'
    check(collector in ('driver','merchant','express')),
  distance_km numeric(10,3) not null default 0,
  is_priority boolean not null default false,
  plus_subscription_applied boolean not null default false,
  plus_free_delivery_applied boolean not null default false,
  plus_discount_percent numeric(6,2) not null default 0,
  pickup_address text,
  pickup_latitude numeric,
  pickup_longitude numeric,
  dropoff_address text not null,
  dropoff_latitude numeric,
  dropoff_longitude numeric,
  customer_note text,
  transfer_receipt_url text,
  transfer_submitted_at timestamptz,
  transfer_reviewed_at timestamptz,
  transfer_reviewed_by uuid references auth.users(id),
  provider_reference text,
  online_checkout_url text,
  provider_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists marketplace_orders_customer_idx
  on public.marketplace_orders(customer_id,created_at desc);
create index if not exists marketplace_orders_merchant_idx
  on public.marketplace_orders(merchant_id,status,created_at desc);
create index if not exists marketplace_orders_driver_idx
  on public.marketplace_orders(assigned_driver_id,status,created_at desc);

create table if not exists public.marketplace_order_items (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.marketplace_orders(id) on delete cascade,
  product_id uuid references public.marketplace_products(id),
  product_name text not null,
  quantity integer not null check(quantity>0),
  unit_price numeric(12,2) not null,
  line_total numeric(12,2) not null,
  created_at timestamptz not null default now()
);

create table if not exists public.marketplace_order_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.marketplace_orders(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  sender_role text not null
    check(sender_role in ('customer','merchant','admin','system')),
  message_type text not null default 'text'
    check(message_type in ('text','bank_details','receipt','system')),
  body text,
  attachment_url text,
  created_at timestamptz not null default now(),
  check(coalesce(length(trim(body)),0)>0 or attachment_url is not null)
);

create index if not exists marketplace_order_messages_order_idx
  on public.marketplace_order_messages(order_id,created_at);

create table if not exists public.marketplace_order_financials (
  order_id uuid primary key references public.marketplace_orders(id) on delete cascade,
  customer_total numeric(12,2) not null default 0,
  merchant_products_amount numeric(12,2) not null default 0,
  driver_payout numeric(12,2) not null default 0,
  driver_tip numeric(12,2) not null default 0,
  express_margin numeric(12,2) not null default 0,
  collector text not null check(collector in ('driver','merchant','express')),
  merchant_owes_driver numeric(12,2) not null default 0,
  merchant_owes_express numeric(12,2) not null default 0,
  driver_owes_merchant numeric(12,2) not null default 0,
  driver_owes_express numeric(12,2) not null default 0,
  express_owes_merchant numeric(12,2) not null default 0,
  express_owes_driver numeric(12,2) not null default 0,
  settlement_status text not null default 'pending'
    check(settlement_status in ('pending','partial','settled')),
  updated_at timestamptz not null default now()
);

insert into public.payment_method_catalog(
  provider_key,display_name,provider_type,active,credential_scope,
  supports_rides,supports_delivery,supports_subscriptions,supports_wallet
)
values(
  'transfer','Transferencia','transfer',true,'zone',
  false,true,false,false
)
on conflict(provider_key) do update set
  display_name=excluded.display_name,
  provider_type=excluded.provider_type,
  active=true,
  supports_delivery=true;

insert into public.zone_payment_methods(
  zone_id,provider_key,enabled,use_rides,use_delivery,use_subscriptions,
  use_wallet,is_primary,sort_order,public_config
)
select
  z.id,'transfer',true,false,true,false,false,false,40,
  jsonb_build_object(
    'requires_merchant_approval',true,
    'label','Transferencia al comercio'
  )
from public.service_zones z
where z.zone_key in ('iquique','trinidad')
on conflict(zone_id,provider_key) do update set
  enabled=true,
  use_delivery=true,
  public_config=excluded.public_config,
  updated_at=now();
