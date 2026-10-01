-- Driver offers are short-lived UI decisions. Keep their lifetime on the
-- server so a browser reload cannot restart the passenger countdown.
create or replace function public.enforce_driver_offer_deadline()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.created_at := coalesce(new.created_at, now());
  if new.status = 'pending' then
    new.expires_at := new.created_at + interval '15 seconds';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_driver_offer_deadline on public.driver_offers;

create trigger trg_driver_offer_deadline
before insert or update of created_at, expires_at, status
on public.driver_offers
for each row
execute function public.enforce_driver_offer_deadline();

update public.driver_offers
set expires_at = created_at + interval '15 seconds'
where status = 'pending'
  and (
    expires_at is null
    or expires_at > created_at + interval '15 seconds'
  );
