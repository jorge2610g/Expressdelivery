-- Express Delivery V2
-- Multi-country / multi-zone schema. Additive and backward compatible.
-- Production visibility remains OFF unless explicitly enabled later.

create extension if not exists pgcrypto;

alter table public.saved_addresses
  add column if not exists zone_id uuid references public.service_zones(id),
  add column if not exists country_code text,
  add column if not exists is_default boolean not null default false,
  add column if not exists delivery_instructions text;

alter table public.marketplace_merchants
  add column if not exists business_hours jsonb not null default '{}'::jsonb,
  add column if not exists open_override boolean,
  add column if not exists minimum_order numeric(12,2) not null default 0,
  add column if not exists is_sponsored boolean not null default false,
  add column if not exists tags text[] not null default '{}'::text[];

alter table public.marketplace_banners
  add column if not exists zone_id uuid references public.service_zones(id),
  add column if not exists country_code text;

create table if not exists public.marketplace_menu_sections (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.marketplace_merchants(id) on delete cascade,
  section_key text not null,
  name text not null,
  subtitle text,
  sort_order integer not null default 100,
  active boolean not null default true,
  preview_visible boolean not null default true,
  production_visible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(merchant_id, section_key)
);

alter table public.marketplace_products
  add column if not exists menu_section_id uuid references public.marketplace_menu_sections(id) on delete set null,
  add column if not exists compare_at_price numeric(12,2),
  add column if not exists promo_price numeric(12,2),
  add column if not exists promo_start_at timestamptz,
  add column if not exists promo_end_at timestamptz,
  add column if not exists promo_label text,
  add column if not exists is_sponsored boolean not null default false,
  add column if not exists is_featured boolean not null default false,
  add column if not exists rating numeric(3,2) not null default 0,
  add column if not exists review_count integer not null default 0,
  add column if not exists sold_count integer not null default 0,
  add column if not exists tags text[] not null default '{}'::text[];

create table if not exists public.marketplace_product_modifier_groups (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.marketplace_products(id) on delete cascade,
  name text not null,
  description text,
  min_select integer not null default 0 check (min_select >= 0),
  max_select integer not null default 1 check (max_select >= 1),
  required boolean not null default false,
  sort_order integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (max_select >= min_select)
);

create table if not exists public.marketplace_product_modifiers (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.marketplace_product_modifier_groups(id) on delete cascade,
  name text not null,
  price_delta numeric(12,2) not null default 0,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_product_cross_sells (
  product_id uuid not null references public.marketplace_products(id) on delete cascade,
  recommended_product_id uuid not null references public.marketplace_products(id) on delete cascade,
  sort_order integer not null default 100,
  primary key(product_id,recommended_product_id),
  check (product_id <> recommended_product_id)
);

create table if not exists public.marketplace_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  order_id uuid not null references public.marketplace_orders(id) on delete cascade,
  merchant_id uuid not null references public.marketplace_merchants(id) on delete cascade,
  product_id uuid references public.marketplace_products(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists marketplace_reviews_unique_target_idx
  on public.marketplace_reviews(
    order_id,
    merchant_id,
    coalesce(product_id,'00000000-0000-0000-0000-000000000000'::uuid)
  );

create table if not exists public.marketplace_home_sections (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid references public.service_zones(id) on delete cascade,
  country_code text,
  section_key text not null,
  title text not null,
  subtitle text,
  section_type text not null default 'merchants'
    check (section_type in ('merchants','products','promotions')),
  source_rule text not null default 'popular'
    check (source_rule in ('popular','trusted','preferences','deals','lowest_price','sponsored','manual')),
  config jsonb not null default '{}'::jsonb,
  sort_order integer not null default 100,
  active boolean not null default true,
  preview_visible boolean not null default true,
  production_visible boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists marketplace_home_sections_scope_key_idx
  on public.marketplace_home_sections(
    coalesce(zone_id,'00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(country_code,''),
    section_key
  );

create table if not exists public.marketplace_coupons (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid references public.service_zones(id) on delete cascade,
  country_code text,
  code text not null,
  title text not null,
  description text,
  discount_type text not null check (discount_type in ('percent','fixed')),
  discount_value numeric(12,2) not null check (discount_value > 0),
  min_order numeric(12,2) not null default 0,
  max_discount numeric(12,2),
  funded_by text not null default 'express'
    check (funded_by in ('express','merchant')),
  usage_limit integer,
  per_user_limit integer not null default 1,
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  preview_visible boolean not null default true,
  production_visible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists marketplace_coupons_code_idx
  on public.marketplace_coupons(lower(code));

create table if not exists public.marketplace_coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.marketplace_coupons(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  order_id uuid not null references public.marketplace_orders(id) on delete cascade,
  discount_amount numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  unique(coupon_id,order_id)
);

create table if not exists public.marketplace_billing_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  country_code text not null,
  legal_name text not null,
  tax_id text,
  email text,
  billing_address text,
  is_default boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id,country_code)
);

alter table public.marketplace_orders
  add column if not exists country_code text,
  add column if not exists saved_address_id uuid references public.saved_addresses(id) on delete set null,
  add column if not exists merchant_note text,
  add column if not exists delivery_instructions text,
  add column if not exists delivery_option text not null default 'door'
    check (delivery_option in ('door','call','concierge','leave_at_door')),
  add column if not exists coupon_id uuid references public.marketplace_coupons(id) on delete set null,
  add column if not exists coupon_code text,
  add column if not exists coupon_discount numeric(12,2) not null default 0,
  add column if not exists billing_profile_snapshot jsonb not null default '{}'::jsonb,
  add column if not exists donation_amount numeric(12,2) not null default 0,
  add column if not exists pickup_code_hash text,
  add column if not exists delivery_code_hash text,
  add column if not exists pickup_verified_at timestamptz,
  add column if not exists delivery_verified_at timestamptz;

alter table public.marketplace_order_items
  add column if not exists base_unit_price numeric(12,2),
  add column if not exists modifiers_total numeric(12,2) not null default 0,
  add column if not exists selected_modifiers jsonb not null default '[]'::jsonb,
  add column if not exists customer_note text,
  add column if not exists promotion_discount numeric(12,2) not null default 0;

update public.marketplace_orders o
set country_code=z.country_code
from public.service_zones z
where z.id=o.zone_id and o.country_code is null;

update public.saved_addresses a
set zone_id=public.service_zone_id_for_point(a.latitude,a.longitude)
where a.zone_id is null
  and a.latitude is not null
  and a.longitude is not null;

update public.saved_addresses a
set country_code=z.country_code
from public.service_zones z
where z.id=a.zone_id
  and a.country_code is null;

insert into public.marketplace_menu_sections(
  merchant_id,section_key,name,sort_order,active,preview_visible,production_visible
)
select m.id,'menu','Menú',100,true,true,false
from public.marketplace_merchants m
on conflict(merchant_id,section_key) do nothing;

update public.marketplace_products p
set menu_section_id=s.id
from public.marketplace_menu_sections s
where s.merchant_id=p.merchant_id
  and s.section_key='menu'
  and p.menu_section_id is null;

insert into public.marketplace_home_sections(
  zone_id,country_code,section_key,title,subtitle,section_type,source_rule,sort_order,
  active,preview_visible,production_visible
)
select z.id,z.country_code,v.section_key,v.title,v.subtitle,v.section_type,v.source_rule,
       v.sort_order,true,true,false
from public.service_zones z
cross join (
  values
    ('popular','Los más pedidos esta semana','Lo que más están pidiendo cerca de ti','merchants','popular',10),
    ('trusted','Locales de confianza','Buenas calificaciones y entregas consistentes','merchants','trusted',20),
    ('preferences','Según tus preferencias','Sugerencias basadas en tu actividad en esta zona','products','preferences',30),
    ('deals','Promociones para ti','Descuentos y beneficios disponibles ahora','promotions','deals',40),
    ('lowest_price','Buen precio','Opciones con precios convenientes','products','lowest_price',50)
) as v(section_key,title,subtitle,section_type,source_rule,sort_order)
where exists(
  select 1 from public.marketplace_zone_settings mz
  where mz.zone_id=z.id and mz.preview_enabled=true
)
on conflict do nothing;

create index if not exists marketplace_menu_sections_merchant_idx
  on public.marketplace_menu_sections(merchant_id,sort_order);
create index if not exists marketplace_products_menu_section_idx
  on public.marketplace_products(menu_section_id,sort_order);
create index if not exists marketplace_products_tags_gin_idx
  on public.marketplace_products using gin(tags);
create index if not exists marketplace_modifier_groups_product_idx
  on public.marketplace_product_modifier_groups(product_id,sort_order);
create index if not exists marketplace_modifiers_group_idx
  on public.marketplace_product_modifiers(group_id,sort_order);
create index if not exists marketplace_reviews_merchant_idx
  on public.marketplace_reviews(merchant_id,created_at desc);
create index if not exists marketplace_reviews_product_idx
  on public.marketplace_reviews(product_id,created_at desc)
  where product_id is not null;
create index if not exists marketplace_home_sections_zone_idx
  on public.marketplace_home_sections(zone_id,sort_order);
create index if not exists marketplace_coupons_scope_idx
  on public.marketplace_coupons(zone_id,country_code,active);
create index if not exists marketplace_coupon_redemptions_user_idx
  on public.marketplace_coupon_redemptions(user_id,coupon_id);
create index if not exists marketplace_orders_country_idx
  on public.marketplace_orders(customer_id,country_code,created_at desc);
create index if not exists saved_addresses_country_idx
  on public.saved_addresses(user_id,country_code,created_at);

create or replace function public.marketplace_set_order_country()
returns trigger
language plpgsql
set search_path='public'
as $$
begin
  if new.zone_id is not null then
    select z.country_code into new.country_code
    from public.service_zones z
    where z.id=new.zone_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_marketplace_set_order_country
  on public.marketplace_orders;
create trigger trg_marketplace_set_order_country
before insert or update of zone_id on public.marketplace_orders
for each row execute function public.marketplace_set_order_country();

alter table public.marketplace_menu_sections enable row level security;
alter table public.marketplace_product_modifier_groups enable row level security;
alter table public.marketplace_product_modifiers enable row level security;
alter table public.marketplace_product_cross_sells enable row level security;
alter table public.marketplace_reviews enable row level security;
alter table public.marketplace_home_sections enable row level security;
alter table public.marketplace_coupons enable row level security;
alter table public.marketplace_coupon_redemptions enable row level security;
alter table public.marketplace_billing_profiles enable row level security;

revoke all on table public.marketplace_menu_sections from anon,authenticated;
revoke all on table public.marketplace_product_modifier_groups from anon,authenticated;
revoke all on table public.marketplace_product_modifiers from anon,authenticated;
revoke all on table public.marketplace_product_cross_sells from anon,authenticated;
revoke all on table public.marketplace_reviews from anon,authenticated;
revoke all on table public.marketplace_home_sections from anon,authenticated;
revoke all on table public.marketplace_coupons from anon,authenticated;
revoke all on table public.marketplace_coupon_redemptions from anon,authenticated;

grant select,insert,update,delete
  on table public.marketplace_billing_profiles to authenticated;
grant all on table public.marketplace_billing_profiles to service_role;
grant all on table public.marketplace_menu_sections to service_role;
grant all on table public.marketplace_product_modifier_groups to service_role;
grant all on table public.marketplace_product_modifiers to service_role;
grant all on table public.marketplace_product_cross_sells to service_role;
grant all on table public.marketplace_reviews to service_role;
grant all on table public.marketplace_home_sections to service_role;
grant all on table public.marketplace_coupons to service_role;
grant all on table public.marketplace_coupon_redemptions to service_role;

drop policy if exists marketplace_billing_profiles_select_own
  on public.marketplace_billing_profiles;
create policy marketplace_billing_profiles_select_own
on public.marketplace_billing_profiles for select
to authenticated
using ((select auth.uid())=user_id);

drop policy if exists marketplace_billing_profiles_insert_own
  on public.marketplace_billing_profiles;
create policy marketplace_billing_profiles_insert_own
on public.marketplace_billing_profiles for insert
to authenticated
with check ((select auth.uid())=user_id);

drop policy if exists marketplace_billing_profiles_update_own
  on public.marketplace_billing_profiles;
create policy marketplace_billing_profiles_update_own
on public.marketplace_billing_profiles for update
to authenticated
using ((select auth.uid())=user_id)
with check ((select auth.uid())=user_id);

drop policy if exists marketplace_billing_profiles_delete_own
  on public.marketplace_billing_profiles;
create policy marketplace_billing_profiles_delete_own
on public.marketplace_billing_profiles for delete
to authenticated
using ((select auth.uid())=user_id);
