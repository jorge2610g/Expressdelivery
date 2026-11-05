-- Anuncios de pasajeros por lugar de la app.
-- Cada anuncio elige en qué pantallas aparece:
--   home_landing  = carrusel "Ofertas para ti" (pantalla de inicio por zona)
--   map_home      = panel "¿A dónde vas?" del mapa
--   ride_chooser  = tarjeta dentro de "¿A dónde y por cuánto?"
-- Anuncios existentes quedan solo en home_landing (sin cambio de comportamiento).
-- Aditiva: se crean funciones nuevas (v3) y las v1/v2 siguen funcionando.
begin;

alter table public.passenger_landing_banners
  add column if not exists placements text[] not null
    default array['home_landing']::text[];

alter table public.passenger_landing_banners
  drop constraint if exists landing_banner_placements_valid;
alter table public.passenger_landing_banners
  add constraint landing_banner_placements_valid
  check (
    cardinality(placements) > 0
    and placements <@ array['home_landing','map_home','ride_chooser']::text[]
  );

-- Lectura para la app de pasajeros: mismas reglas que v1 (entorno propio de la
-- cuenta, zona, activo y fechas) más filtro por lugar.
create or replace function public.passenger_ads_v1(p_zone_id uuid, p_placement text)
returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare v_channel text; v_result jsonb;
begin
  if auth.uid() is null or p_zone_id is null
     or p_placement not in ('home_landing','map_home','ride_chooser') then
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
    and p_placement = any(b.placements)
    and (b.starts_at is null or b.starts_at<=now())
    and (b.ends_at is null or b.ends_at>now());
  return v_result;
end $$;

revoke all on function public.passenger_ads_v1(uuid,text) from public,anon;
grant execute on function public.passenger_ads_v1(uuid,text) to authenticated;

-- Guardado para el panel: igual que v2 más lugares elegidos.
create or replace function public.admin_landing_banner_save_v3(
  p_id uuid,p_zone_id uuid,p_channel text,p_title text,p_subtitle text,
  p_cta_label text,p_image_url text,p_target_module text,p_target_url text,
  p_style_key text,p_active boolean,p_sort_order integer,
  p_starts_at timestamptz default null,p_ends_at timestamptz default null,
  p_media_type text default null,p_media_url text default null,
  p_display_seconds integer default null,p_advertiser_name text default null,
  p_advertiser_contact text default null,p_amount_bs numeric default null,
  p_payment_status text default null,p_placements text[] default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_ctx jsonb; v_id uuid; v_country text;
  v_media text; v_seconds integer; v_payment text; v_places text[];
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
  v_places:=coalesce(p_placements,array['home_landing']::text[]);
  if cardinality(v_places) = 0
     or not v_places <@ array['home_landing','map_home','ride_chooser']::text[] then
    raise exception 'Elige al menos un lugar válido para el anuncio';
  end if;

  insert into public.passenger_landing_banners(
    id,zone_id,channel,title,subtitle,cta_label,image_url,
    target_module,target_url,style_key,active,sort_order,
    starts_at,ends_at,media_type,media_url,display_seconds,
    advertiser_name,advertiser_contact,amount_bs,payment_status,
    placements,updated_at
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
    p_amount_bs,v_payment,v_places,now()
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
    placements=excluded.placements,
    updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.admin_landing_banner_save_v3(
  uuid,uuid,text,text,text,text,text,text,text,text,boolean,integer,
  timestamptz,timestamptz,text,text,integer,text,text,numeric,text,text[]) from public,anon;
grant execute on function public.admin_landing_banner_save_v3(
  uuid,uuid,text,text,text,text,text,text,text,text,boolean,integer,
  timestamptz,timestamptz,text,text,integer,text,text,numeric,text,text[]) to authenticated;

commit;
