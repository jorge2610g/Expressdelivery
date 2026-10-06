-- Prevent a driver from becoming available for new requests while a trip
-- or delivery is still active. The active service itself continues using the
-- internal busy/offline presentation and location tracking remains tied to the
-- service state.

create or replace function public.guard_driver_online_requires_driver_mode()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.online_status in ('online','busy') then
    if not exists (
      select 1
      from public.users u
      where u.id=new.id
        and u.account_status='active'
        and u.active_mode='driver'
    ) then
      raise exception 'Debes estar en modo Conductor para conectarte';
    end if;
  end if;

  if new.online_status='online' then
    if exists (
      select 1
      from public.trips t
      where t.driver_id=new.id
        and t.status not in ('completed','cancelled')
    ) or exists (
      select 1
      from public.delivery_requests d
      where d.courier_id=new.id
        and d.status not in ('delivered','cancelled')
    ) then
      raise exception 'No puedes ponerte en línea mientras tienes un servicio activo';
    end if;
  end if;

  return new;
end;
$$;

-- Repair any stale availability left by an older client. Keep active service
-- semantics as busy instead of exposing the driver as available.
update public.driver_profiles dp
set online_status='busy',
    updated_at=now()
where dp.online_status='online'
  and (
    exists (
      select 1
      from public.trips t
      where t.driver_id=dp.id
        and t.status not in ('completed','cancelled')
    )
    or exists (
      select 1
      from public.delivery_requests d
      where d.courier_id=dp.id
        and d.status not in ('delivered','cancelled')
    )
  );

revoke all on function public.guard_driver_online_requires_driver_mode()
from public,anon,authenticated;
