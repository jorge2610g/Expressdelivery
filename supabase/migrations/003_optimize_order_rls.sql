-- Optimize order RLS policies and status-history lookups

create index if not exists order_status_history_changed_by_idx
on public.order_status_history(changed_by);

drop policy if exists orders_driver_pending_select on public.orders;
drop policy if exists orders_driver_accept on public.orders;

drop policy if exists orders_select_customer_or_driver on public.orders;
create policy orders_select_customer_or_driver
on public.orders for select
to authenticated
using (
  (select auth.uid()) = customer_id
  or (select auth.uid()) = driver_id
  or (
    status = 'pending'
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'driver'
    )
  )
);

drop policy if exists orders_update_assigned_driver on public.orders;
create policy orders_update_assigned_driver
on public.orders for update
to authenticated
using (
  (select auth.uid()) = driver_id
  or (
    status = 'pending'
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'driver'
    )
  )
)
with check (
  (select auth.uid()) = driver_id
);

-- Admin dashboard: settings and full operational access
create table if not exists public.app_settings (
  id integer primary key default 1 check (id = 1),
  base_price numeric(12,2) not null default 1500 check (base_price >= 0),
  price_per_km numeric(12,2) not null default 800 check (price_per_km >= 0),
  updated_at timestamptz not null default now()
);
insert into public.app_settings(id, base_price, price_per_km)
values (1, 1500, 800) on conflict (id) do nothing;
alter table public.app_settings enable row level security;
drop policy if exists app_settings_read_authenticated on public.app_settings;
create policy app_settings_read_authenticated on public.app_settings for select to authenticated using (true);
drop policy if exists app_settings_admin_update on public.app_settings;
create policy app_settings_admin_update on public.app_settings for update to authenticated
using (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
drop policy if exists orders_admin_select on public.orders;
create policy orders_admin_select on public.orders for select to authenticated
using (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
drop policy if exists orders_admin_update on public.orders;
create policy orders_admin_update on public.orders for update to authenticated
using (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
drop policy if exists profiles_admin_select on public.profiles;
create policy profiles_admin_select on public.profiles for select to authenticated
using ((select auth.uid())=id or exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'));
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated
using (exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'))
with check (role in ('customer','driver','admin'));
