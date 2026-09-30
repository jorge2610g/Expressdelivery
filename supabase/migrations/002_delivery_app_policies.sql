-- Express Delivery - driver policies and automatic status history

create or replace function app_private.record_order_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history(order_id, status, changed_by)
    values (new.id, new.status, auth.uid());
  elsif old.status is distinct from new.status then
    insert into public.order_status_history(order_id, status, changed_by)
    values (new.id, new.status, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists orders_status_history_trigger on public.orders;
create trigger orders_status_history_trigger
after insert or update of status on public.orders
for each row execute function app_private.record_order_status_change();

drop policy if exists orders_driver_pending_select on public.orders;
create policy orders_driver_pending_select
on public.orders for select
to authenticated
using (
  status = 'pending'
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'driver'
  )
);

drop policy if exists orders_driver_accept on public.orders;
create policy orders_driver_accept
on public.orders for update
to authenticated
using (
  status = 'pending'
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'driver'
  )
)
with check (
  driver_id = auth.uid()
  and status = 'accepted'
);