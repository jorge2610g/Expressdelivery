-- Notify clients of campaign changes without exposing private advertiser fields.
begin;
create table public.express_ad_revisions (
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  channel text not null check(channel in ('preview','production')),
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  primary key(zone_id,channel)
);
alter table public.express_ad_revisions enable row level security;
revoke all on public.express_ad_revisions from public,anon,authenticated;
grant select on public.express_ad_revisions to authenticated;
create policy express_ad_revisions_own_environment
on public.express_ad_revisions for select to authenticated
using(channel = (select public.admin_user_runtime_environment(auth.uid())));

create or replace function public.notify_express_ad_revision()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op in ('UPDATE','DELETE') then
    insert into public.express_ad_revisions(zone_id,channel)
    values(old.zone_id,old.channel)
    on conflict(zone_id,channel) do update set
      revision=express_ad_revisions.revision+1,updated_at=now();
  end if;
  if tg_op='INSERT' or (tg_op='UPDATE' and
      (new.zone_id,new.channel) is distinct from (old.zone_id,old.channel)) then
    insert into public.express_ad_revisions(zone_id,channel)
    values(new.zone_id,new.channel)
    on conflict(zone_id,channel) do update set
      revision=express_ad_revisions.revision+1,updated_at=now();
  end if;
  return null;
end;
$$;
revoke all on function public.notify_express_ad_revision() from public,anon,authenticated;
create trigger notify_express_ad_revision
  after insert or update or delete on public.passenger_landing_banners
  for each row execute function public.notify_express_ad_revision();

alter publication supabase_realtime add table public.express_ad_revisions;
commit;
