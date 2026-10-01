-- Keep pending driver offers visible long enough for the passenger to act.
-- The server enforces the minimum even when an older Preview client submits
-- a shorter expires_at value.

create or replace function public.enforce_driver_offer_minimum_lifetime()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'pending' then
    if new.expires_at is null
       or new.expires_at < now() + interval '30 seconds' then
      new.expires_at := now() + interval '30 seconds';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_driver_offer_minimum_lifetime
on public.driver_offers;

create trigger trg_enforce_driver_offer_minimum_lifetime
before insert or update of expires_at, status
on public.driver_offers
for each row
execute function public.enforce_driver_offer_minimum_lifetime();
