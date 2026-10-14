-- Express landing advertisements: independent of Market activation.
-- One codebase serves Preview and Production; account identity, not a URL
-- parameter, selects which campaign rows the passenger may see.
create table if not exists public.passenger_landing_banners (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.service_zones(id) on delete cascade,
  channel text not null check (channel in ('preview','production')),
  title text not null check (char_length(title) between 1 and 100),
  subtitle text not null default '',
  cta_label text not null default 'Descubrir',
  image_url text,
  target_module text check (target_module in ('ride','delivery','market')),
  target_url text,
  style_key text not null default 'blue',
  active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint landing_banner_valid_dates
    check (starts_at is null or ends_at is null or starts_at < ends_at),
  constraint landing_banner_https_image
    check (image_url is null or image_url ~ '^https://'),
  constraint landing_banner_https_link
    check (target_url is null or target_url ~ '^https://')
);

create index if not exists idx_passenger_landing_banners_visible
  on public.passenger_landing_banners
  (zone_id, channel, active, sort_order, created_at desc);

alter table public.passenger_landing_banners enable row level security;
revoke all on table public.passenger_landing_banners from public, anon, authenticated;

-- Public media, private write: photos must not expose personal user data.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('express-landing-banners','express-landing-banners',true,
        5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public=true, file_size_limit=5242880,
  allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists landing_banner_admin_upload on storage.objects;
create policy landing_banner_admin_upload on storage.objects
for insert to authenticated with check (
  bucket_id='express-landing-banners' and public.is_admin()
);
drop policy if exists landing_banner_admin_update on storage.objects;
create policy landing_banner_admin_update on storage.objects
for update to authenticated using (
  bucket_id='express-landing-banners' and public.is_admin()
) with check (
  bucket_id='express-landing-banners' and public.is_admin()
);

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
      'style_key',b.style_key
    ) order by b.sort_order,b.created_at desc
  ),'[]'::jsonb) into v_result
  from public.passenger_landing_banners b
  where b.zone_id=p_zone_id and b.channel=v_channel and b.active
    and (b.starts_at is null or b.starts_at<=now())
    and (b.ends_at is null or b.ends_at>now());
  return v_result;
end $$;

create or replace function public.admin_landing_banners_list_v1(
  p_zone_id uuid,p_channel text
) returns jsonb language plpgsql stable security definer
set search_path=public as $$
declare v_ctx jsonb; v_zone_country text;
begin
  v_ctx:=public.admin_access_context();
  if v_ctx->>'allowed' is distinct from 'true'
     or p_channel not in ('preview','production')
     or not public.admin_environment_allowed(p_channel)
     or p_zone_id is null then
    raise exception 'No autorizado';
  end if;
  select country_code into v_zone_country from public.service_zones
  where id=p_zone_id;
  if not found then raise exception 'Zona no encontrada'; end if;
  if v_ctx->>'zone_id' is not null
      and v_ctx->>'zone_id' <> p_zone_id::text then
    raise exception 'Zona fuera de tus permisos';
  end if;
  if v_ctx->>'country_code' is not null
      and v_ctx->>'country_code' <> v_zone_country then
    raise exception 'País fuera de tus permisos';
  end if;
  return (select coalesce(jsonb_agg(to_jsonb(b)
      order by b.sort_order,b.created_at desc),'[]'::jsonb)
    from public.passenger_landing_banners b
    where b.zone_id=p_zone_id and b.channel=p_channel);
end $$;

create or replace function public.admin_landing_banner_save_v1(
  p_id uuid,p_zone_id uuid,p_channel text,p_title text,p_subtitle text,
  p_cta_label text,p_image_url text,p_target_module text,p_target_url text,
  p_style_key text,p_active boolean,p_sort_order integer,
  p_starts_at timestamptz default null,p_ends_at timestamptz default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_id uuid; v_country text;
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
  insert into public.passenger_landing_banners(
    id,zone_id,channel,title,subtitle,cta_label,image_url,
    target_module,target_url,style_key,active,sort_order,
    starts_at,ends_at,updated_at
  ) values(
    coalesce(p_id,gen_random_uuid()),p_zone_id,p_channel,trim(p_title),
    coalesce(p_subtitle,''),coalesce(nullif(trim(p_cta_label),''),'Descubrir'),
    nullif(trim(coalesce(p_image_url,'')),''),
    nullif(trim(coalesce(p_target_module,'')),''),
    nullif(trim(coalesce(p_target_url,'')),''),
    coalesce(nullif(trim(p_style_key),''),'blue'),
    coalesce(p_active,true),coalesce(p_sort_order,100),
    p_starts_at,p_ends_at,now()
  ) on conflict (id) do update set
    title=excluded.title,subtitle=excluded.subtitle,
    cta_label=excluded.cta_label,image_url=excluded.image_url,
    target_module=excluded.target_module,target_url=excluded.target_url,
    style_key=excluded.style_key,active=excluded.active,
    sort_order=excluded.sort_order,starts_at=excluded.starts_at,
    ends_at=excluded.ends_at,updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.passenger_landing_banners_v1(uuid) from public,anon;
revoke all on function public.admin_landing_banners_list_v1(uuid,text) from public,anon;
revoke all on function public.admin_landing_banner_save_v1(
  uuid,uuid,text,text,text,text,text,text,text,text,boolean,integer,
  timestamptz,timestamptz) from public,anon;
grant execute on function public.passenger_landing_banners_v1(uuid)
  to authenticated;
grant execute on function public.admin_landing_banners_list_v1(uuid,text)
  to authenticated;
grant execute on function public.admin_landing_banner_save_v1(
  uuid,uuid,text,text,text,text,text,text,text,text,boolean,integer,
  timestamptz,timestamptz) to authenticated;
