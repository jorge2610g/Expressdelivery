-- Allow parent-zone cascades without recreating revision rows for a deleted zone.
begin;
create or replace function public.notify_express_ad_revision()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op in ('UPDATE','DELETE') and exists(
      select 1 from public.service_zones where id=old.zone_id) then
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
commit;
