-- Ordered creatives within one campaign; private metadata stays on the campaign.
begin;
alter table public.passenger_landing_banners add column slides jsonb not null default '[]'::jsonb;
alter table public.passenger_landing_banners add constraint landing_banner_slides_array
  check(case when jsonb_typeof(slides)='array' then jsonb_array_length(slides)<=20 else false end);

create or replace function public.passenger_ads_v2(p_zone_id uuid,p_placement text)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(a.value || jsonb_build_object('slides',b.slides) order by a.ord),'[]'::jsonb)
  from jsonb_array_elements(public.passenger_ads_v1(p_zone_id,p_placement)) with ordinality a(value,ord)
  join public.passenger_landing_banners b on b.id=(a.value->>'id')::uuid;
$$;
revoke all on function public.passenger_ads_v2(uuid,text) from public,anon;
grant execute on function public.passenger_ads_v2(uuid,text) to authenticated;

create or replace function public.driver_ads_v2(p_zone_id uuid,p_placement text)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(a.value || jsonb_build_object('slides',b.slides) order by a.ord),'[]'::jsonb)
  from jsonb_array_elements(public.driver_ads_v1(p_zone_id,p_placement)) with ordinality a(value,ord)
  join public.passenger_landing_banners b on b.id=(a.value->>'id')::uuid;
$$;
revoke all on function public.driver_ads_v2(uuid,text) from public,anon;
grant execute on function public.driver_ads_v2(uuid,text) to authenticated;

create or replace function public.admin_landing_banner_save_v4(
  p_id uuid,p_zone_id uuid,p_channel text,p_title text,p_subtitle text,
  p_cta_label text,p_image_url text,p_target_module text,p_target_url text,
  p_style_key text,p_active boolean,p_sort_order integer,
  p_starts_at timestamptz default null,p_ends_at timestamptz default null,
  p_media_type text default null,p_media_url text default null,
  p_display_seconds integer default null,p_advertiser_name text default null,
  p_advertiser_contact text default null,p_amount_bs numeric default null,
  p_payment_status text default null,p_placements text[] default null,
  p_slides jsonb default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_slides jsonb; v_slide jsonb;
begin
  if auth.uid() is null then raise exception 'No autorizado'; end if;
  v_slides:=coalesce(p_slides,jsonb_build_array(jsonb_build_object(
    'media_type',coalesce(nullif(p_media_type,''),'image'),
    'image_url',p_image_url,'video_url',p_media_url,'target_url',p_target_url)));
  if jsonb_typeof(v_slides) <> 'array' then raise exception 'Las imágenes no son válidas'; end if;
  if jsonb_array_length(v_slides) not between 1 and 20 then
    raise exception 'Añade entre 1 y 20 imágenes al banner';
  end if;
  for v_slide in select value from jsonb_array_elements(v_slides) loop
    if jsonb_typeof(v_slide) <> 'object'
        or coalesce(v_slide->>'media_type','image') not in ('image','video')
        or (coalesce(v_slide->>'media_type','image')='image'
          and coalesce(trim(v_slide->>'image_url'),'') !~ '^https://[^/[:space:]]+')
        or (v_slide->>'media_type'='video'
          and coalesce(trim(v_slide->>'video_url'),'') !~ '^https://[^/[:space:]]+')
        or coalesce(trim(v_slide->>'target_url'),'') !~ '^https://[^/[:space:]]+' then
      raise exception 'Cada pieza necesita una imagen o video válido y su URL HTTPS de destino';
    end if;
  end loop;
  select jsonb_agg(
    jsonb_build_object('media_type',coalesce(value->>'media_type','image'))
    || case when coalesce(value->>'media_type','image')='video'
      then jsonb_build_object('video_url',trim(value->>'video_url'))
      else jsonb_build_object('image_url',trim(value->>'image_url')) end
    || jsonb_build_object('target_url',trim(value->>'target_url')) order by ord)
    into v_slides
  from jsonb_array_elements(v_slides) with ordinality a(value,ord);
  -- Reuse the established role, zone, country and environment authorization.
  v_id:=public.admin_landing_banner_save_v3(
    p_id,
    p_zone_id,
    p_channel,
    p_title,
    p_subtitle,
    p_cta_label,
    coalesce(v_slides->0->>'image_url',v_slides->0->>'video_url'),
    p_target_module,
    v_slides->0->>'target_url',
    p_style_key,
    p_active,
    p_sort_order,
    p_starts_at,
    p_ends_at,
    v_slides->0->>'media_type',
    v_slides->0->>'video_url',
    p_display_seconds,
    p_advertiser_name,
    p_advertiser_contact,
    p_amount_bs,
    p_payment_status,
    p_placements);
  update public.passenger_landing_banners set slides=v_slides where id=v_id;
  return v_id;
end;
$$;
revoke all on function public.admin_landing_banner_save_v4(
  uuid,uuid,text,text,text,text,text,text,text,text,boolean,integer,
  timestamptz,timestamptz,text,text,integer,text,text,numeric,text,text[],jsonb)
  from public,anon;
grant execute on function public.admin_landing_banner_save_v4(
  uuid,uuid,text,text,text,text,text,text,text,text,boolean,integer,
  timestamptz,timestamptz,text,text,integer,text,text,numeric,text,text[],jsonb)
  to authenticated;
commit;
