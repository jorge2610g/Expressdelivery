begin;

alter table public.marketplace_merchants
  add column if not exists cover_image_url text;

alter table public.marketplace_products
  add column if not exists category_id uuid;

create table if not exists public.marketplace_merchant_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  channel text not null check (channel in ('preview','production')),
  email text not null,
  restaurant_name text not null,
  logo_url text not null,
  cover_image_url text not null,
  address text not null,
  latitude numeric not null,
  longitude numeric not null,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  review_note text,
  merchant_id uuid references public.marketplace_merchants(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(trim(restaurant_name)) between 2 and 120),
  check (length(trim(address)) between 4 and 500),
  check (latitude between -90 and 90),
  check (longitude between -180 and 180)
);

create unique index if not exists marketplace_merchant_applications_open_uidx
  on public.marketplace_merchant_applications(user_id,channel)
  where status = 'pending';
create index if not exists marketplace_merchant_applications_review_idx
  on public.marketplace_merchant_applications(channel,status,created_at desc);

alter table public.marketplace_merchant_applications enable row level security;
revoke all on public.marketplace_merchant_applications from public,anon,authenticated;
grant select on public.marketplace_merchant_applications to authenticated;
drop policy if exists marketplace_merchant_application_read_self
  on public.marketplace_merchant_applications;
create policy marketplace_merchant_application_read_self
  on public.marketplace_merchant_applications
  for select to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.marketplace_merchant_product_categories (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.marketplace_merchants(id) on delete cascade,
  name text not null,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (merchant_id, name),
  check (length(trim(name)) between 2 and 60)
);
create index if not exists marketplace_merchant_product_categories_active_idx
  on public.marketplace_merchant_product_categories(merchant_id,active,sort_order,name);
alter table public.marketplace_merchant_product_categories enable row level security;
revoke all on public.marketplace_merchant_product_categories from public,anon,authenticated;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname='marketplace_products_category_id_fkey'
      and conrelid='public.marketplace_products'::regclass
  ) then
    alter table public.marketplace_products
      add constraint marketplace_products_category_id_fkey
      foreign key(category_id)
      references public.marketplace_merchant_product_categories(id)
      on delete set null;
  end if;
end $$;

create or replace function public.marketplace_merchant_application_state(p_channel text)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_uid uuid := auth.uid(); v_result jsonb;
begin
  if v_uid is null or p_channel not in ('preview','production') then
    raise exception 'No autorizado';
  end if;
  if not exists (
    select 1 from public.account_runtime_bindings b
    where b.user_id=v_uid and b.environment=p_channel
  ) then
    raise exception 'Esta cuenta pertenece a otro entorno';
  end if;
  select to_jsonb(a) into v_result
  from public.marketplace_merchant_applications a
  where a.user_id=v_uid and a.channel=p_channel
  order by a.created_at desc limit 1;
  return coalesce(v_result,'{}'::jsonb);
end $$;
revoke all on function public.marketplace_merchant_application_state(text) from public,anon;
grant execute on function public.marketplace_merchant_application_state(text) to authenticated;

create or replace function public.marketplace_submit_merchant_application(
  p_channel text,p_email text,p_restaurant_name text,p_logo_url text,
  p_cover_image_url text,p_address text,p_latitude numeric,p_longitude numeric
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_uid uuid := auth.uid(); v_auth_email text; v_runtime jsonb; v_id uuid;
begin
  if v_uid is null then raise exception 'Inicia sesión para solicitar acceso'; end if;
  if p_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  v_runtime := public.ensure_current_runtime_access(p_channel);
  if coalesce((v_runtime->>'allowed')::boolean,false) is not true then
    raise exception 'Esta cuenta pertenece a otro entorno';
  end if;
  select lower(trim(email)) into v_auth_email from auth.users where id=v_uid;
  if v_auth_email is null or lower(trim(coalesce(p_email,''))) <> v_auth_email then
    raise exception 'El correo debe coincidir con la cuenta autenticada';
  end if;
  if length(trim(coalesce(p_restaurant_name,''))) not between 2 and 120
     or length(trim(coalesce(p_address,''))) not between 4 and 500
     or p_latitude is null or p_latitude not between -90 and 90
     or p_longitude is null or p_longitude not between -180 and 180
     or length(trim(coalesce(p_logo_url,''))) not between 8 and 1000
     or length(trim(coalesce(p_cover_image_url,''))) not between 8 and 1000 then
    raise exception 'Completa nombre, logo, portada y ubicación';
  end if;
  if exists(select 1 from public.marketplace_merchant_users mu
      where mu.user_id=v_uid and mu.active) then
    raise exception 'Esta cuenta ya administra un restaurante';
  end if;
  select id into v_id from public.marketplace_merchant_applications
    where user_id=v_uid and channel=p_channel and status='pending'
    for update;
  if v_id is null then
    insert into public.marketplace_merchant_applications(
      user_id,channel,email,restaurant_name,logo_url,cover_image_url,
      address,latitude,longitude,status
    ) values (
      v_uid,p_channel,v_auth_email,trim(p_restaurant_name),trim(p_logo_url),
      trim(p_cover_image_url),trim(p_address),p_latitude,p_longitude,'pending'
    ) returning id into v_id;
  else
    update public.marketplace_merchant_applications set
      email=v_auth_email,restaurant_name=trim(p_restaurant_name),
      logo_url=trim(p_logo_url),cover_image_url=trim(p_cover_image_url),
      address=trim(p_address),latitude=p_latitude,longitude=p_longitude,
      review_note=null,updated_at=now()
    where id=v_id;
  end if;
  return jsonb_build_object('id',v_id,'status','pending');
end $$;
revoke all on function public.marketplace_submit_merchant_application(
  text,text,text,text,text,text,numeric,numeric
) from public,anon;
grant execute on function public.marketplace_submit_merchant_application(
  text,text,text,text,text,text,numeric,numeric
) to authenticated;

create or replace function public.admin_marketplace_merchant_applications(
  p_channel text,p_zone_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb;
begin
  if not public.is_admin() then raise exception 'Solo Admin puede revisar solicitudes'; end if;
  if p_channel not in ('preview','production') then raise exception 'Entorno inválido'; end if;
  select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at),'[]'::jsonb)
  into v_result from public.marketplace_merchant_applications a
  where a.channel=p_channel and a.status='pending'
    and (p_zone_id is null or public.service_zone_id_for_point(a.latitude,a.longitude)=p_zone_id);
  return v_result;
end $$;
revoke all on function public.admin_marketplace_merchant_applications(text,uuid) from public,anon;
grant execute on function public.admin_marketplace_merchant_applications(text,uuid) to authenticated;

create or replace function public.admin_marketplace_approve_merchant_application(
  p_application_id uuid,p_zone_id uuid
) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_app public.marketplace_merchant_applications%rowtype;
  v_merchant uuid; v_zone public.service_zones%rowtype; v_bound text;
begin
  if not public.is_admin() then raise exception 'Solo Admin puede aprobar solicitudes'; end if;
  select * into v_app from public.marketplace_merchant_applications
    where id=p_application_id for update;
  if not found or v_app.status<>'pending' then raise exception 'Solicitud no disponible'; end if;
  select * into v_zone from public.service_zones where id=p_zone_id and active;
  if not found then raise exception 'Selecciona una zona activa'; end if;
  select environment into v_bound from public.account_runtime_bindings where user_id=v_app.user_id;
  if v_bound is distinct from v_app.channel then raise exception 'La cuenta no pertenece al entorno de esta solicitud'; end if;
  insert into public.marketplace_merchants(
    zone_id,category_key,name,image_url,cover_image_url,address,latitude,longitude,
    active,preview_visible,production_visible
  ) values (
    v_zone.id,'restaurants',v_app.restaurant_name,v_app.logo_url,v_app.cover_image_url,
    v_app.address,v_app.latitude,v_app.longitude,true,
    v_app.channel='preview',v_app.channel='production'
  ) returning id into v_merchant;
  insert into public.marketplace_merchant_users(merchant_id,user_id,role,active)
    values(v_merchant,v_app.user_id,'owner',true);
  update public.marketplace_merchant_applications set
    status='approved',merchant_id=v_merchant,reviewed_by=auth.uid(),
    reviewed_at=now(),updated_at=now()
  where id=v_app.id;
  return jsonb_build_object('application_id',v_app.id,'merchant_id',v_merchant);
end $$;
revoke all on function public.admin_marketplace_approve_merchant_application(uuid,uuid) from public,anon;
grant execute on function public.admin_marketplace_approve_merchant_application(uuid,uuid) to authenticated;

create or replace function public.admin_marketplace_reject_merchant_application(
  p_application_id uuid,p_reason text
) returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_admin() then raise exception 'Solo Admin puede rechazar solicitudes'; end if;
  if length(trim(coalesce(p_reason,''))) not between 4 and 500 then
    raise exception 'Escribe el motivo del rechazo';
  end if;
  update public.marketplace_merchant_applications set
    status='rejected',review_note=trim(p_reason),reviewed_by=auth.uid(),
    reviewed_at=now(),updated_at=now()
  where id=p_application_id and status='pending';
  if not found then raise exception 'Solicitud no disponible'; end if;
end $$;
revoke all on function public.admin_marketplace_reject_merchant_application(uuid,text) from public,anon;
grant execute on function public.admin_marketplace_reject_merchant_application(uuid,text) to authenticated;

create or replace function public.marketplace_merchant_categories(p_merchant_id uuid,p_channel text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_role text; v_rows jsonb;
begin
  select mu.role into v_role from public.marketplace_merchant_users mu
  join public.account_runtime_bindings b on b.user_id=mu.user_id and b.environment=p_channel
  join public.marketplace_merchants m on m.id=mu.merchant_id and m.active
  where mu.merchant_id=p_merchant_id and mu.user_id=auth.uid() and mu.active;
  if v_role is null or p_channel not in ('preview','production') then raise exception 'No autorizado'; end if;
  select coalesce(jsonb_agg(to_jsonb(c) order by c.sort_order,c.name),'[]'::jsonb)
    into v_rows from public.marketplace_merchant_product_categories c
    where c.merchant_id=p_merchant_id and c.active;
  return v_rows;
end $$;
revoke all on function public.marketplace_merchant_categories(uuid,text) from public,anon;
grant execute on function public.marketplace_merchant_categories(uuid,text) to authenticated;

create or replace function public.marketplace_merchant_upsert_category(
  p_merchant_id uuid,p_category_id uuid,p_name text,p_channel text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text; v_row public.marketplace_merchant_product_categories%rowtype;
begin
  select mu.role into v_role from public.marketplace_merchant_users mu
  join public.account_runtime_bindings b on b.user_id=mu.user_id and b.environment=p_channel
  join public.marketplace_merchants m on m.id=mu.merchant_id and m.active
  where mu.merchant_id=p_merchant_id and mu.user_id=auth.uid() and mu.active;
  if v_role not in ('owner','manager') or p_channel not in ('preview','production') then
    raise exception 'No tienes permisos para categorías';
  end if;
  if length(trim(coalesce(p_name,''))) not between 2 and 60 then raise exception 'Nombre de categoría inválido'; end if;
  if p_category_id is not null and not exists(
    select 1 from public.marketplace_merchant_product_categories
      where id=p_category_id and merchant_id=p_merchant_id
  ) then raise exception 'No puedes editar una categoría ajena'; end if;
  insert into public.marketplace_merchant_product_categories(id,merchant_id,name)
    values(coalesce(p_category_id,gen_random_uuid()),p_merchant_id,trim(p_name))
  on conflict(id) do update set name=excluded.name,updated_at=now()
  returning * into v_row;
  return to_jsonb(v_row);
end $$;
revoke all on function public.marketplace_merchant_upsert_category(uuid,uuid,text,text) from public,anon;
grant execute on function public.marketplace_merchant_upsert_category(uuid,uuid,text,text) to authenticated;

create or replace function public.marketplace_merchant_upsert_product_v2(
  p_merchant_id uuid,p_product_id uuid,p_category_id uuid,p_name text,
  p_description text,p_price numeric,p_active boolean,p_image_url text,p_channel text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text; v_currency text; v_result public.marketplace_products%rowtype;
begin
  select mu.role into v_role from public.marketplace_merchant_users mu
  join public.account_runtime_bindings b on b.user_id=mu.user_id and b.environment=p_channel
  join public.marketplace_merchants m on m.id=mu.merchant_id and m.active
  where mu.merchant_id=p_merchant_id and mu.user_id=auth.uid() and mu.active;
  if v_role not in ('owner','manager') or p_channel not in ('preview','production') then
    raise exception 'No tienes permisos para productos';
  end if;
  select z.currency_code into v_currency from public.marketplace_merchants m
  join public.service_zones z on z.id=m.zone_id where m.id=p_merchant_id;
  if v_currency is null then raise exception 'Comercio no encontrado'; end if;
  if not exists(select 1 from public.marketplace_merchant_product_categories c
      where c.id=p_category_id and c.merchant_id=p_merchant_id and c.active) then
    raise exception 'Crea o selecciona una categoría antes de guardar productos';
  end if;
  if length(trim(coalesce(p_name,''))) not between 2 and 100
     or length(coalesce(p_description,''))>1500
     or p_price is null or p_price<0 or p_price>10000000
     or (v_currency='CLP' and mod(p_price,1)<>0)
     or length(coalesce(p_image_url,''))>1000 then
    raise exception 'Producto inválido';
  end if;
  if p_product_id is not null and not exists(select 1 from public.marketplace_products
      where id=p_product_id and merchant_id=p_merchant_id) then
    raise exception 'No puedes editar un producto ajeno';
  end if;
  insert into public.marketplace_products(
    id,merchant_id,category_id,name,description,price,currency_code,active,image_url
  ) values(
    coalesce(p_product_id,gen_random_uuid()),p_merchant_id,p_category_id,
    trim(p_name),coalesce(p_description,''),p_price,v_currency,
    coalesce(p_active,true),nullif(trim(coalesce(p_image_url,'')),'')
  ) on conflict(id) do update set
    category_id=excluded.category_id,name=excluded.name,
    description=excluded.description,price=excluded.price,
    active=excluded.active,image_url=excluded.image_url,updated_at=now()
  returning * into v_result;
  return jsonb_build_object('id',v_result.id,'name',v_result.name,
    'category_id',v_result.category_id,'price',v_result.price,'active',v_result.active);
end $$;
revoke all on function public.marketplace_merchant_upsert_product_v2(
  uuid,uuid,uuid,text,text,numeric,boolean,text,text
) from public,anon;
grant execute on function public.marketplace_merchant_upsert_product_v2(
  uuid,uuid,uuid,text,text,numeric,boolean,text,text
) to authenticated;

-- Older clients still need a category. They use the merchant's first active
-- category; new clients choose one explicitly through the v2 RPC.
create or replace function public.marketplace_merchant_upsert_product(
  p_merchant_id uuid,p_product_id uuid,p_name text,p_description text,
  p_price numeric,p_active boolean,p_image_url text,p_channel text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_category uuid;
begin
  select id into v_category from public.marketplace_merchant_product_categories
    where merchant_id=p_merchant_id and active order by sort_order,name limit 1;
  if v_category is null then raise exception 'Crea una categoría antes de subir el primer producto'; end if;
  return public.marketplace_merchant_upsert_product_v2(
    p_merchant_id,p_product_id,v_category,p_name,p_description,p_price,
    p_active,p_image_url,p_channel
  );
end $$;
revoke all on function public.marketplace_merchant_upsert_product(
  uuid,uuid,text,text,numeric,boolean,text,text
) from public,anon;
grant execute on function public.marketplace_merchant_upsert_product(
  uuid,uuid,text,text,numeric,boolean,text,text
) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('marketplace-merchant-applications','marketplace-merchant-applications',true,8388608,
  array['image/jpeg','image/png','image/webp']::text[])
on conflict(id) do update set public=true,file_size_limit=8388608,
  allowed_mime_types=array['image/jpeg','image/png','image/webp']::text[];
drop policy if exists marketplace_merchant_application_media_upload
  on storage.objects;
create policy marketplace_merchant_application_media_upload
  on storage.objects for insert to authenticated
  with check (bucket_id='marketplace-merchant-applications'
    and (storage.foldername(name))[1]=(select auth.uid())::text);

create table if not exists public.admin_marketplace_support_sessions (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  merchant_id uuid not null references public.marketplace_merchants(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at timestamptz
);
create index if not exists admin_marketplace_support_session_expiry_idx
  on public.admin_marketplace_support_sessions(admin_user_id,expires_at desc);
alter table public.admin_marketplace_support_sessions enable row level security;
revoke all on public.admin_marketplace_support_sessions from public,anon,authenticated;
create or replace function public.admin_marketplace_support_open(p_merchant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_name text; v_expires timestamptz := now()+interval '20 minutes';
begin
  if not public.is_admin() then raise exception 'Solo Admin puede abrir soporte'; end if;
  select name into v_name from public.marketplace_merchants where id=p_merchant_id;
  if v_name is null then raise exception 'Restaurante no encontrado'; end if;
  insert into public.admin_marketplace_support_sessions(admin_user_id,merchant_id,expires_at)
  values(auth.uid(),p_merchant_id,v_expires) returning id into v_id;
  return jsonb_build_object('session_id',v_id,'merchant_id',p_merchant_id,
    'merchant_name',v_name,'expires_at',v_expires);
end $$;
revoke all on function public.admin_marketplace_support_open(uuid) from public,anon;
grant execute on function public.admin_marketplace_support_open(uuid) to authenticated;

create or replace function public.admin_marketplace_support_state(p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_merchant uuid; v_result jsonb;
begin
  select merchant_id into v_merchant from public.admin_marketplace_support_sessions
  where id=p_session_id and admin_user_id=auth.uid() and closed_at is null and expires_at>now();
  if v_merchant is null or not public.is_admin() then raise exception 'La sesión temporal venció o no está autorizada'; end if;
  select jsonb_build_object(
    'merchant',to_jsonb(m),
    'products',(select coalesce(jsonb_agg(to_jsonb(p) order by p.sort_order,p.name),'[]'::jsonb)
      from public.marketplace_products p where p.merchant_id=m.id),
    'categories',(select coalesce(jsonb_agg(to_jsonb(c) order by c.sort_order,c.name),'[]'::jsonb)
      from public.marketplace_merchant_product_categories c where c.merchant_id=m.id),
    'orders',(select coalesce(jsonb_agg(jsonb_build_object(
      'id',o.id,'status',o.status,'total_amount',o.total_amount,'created_at',o.created_at
    ) order by o.created_at desc),'[]'::jsonb)
      from (select * from public.marketplace_orders where merchant_id=m.id
            order by created_at desc limit 30) o)
  ) into v_result from public.marketplace_merchants m where m.id=v_merchant;
  return v_result;
end $$;
revoke all on function public.admin_marketplace_support_state(uuid) from public,anon;
grant execute on function public.admin_marketplace_support_state(uuid) to authenticated;

create or replace function public.admin_marketplace_support_close(p_session_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Solo Admin puede cerrar soporte'; end if;
  update public.admin_marketplace_support_sessions set closed_at=now()
  where id=p_session_id and admin_user_id=auth.uid() and closed_at is null;
end $$;
revoke all on function public.admin_marketplace_support_close(uuid) from public,anon;
grant execute on function public.admin_marketplace_support_close(uuid) to authenticated;

commit;
