-- Marketplace Express + driver priority controls.
-- Preview and Production are independently enabled from Adminexpress.

create table if not exists public.marketplace_settings (
  id boolean primary key default true check (id = true),
  preview_enabled boolean not null default true,
  production_enabled boolean not null default false,
  module_name text not null default 'Express Market',
  search_placeholder text not null default 'Locales, productos y promociones',
  hero_title text not null default 'Todo lo que necesitas, en Express',
  hero_subtitle text not null default 'Comida, mercados, tiendas y más.',
  updated_at timestamptz not null default now()
);

insert into public.marketplace_settings(id)
values(true)
on conflict (id) do nothing;

create table if not exists public.marketplace_categories (
  id uuid primary key default gen_random_uuid(),
  category_key text not null unique,
  name text not null,
  icon_key text not null default 'storefront',
  active boolean not null default true,
  preview_visible boolean not null default true,
  production_visible boolean not null default false,
  sort_order integer not null default 100,
  updated_at timestamptz not null default now()
);

insert into public.marketplace_categories(
  category_key,name,icon_key,sort_order,preview_visible,production_visible
)
values
  ('restaurants','Restaurantes','restaurant',10,true,false),
  ('markets','Mercados','shopping_basket',20,true,false),
  ('cafe','Café & Tortas','local_cafe',30,true,false),
  ('butchers','Carnicerías','set_meal',40,true,false),
  ('gifts','Tiendas y regalos','shopping_bag',50,true,false),
  ('pets','Mascotas','pets',60,true,false)
on conflict (category_key) do nothing;

create table if not exists public.marketplace_banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subtitle text,
  cta_label text,
  style_key text not null default 'blue',
  active boolean not null default true,
  preview_visible boolean not null default true,
  production_visible boolean not null default false,
  sort_order integer not null default 100,
  updated_at timestamptz not null default now()
);

insert into public.marketplace_banners(
  title,subtitle,cta_label,style_key,sort_order,preview_visible,production_visible
)
select *
from (
  values
    ('Descubre Express Market','Tus comercios favoritos en un solo lugar.','Explorar','blue',10,true,false),
    ('Promos Express','Configura descuentos y campañas desde el panel.','Ver promociones','yellow',20,true,false)
) as seed(title,subtitle,cta_label,style_key,sort_order,preview_visible,production_visible)
where not exists(select 1 from public.marketplace_banners);

create table if not exists public.marketplace_merchants (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid references public.service_zones(id) on delete set null,
  category_key text references public.marketplace_categories(category_key) on update cascade on delete restrict,
  name text not null,
  description text,
  image_url text,
  active boolean not null default true,
  preview_visible boolean not null default true,
  production_visible boolean not null default false,
  rating numeric(3,2) not null default 5.0,
  eta_min_minutes integer not null default 15,
  eta_max_minutes integer not null default 40,
  delivery_fee numeric(12,2) not null default 0,
  sort_order integer not null default 100,
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_products (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.marketplace_merchants(id) on delete cascade,
  name text not null,
  description text,
  price numeric(12,2) not null check (price >= 0),
  currency_code text not null default 'CLP',
  image_url text,
  active boolean not null default true,
  sort_order integer not null default 100,
  updated_at timestamptz not null default now()
);

alter table public.marketplace_settings enable row level security;
alter table public.marketplace_categories enable row level security;
alter table public.marketplace_banners enable row level security;
alter table public.marketplace_merchants enable row level security;
alter table public.marketplace_products enable row level security;

create or replace function public.marketplace_home(
  p_channel text default 'production',
  p_lat numeric default null,
  p_lng numeric default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_preview boolean := lower(coalesce(p_channel,'production')) = 'preview';
  v_enabled boolean;
  v_settings jsonb;
  v_categories jsonb;
  v_banners jsonb;
  v_merchants jsonb;
  v_zone_id uuid;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if p_lat is not null and p_lng is not null then
    v_zone_id := public.service_zone_id_for_point(p_lat,p_lng);
  else
    select last_zone_id into v_zone_id from public.users where id=v_uid;
  end if;

  select
    case when v_preview then preview_enabled else production_enabled end,
    jsonb_build_object(
      'module_name',module_name,
      'search_placeholder',search_placeholder,
      'hero_title',hero_title,
      'hero_subtitle',hero_subtitle,
      'preview_enabled',preview_enabled,
      'production_enabled',production_enabled
    )
  into v_enabled,v_settings
  from public.marketplace_settings
  where id=true;

  if coalesce(v_enabled,false) is false then
    return jsonb_build_object(
      'enabled',false,
      'channel',case when v_preview then 'preview' else 'production' end,
      'settings',coalesce(v_settings,'{}'::jsonb),
      'categories','[]'::jsonb,
      'banners','[]'::jsonb,
      'merchants','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb)
  into v_categories
  from (
    select id,category_key,name,icon_key,sort_order
    from public.marketplace_categories
    where active=true
      and case when v_preview then preview_visible else production_visible end
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order),'[]'::jsonb)
  into v_banners
  from (
    select id,title,subtitle,cta_label,style_key,sort_order
    from public.marketplace_banners
    where active=true
      and case when v_preview then preview_visible else production_visible end
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb)
  into v_merchants
  from (
    select
      m.id,m.category_key,m.name,m.description,m.image_url,m.rating,
      m.eta_min_minutes,m.eta_max_minutes,m.delivery_fee,m.sort_order,
      z.currency_code
    from public.marketplace_merchants m
    left join public.service_zones z on z.id=m.zone_id
    where m.active=true
      and (m.zone_id is null or v_zone_id is null or m.zone_id=v_zone_id)
      and case when v_preview then m.preview_visible else m.production_visible end
  ) x;

  return jsonb_build_object(
    'enabled',true,
    'channel',case when v_preview then 'preview' else 'production' end,
    'settings',coalesce(v_settings,'{}'::jsonb),
    'categories',coalesce(v_categories,'[]'::jsonb),
    'banners',coalesce(v_banners,'[]'::jsonb),
    'merchants',coalesce(v_merchants,'[]'::jsonb)
  );
end;
$function$;

create or replace function public.admin_marketplace_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'settings',(
      select to_jsonb(s) - 'id'
      from public.marketplace_settings s
      where id=true
    ),
    'categories',(
      select coalesce(jsonb_agg(to_jsonb(c) order by c.sort_order,c.name),'[]'::jsonb)
      from public.marketplace_categories c
    ),
    'banners',(
      select coalesce(jsonb_agg(to_jsonb(b) order by b.sort_order),'[]'::jsonb)
      from public.marketplace_banners b
    ),
    'merchants',(
      select coalesce(jsonb_agg(to_jsonb(m) order by m.sort_order,m.name),'[]'::jsonb)
      from public.marketplace_merchants m
    )
  );
end;
$function$;

create or replace function public.admin_marketplace_update_settings(
  p_preview_enabled boolean,
  p_production_enabled boolean,
  p_module_name text,
  p_search_placeholder text,
  p_hero_title text,
  p_hero_subtitle text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  update public.marketplace_settings
  set preview_enabled=coalesce(p_preview_enabled,false),
      production_enabled=coalesce(p_production_enabled,false),
      module_name=coalesce(nullif(trim(p_module_name),''),'Express Market'),
      search_placeholder=coalesce(nullif(trim(p_search_placeholder),''),'Locales, productos y promociones'),
      hero_title=coalesce(nullif(trim(p_hero_title),''),'Todo lo que necesitas, en Express'),
      hero_subtitle=coalesce(nullif(trim(p_hero_subtitle),''),'Comida, mercados, tiendas y más.'),
      updated_at=now()
  where id=true;

  perform public.admin_log_action(
    'update','marketplace_settings','global',
    jsonb_build_object(
      'preview_enabled',p_preview_enabled,
      'production_enabled',p_production_enabled
    )
  );

  return public.admin_marketplace_state();
end;
$function$;

create or replace function public.admin_marketplace_upsert_category(
  p_id uuid,
  p_category_key text,
  p_name text,
  p_icon_key text,
  p_active boolean,
  p_preview_visible boolean,
  p_production_visible boolean,
  p_sort_order integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  if p_id is null then
    insert into public.marketplace_categories(
      category_key,name,icon_key,active,preview_visible,production_visible,sort_order,updated_at
    ) values(
      lower(trim(p_category_key)),
      trim(p_name),
      coalesce(nullif(trim(p_icon_key),''),'storefront'),
      coalesce(p_active,true),
      coalesce(p_preview_visible,true),
      coalesce(p_production_visible,false),
      coalesce(p_sort_order,100),
      now()
    ) returning id into v_id;
  else
    update public.marketplace_categories
    set category_key=lower(trim(p_category_key)),
        name=trim(p_name),
        icon_key=coalesce(nullif(trim(p_icon_key),''),'storefront'),
        active=coalesce(p_active,true),
        preview_visible=coalesce(p_preview_visible,true),
        production_visible=coalesce(p_production_visible,false),
        sort_order=coalesce(p_sort_order,100),
        updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;

  return v_id;
end;
$function$;

create or replace function public.admin_marketplace_upsert_banner(
  p_id uuid,
  p_title text,
  p_subtitle text,
  p_cta_label text,
  p_style_key text,
  p_active boolean,
  p_preview_visible boolean,
  p_production_visible boolean,
  p_sort_order integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  if p_id is null then
    insert into public.marketplace_banners(
      title,subtitle,cta_label,style_key,active,preview_visible,production_visible,sort_order,updated_at
    ) values(
      trim(p_title),p_subtitle,p_cta_label,coalesce(nullif(trim(p_style_key),''),'blue'),
      coalesce(p_active,true),coalesce(p_preview_visible,true),
      coalesce(p_production_visible,false),coalesce(p_sort_order,100),now()
    ) returning id into v_id;
  else
    update public.marketplace_banners
    set title=trim(p_title),
        subtitle=p_subtitle,
        cta_label=p_cta_label,
        style_key=coalesce(nullif(trim(p_style_key),''),'blue'),
        active=coalesce(p_active,true),
        preview_visible=coalesce(p_preview_visible,true),
        production_visible=coalesce(p_production_visible,false),
        sort_order=coalesce(p_sort_order,100),
        updated_at=now()
    where id=p_id
    returning id into v_id;
  end if;

  return v_id;
end;
$function$;

create table if not exists public.driver_priority_settings (
  id boolean primary key default true check (id = true),
  preview_enabled boolean not null default true,
  production_enabled boolean not null default false,
  preview_enforcement_enabled boolean not null default true,
  production_enforcement_enabled boolean not null default false,
  high_min_score numeric(5,2) not null default 80,
  medium_min_score numeric(5,2) not null default 55,
  rating_weight numeric(5,2) not null default 35,
  reviews_weight numeric(5,2) not null default 25,
  experience_weight numeric(5,2) not null default 20,
  frequency_weight numeric(5,2) not null default 20,
  review_target integer not null default 20,
  experience_trip_target integer not null default 100,
  frequency_30d_target integer not null default 30,
  updated_at timestamptz not null default now()
);

insert into public.driver_priority_settings(id)
values(true)
on conflict(id) do nothing;

alter table public.driver_priority_settings enable row level security;

create or replace function public.driver_priority_summary_for(
  p_driver_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_rating numeric := 0;
  v_review_count integer := 0;
  v_completed integer := 0;
  v_recent integer := 0;
  v_rating_score numeric := 0;
  v_reviews_score numeric := 0;
  v_experience_score numeric := 0;
  v_frequency_score numeric := 0;
  v_total numeric := 0;
  v_level text := 'low';
  v_s public.driver_priority_settings%rowtype;
begin
  select * into v_s from public.driver_priority_settings where id=true;

  select coalesce(round(avg(r.score)::numeric,2),0),count(*)::integer
  into v_rating,v_review_count
  from public.ratings r
  where r.to_user_id=p_driver_id;

  select count(*)::integer into v_completed
  from public.trips t
  where t.driver_id=p_driver_id and t.status='completed';

  select count(*)::integer into v_recent
  from public.trips t
  where t.driver_id=p_driver_id
    and t.status='completed'
    and coalesce(t.completed_at,t.created_at) >= now() - interval '30 days';

  v_rating_score := case
    when v_rating <= 0 then 50
    else least(100,greatest(0,((v_rating - 1) / 4) * 100))
  end;

  v_reviews_score := least(
    100,
    greatest(
      0,
      v_rating_score * least(1, v_review_count::numeric / greatest(v_s.review_target,1))
      + 50 * (1 - least(1, v_review_count::numeric / greatest(v_s.review_target,1)))
    )
  );

  v_experience_score := least(
    100,
    greatest(0, v_completed::numeric / greatest(v_s.experience_trip_target,1) * 100)
  );

  v_frequency_score := least(
    100,
    greatest(0, v_recent::numeric / greatest(v_s.frequency_30d_target,1) * 100)
  );

  v_total := round(
    (
      v_rating_score * v_s.rating_weight +
      v_reviews_score * v_s.reviews_weight +
      v_experience_score * v_s.experience_weight +
      v_frequency_score * v_s.frequency_weight
    ) / greatest(
      v_s.rating_weight + v_s.reviews_weight +
      v_s.experience_weight + v_s.frequency_weight,
      1
    ),
    2
  );

  v_level := case
    when v_total >= v_s.high_min_score then 'high'
    when v_total >= v_s.medium_min_score then 'medium'
    else 'low'
  end;

  return jsonb_build_object(
    'driver_id',p_driver_id,
    'level',v_level,
    'score',v_total,
    'average_rating',v_rating,
    'review_count',v_review_count,
    'completed_trips',v_completed,
    'recent_trips_30d',v_recent,
    'metrics',jsonb_build_object(
      'rating',round(v_rating_score,2),
      'reviews',round(v_reviews_score,2),
      'experience',round(v_experience_score,2),
      'frequency',round(v_frequency_score,2)
    )
  );
end;
$function$;

create or replace function public.my_driver_priority_summary(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_preview boolean := lower(coalesce(p_channel,'production'))='preview';
  v_enabled boolean;
  v_enforcement boolean;
  v_summary jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  if not exists(select 1 from public.driver_profiles where id=v_uid) then
    return jsonb_build_object('enabled',false,'reason','not_driver');
  end if;

  select
    case when v_preview then preview_enabled else production_enabled end,
    case when v_preview then preview_enforcement_enabled else production_enforcement_enabled end
  into v_enabled,v_enforcement
  from public.driver_priority_settings
  where id=true;

  v_summary := public.driver_priority_summary_for(v_uid);

  return coalesce(v_summary,'{}'::jsonb) || jsonb_build_object(
    'enabled',coalesce(v_enabled,false),
    'enforcement_enabled',coalesce(v_enforcement,false),
    'channel',case when v_preview then 'preview' else 'production' end
  );
end;
$function$;

create or replace function public.available_ride_requests_for_driver_v2(
  p_channel text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_preview boolean := lower(coalesce(p_channel,'production'))='preview';
  v_enforcement boolean := false;
  v_priority jsonb;
  v_level text := 'medium';
  v_base jsonb;
  v_lat numeric;
  v_lng numeric;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'No autorizado';
  end if;

  select
    case when v_preview then preview_enforcement_enabled else production_enforcement_enabled end
  into v_enforcement
  from public.driver_priority_settings
  where id=true;

  v_base := public.available_ride_requests_for_driver();

  if coalesce(v_enforcement,false) is false then
    return v_base;
  end if;

  v_priority := public.driver_priority_summary_for(v_uid);
  v_level := coalesce(v_priority->>'level','medium');

  select latitude,longitude into v_lat,v_lng
  from public.driver_profiles where id=v_uid;

  select coalesce(jsonb_agg(x.payload order by x.rank_a,x.rank_b,x.rank_c,x.created_at),'[]'::jsonb)
  into v_result
  from (
    select
      e as payload,
      coalesce((e->>'created_at')::timestamptz,now()) as created_at,
      case
        when v_level='high' then coalesce(
          public.geo_distance_km(
            v_lat,v_lng,
            nullif(e->>'pickup_latitude','')::numeric,
            nullif(e->>'pickup_longitude','')::numeric
          ),99999)
        when v_level='medium' then coalesce(
          public.geo_distance_km(
            v_lat,v_lng,
            nullif(e->>'pickup_latitude','')::numeric,
            nullif(e->>'pickup_longitude','')::numeric
          ),99999)
        else -coalesce(
          public.geo_distance_km(
            v_lat,v_lng,
            nullif(e->>'pickup_latitude','')::numeric,
            nullif(e->>'pickup_longitude','')::numeric
          ),0)
      end as rank_a,
      case
        when v_level='low' then coalesce(pr.passenger_rating,0)
        else -coalesce(pr.passenger_rating,5)
      end as rank_b,
      case
        when v_level='low' then coalesce(
          nullif(e->>'proposed_fare','')::numeric /
          nullif(nullif(e->>'route_distance_km','')::numeric,0),
          0
        )
        else -coalesce(
          nullif(e->>'proposed_fare','')::numeric /
          nullif(nullif(e->>'route_distance_km','')::numeric,0),
          0
        )
      end as rank_c
    from jsonb_array_elements(coalesce(v_base,'[]'::jsonb)) e
    left join lateral (
      select round(avg(r.score)::numeric,2) as passenger_rating
      from public.ratings r
      where r.to_user_id = nullif(e->>'passenger_id','')::uuid
    ) pr on true
  ) x;

  return coalesce(v_result,'[]'::jsonb);
end;
$function$;

create or replace function public.admin_driver_priority_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'settings',(
      select to_jsonb(s)-'id'
      from public.driver_priority_settings s
      where id=true
    ),
    'drivers',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id',dp.id,
            'name',u.full_name,
            'rating',dp.rating,
            'completed_trips',dp.completed_trips,
            'priority',public.driver_priority_summary_for(dp.id)
          )
          order by (public.driver_priority_summary_for(dp.id)->>'score')::numeric desc
        ),
        '[]'::jsonb
      )
      from public.driver_profiles dp
      join public.users u on u.id=dp.id
      where dp.approval_status='approved'
    )
  );
end;
$function$;

create or replace function public.admin_update_driver_priority_settings(
  p_preview_enabled boolean,
  p_production_enabled boolean,
  p_preview_enforcement_enabled boolean,
  p_production_enforcement_enabled boolean,
  p_high_min_score numeric,
  p_medium_min_score numeric,
  p_rating_weight numeric,
  p_reviews_weight numeric,
  p_experience_weight numeric,
  p_frequency_weight numeric,
  p_review_target integer,
  p_experience_trip_target integer,
  p_frequency_30d_target integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;

  if p_high_min_score <= p_medium_min_score then
    raise exception 'El umbral Alta debe ser mayor que el umbral Media';
  end if;

  if coalesce(p_rating_weight,0)+coalesce(p_reviews_weight,0)+
     coalesce(p_experience_weight,0)+coalesce(p_frequency_weight,0) <= 0 then
    raise exception 'Los pesos deben sumar más de cero';
  end if;

  update public.driver_priority_settings
  set preview_enabled=coalesce(p_preview_enabled,false),
      production_enabled=coalesce(p_production_enabled,false),
      preview_enforcement_enabled=coalesce(p_preview_enforcement_enabled,false),
      production_enforcement_enabled=coalesce(p_production_enforcement_enabled,false),
      high_min_score=least(100,greatest(0,p_high_min_score)),
      medium_min_score=least(100,greatest(0,p_medium_min_score)),
      rating_weight=greatest(0,p_rating_weight),
      reviews_weight=greatest(0,p_reviews_weight),
      experience_weight=greatest(0,p_experience_weight),
      frequency_weight=greatest(0,p_frequency_weight),
      review_target=greatest(1,p_review_target),
      experience_trip_target=greatest(1,p_experience_trip_target),
      frequency_30d_target=greatest(1,p_frequency_30d_target),
      updated_at=now()
  where id=true;

  perform public.admin_log_action(
    'update','driver_priority_settings','global',
    jsonb_build_object(
      'preview_enabled',p_preview_enabled,
      'production_enabled',p_production_enabled,
      'preview_enforcement_enabled',p_preview_enforcement_enabled,
      'production_enforcement_enabled',p_production_enforcement_enabled
    )
  );

  return public.admin_driver_priority_state();
end;
$function$;

revoke all on function public.marketplace_home(text,numeric,numeric) from public, anon;
revoke all on function public.admin_marketplace_state() from public, anon;
revoke all on function public.admin_marketplace_update_settings(boolean,boolean,text,text,text,text) from public, anon;
revoke all on function public.admin_marketplace_upsert_category(uuid,text,text,text,boolean,boolean,boolean,integer) from public, anon;
revoke all on function public.admin_marketplace_upsert_banner(uuid,text,text,text,text,boolean,boolean,boolean,integer) from public, anon;
revoke all on function public.driver_priority_summary_for(uuid) from public, anon, authenticated;
revoke all on function public.my_driver_priority_summary(text) from public, anon;
revoke all on function public.available_ride_requests_for_driver_v2(text) from public, anon;
revoke all on function public.admin_driver_priority_state() from public, anon;
revoke all on function public.admin_update_driver_priority_settings(boolean,boolean,boolean,boolean,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer) from public, anon;

grant execute on function public.marketplace_home(text,numeric,numeric) to authenticated;
grant execute on function public.admin_marketplace_state() to authenticated;
grant execute on function public.admin_marketplace_update_settings(boolean,boolean,text,text,text,text) to authenticated;
grant execute on function public.admin_marketplace_upsert_category(uuid,text,text,text,boolean,boolean,boolean,integer) to authenticated;
grant execute on function public.admin_marketplace_upsert_banner(uuid,text,text,text,text,boolean,boolean,boolean,integer) to authenticated;
grant execute on function public.my_driver_priority_summary(text) to authenticated;
grant execute on function public.available_ride_requests_for_driver_v2(text) to authenticated;
grant execute on function public.admin_driver_priority_state() to authenticated;
grant execute on function public.admin_update_driver_priority_settings(boolean,boolean,boolean,boolean,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer) to authenticated;
