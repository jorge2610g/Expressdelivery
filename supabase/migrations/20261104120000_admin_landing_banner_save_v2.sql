-- Admin: save passenger carousel ads with video, seconds per ad and advertiser.
-- New function (v2) with the same authorization rules as v1; v1 stays untouched
-- so older panels keep working. Missing new arguments take safe defaults.
begin;

create or replace function public.admin_landing_banner_save_v2(
  p_id uuid,p_zone_id uuid,p_channel text,p_title text,p_subtitle text,
  p_cta_label text,p_image_url text,p_target_module text,p_target_url text,
  p_style_key text,p_active boolean,p_sort_order integer,
  p_starts_at timestamptz default null,p_ends_at timestamptz default null,
  p_media_type text default null,p_media_url text default null,
  p_display_seconds integer default null,p_advertiser_name text default null,
  p_advertiser_contact text default null,p_amount_bs numeric default null,
  p_payment_status text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_ctx jsonb; v_id uuid; v_country text;
  v_media text; v_seconds integer; v_payment text;
begin
  v_ctx:=public.admin_access_context();
  if v_ctx->>'allowed' is distinct from 'true'
      or v_ctx->>'read_only'='true'
      or p_channel not in ('preview','production')
      or not public.admin_environment_allowed(p_channel)
      or p_zone_id is null then
    raise exception 'No autorizado para administrar publicidad';
  end if;
  select country_code into v_country from public.service_zones
  where id=p_zone_id;
  if not found then raise exception 'Zona no encontrada'; end if;
  if v_ctx->>'zone_id' is not null
      and v_ctx->>'zone_id' <> p_zone_id::text then
    raise exception 'Zona fuera de tus permisos';
  end if;
  if v_ctx->>'country_code' is not null
      and v_ctx->>'country_code' <> v_country then
    raise exception 'País fuera de tus permisos';
  end if;
  if nullif(trim(coalesce(p_title,'')),'') is null then
    raise exception 'Escribe un título';
  end if;
  if p_id is not null and not exists(
    select 1 from public.passenger_landing_banners
    where id=p_id and zone_id=p_zone_id and channel=p_channel
  ) then raise exception 'El banner no pertenece a la zona y entorno'; end if;

  v_media:=coalesce(nullif(trim(coalesce(p_media_type,'')),''),'image');
  if v_media not in ('image','video') then
    raise exception 'El tipo de medio debe ser imagen o video';
  end if;
  if v_media='video' and coalesce(trim(p_media_url),'') !~ '^https://' then
    raise exception 'El video necesita una URL https';
  end if;
  v_seconds:=coalesce(p_display_seconds,5);
  if v_seconds < 3 or v_seconds > 60 then
    raise exception 'Los segundos del anuncio deben estar entre 3 y 60';
  end if;
  v_payment:=coalesce(nullif(trim(coalesce(p_payment_status,'')),''),'unpaid');
  if v_payment not in ('unpaid','paid','exempt') then
    raise exception 'El estado de pago no es válido';
  end if;

  insert into public.passenger_landing_banners(
    id,zone_id,channel,title,subtitle,cta_label,image_url,
    target_module,target_url,style_key,active,sort_order,
    starts_at,ends_at,media_type,media_url,display_seconds,
    advertiser_name,advertiser_contact,amount_bs,payment_status,updated_at
  ) values(
    coalesce(p_id,gen_random_uuid()),p_zone_id,p_channel,trim(p_title),
    coalesce(p_subtitle,''),coalesce(nullif(trim(p_cta_label),''),'Descubrir'),
    nullif(trim(coalesce(p_image_url,'')),''),
    nullif(trim(coalesce(p_target_module,'')),''),
    nullif(trim(coalesce(p_target_url,'')),''),
    coalesce(nullif(trim(p_style_key),''),'blue'),
    coalesce(p_active,true),coalesce(p_sort_order,100),
    p_starts_at,p_ends_at,v_media,
    nullif(trim(coalesce(p_media_url,'')),''),v_seconds,
    trim(coalesce(p_advertiser_name,'')),trim(coalesce(p_advertiser_contact,'')),
    p_amount_bs,v_payment,now()
  ) on conflict (id) do update set
    title=excluded.title,subtitle=excluded.subtitle,
    cta_label=excluded.cta_label,image_url=excluded.image_url,
    target_module=excluded.target_module,target_url=excluded.target_url,
    style_key=excluded.style_key,active=excluded.active,
    sort_order=excluded.sort_order,starts_at=excluded.starts_at,
    ends_at=excluded.ends_at,media_type=excluded.media_type,
    media_url=excluded.media_url,display_seconds=excluded.display_seconds,
    advertiser_name=excluded.advertiser_name,
    advertiser_contact=excluded.advertiser_contact,
    amount_bs=excluded.amount_bs,payment_status=excluded.payment_status,
    updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.admin_landing_banner_save_v2(
  uuid,uuid,text,text,text,text,text,text,text,text,boolean,integer,
  timestamptz,timestamptz,text,text,integer,text,text,numeric,text) from public,anon;
grant execute on function public.admin_landing_banner_save_v2(
  uuid,uuid,text,text,text,text,text,text,text,text,boolean,integer,
  timestamptz,timestamptz,text,text,integer,text,text,numeric,text) to authenticated;

commit;
