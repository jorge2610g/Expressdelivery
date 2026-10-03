-- Make Express Delivery priority operational for couriers, not only visual.
alter table public.delivery_requests
  add column if not exists marketplace_priority boolean not null default false,
  add column if not exists dispatch_priority integer not null default 0;

create index if not exists delivery_requests_dispatch_priority_idx
  on public.delivery_requests(status,dispatch_priority desc,created_at asc)
  where status='searching' and courier_id is null;

create or replace function public.sync_marketplace_delivery_priority()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_priority boolean:=false;
begin
  if new.marketplace_order_id is not null then
    select coalesce(o.is_priority,false)
    into v_priority
    from public.marketplace_orders o
    where o.id=new.marketplace_order_id;

    new.marketplace_priority:=coalesce(v_priority,false);
    new.dispatch_priority:=case when coalesce(v_priority,false) then 100 else 0 end;
  else
    new.marketplace_priority:=false;
    new.dispatch_priority:=0;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_sync_marketplace_delivery_priority
  on public.delivery_requests;
create trigger trg_sync_marketplace_delivery_priority
before insert or update of marketplace_order_id
on public.delivery_requests
for each row execute function public.sync_marketplace_delivery_priority();

update public.delivery_requests d
set
  marketplace_priority=coalesce(o.is_priority,false),
  dispatch_priority=case when coalesce(o.is_priority,false) then 100 else 0 end
from public.marketplace_orders o
where o.id=d.marketplace_order_id
  and (
    d.marketplace_priority is distinct from coalesce(o.is_priority,false)
    or d.dispatch_priority is distinct from
      case when coalesce(o.is_priority,false) then 100 else 0 end
  );

revoke execute on function public.sync_marketplace_delivery_priority()
from public,anon,authenticated;
