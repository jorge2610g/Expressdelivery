-- Personal coupon wallet for Express Delivery. Existing order pricing,
-- redemptions and provider payments remain the authority.
-- Preview/Production scope is bound to the authenticated account on server.
create table if not exists public.delivery_saved_coupons (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  coupon_id uuid not null references public.marketplace_coupons(id) on delete cascade,
  channel text not null check (channel in ('preview','production')),
  created_at timestamptz not null default now(),
  unique (user_id, coupon_id, channel)
);
create index if not exists delivery_saved_coupons_user_channel_idx
  on public.delivery_saved_coupons(user_id,channel,created_at desc);
alter table public.delivery_saved_coupons enable row level security;
revoke all on public.delivery_saved_coupons from public, anon, authenticated;
grant select on public.delivery_saved_coupons to authenticated;
drop policy if exists delivery_saved_coupons_select_own on public.delivery_saved_coupons;
create policy delivery_saved_coupons_select_own
  on public.delivery_saved_coupons for select to authenticated
  using (user_id=auth.uid());

create or replace function public.delivery_save_coupon(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text;
  v_zone uuid;
  v_country text;
  v_coupon public.marketplace_coupons%rowtype;
  v_total integer;
  v_used integer;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Inicia sesión para guardar cupones';
  end if;
  if length(trim(coalesce(p_code,'')))<3 or length(trim(p_code))>64 then
    raise exception 'Introduce un código de cupón válido';
  end if;
  v_channel:=public.admin_user_runtime_environment(v_uid);
  if v_channel not in ('preview','production') then
    raise exception 'Entorno de cuenta no disponible';
  end if;
  select u.last_zone_id,z.country_code into v_zone,v_country
    from public.users u
    left join public.service_zones z on z.id=u.last_zone_id
    where u.id=v_uid;
  if v_zone is null then
    raise exception 'Selecciona una zona antes de guardar cupones';
  end if;
  select c.* into v_coupon
    from public.marketplace_coupons c
    where lower(c.code)=lower(trim(p_code)) and c.active
      and (c.starts_at is null or c.starts_at<=now())
      and (c.ends_at is null or c.ends_at>now())
      and (c.zone_id is null or c.zone_id=v_zone)
      and (c.country_code is null or c.country_code=v_country)
      and case when v_channel='preview'
               then c.preview_visible else c.production_visible end
    limit 1;
  if not found then
    return jsonb_build_object('ok',false,'message',
      'Este cupón no está disponible en tu zona.');
  end if;
  select count(*)::integer into v_total from public.marketplace_coupon_redemptions r
    where r.coupon_id=v_coupon.id;
  select count(*)::integer into v_used from public.marketplace_coupon_redemptions r
    where r.coupon_id=v_coupon.id and r.user_id=v_uid;
  if (v_coupon.usage_limit is not null and v_total>=v_coupon.usage_limit)
     or (v_coupon.per_user_limit is not null and v_used>=v_coupon.per_user_limit) then
    return jsonb_build_object('ok',false,'message','Este cupón ya fue utilizado o se agotó.');
  end if;
  insert into public.delivery_saved_coupons(user_id,coupon_id,channel)
    values(v_uid,v_coupon.id,v_channel)
    on conflict (user_id,coupon_id,channel) do nothing;
  return jsonb_build_object('ok',true,'code',upper(v_coupon.code),
    'message','Cupón guardado. Puedes utilizarlo al pagar tu pedido.');
end; $$;
revoke all on function public.delivery_save_coupon(text) from public,anon;
grant execute on function public.delivery_save_coupon(text) to authenticated;

create or replace function public.delivery_my_coupons()
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare
  v_uid uuid:=auth.uid();
  v_channel text;
  v_zone uuid;
  v_country text;
  v_result jsonb;
begin
  if v_uid is null or not public.is_account_active() then
    raise exception 'Inicia sesión para ver tus cupones';
  end if;
  v_channel:=public.admin_user_runtime_environment(v_uid);
  if v_channel not in ('preview','production') then
    raise exception 'Entorno de cuenta no disponible';
  end if;
  select u.last_zone_id,z.country_code into v_zone,v_country
    from public.users u left join public.service_zones z on z.id=u.last_zone_id
    where u.id=v_uid;
  select coalesce(jsonb_agg(jsonb_build_object(
      'code',upper(c.code),'title',c.title,'description',c.description,
      'discount_type',c.discount_type,'discount_value',c.discount_value,
      'min_order',c.min_order,'max_discount',c.max_discount,
      'ends_at',c.ends_at,'created_at',s.created_at,
      'status',case
        when (select count(*) from public.marketplace_coupon_redemptions r
              where r.coupon_id=c.id and r.user_id=v_uid)>=coalesce(c.per_user_limit,2147483647)
             then 'used'
        when not c.active or (c.ends_at is not null and c.ends_at<=now())
             then 'expired'
        when c.starts_at is not null and c.starts_at>now() then 'unavailable'
        when (c.zone_id is not null and c.zone_id is distinct from v_zone)
             or (c.country_code is not null and c.country_code is distinct from v_country)
             then 'other_zone'
        when (case when v_channel='preview' then not c.preview_visible
                   else not c.production_visible end)
             then 'unavailable'
        when c.usage_limit is not null and
             (select count(*) from public.marketplace_coupon_redemptions r
              where r.coupon_id=c.id)>=c.usage_limit then 'expired'
        else 'available'
      end
    ) order by s.created_at desc), '[]'::jsonb)
    into v_result
    from public.delivery_saved_coupons s
    join public.marketplace_coupons c on c.id=s.coupon_id
    where s.user_id=v_uid and s.channel=v_channel;
  return coalesce(v_result,'[]'::jsonb);
end; $$;
revoke all on function public.delivery_my_coupons() from public,anon;
grant execute on function public.delivery_my_coupons() to authenticated;
