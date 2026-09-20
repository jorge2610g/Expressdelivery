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