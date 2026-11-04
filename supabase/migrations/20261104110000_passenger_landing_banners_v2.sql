-- Passenger carousel: the banners RPC now also returns media type, video URL,
-- seconds per ad and advertiser name. Same signature and same access rules as v1
-- (caller's own runtime channel, zone scope, active dates). Read-only.
begin;

create or replace function public.passenger_landing_banners_v1(p_zone_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare v_channel text; v_result jsonb;
begin
  if auth.uid() is null or p_zone_id is null then
    return '[]'::jsonb;
  end if;
  -- Ignore caller-supplied environment entirely.
  v_channel:=public.admin_user_runtime_environment(auth.uid());
  if v_channel not in ('preview','production') then
    return '[]'::jsonb;
  end if;
  if not exists (select 1 from public.service_zones where id=p_zone_id) then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',b.id,'title',b.title,'subtitle',b.subtitle,
      'cta_label',b.cta_label,'image_url',b.image_url,
      'target_module',b.target_module,'target_url',b.target_url,
      'style_key',b.style_key,
      'media_type',b.media_type,'media_url',b.media_url,
      'display_seconds',b.display_seconds,
      'advertiser_name',b.advertiser_name
    ) order by b.sort_order,b.created_at desc
  ),'[]'::jsonb) into v_result
  from public.passenger_landing_banners b
  where b.zone_id=p_zone_id and b.channel=v_channel and b.active
    and (b.starts_at is null or b.starts_at<=now())
    and (b.ends_at is null or b.ends_at>now());
  return v_result;
end $$;

commit;
