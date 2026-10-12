-- Weekly settlement ledger. Private merchant cut, private Express breakdown.
-- No payment is assumed from the merchant's report: admin review is required.
begin;
create table if not exists public.marketplace_weekly_cuts(
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.marketplace_merchants(id),
 zone_id uuid not null references public.service_zones(id),
 channel text not null check(channel in ('preview','production')),
 week_start date not null,
 week_end date not null,
 amount numeric(14,2) not null check(amount>0),
 currency_code text not null,
 status text not null default 'pending' check(status in
   ('pending','under_review','rejected','paid')),
 reference text,
 receipt_path text,
 payment_method text,
 reported_by uuid references public.users(id),
 reported_at timestamptz,
 reviewed_by uuid references public.users(id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(merchant_id,channel,week_start),
 check(week_end=week_start+7)
);
create table if not exists public.marketplace_weekly_cut_items(
 cut_id uuid not null references public.marketplace_weekly_cuts(id),
 order_id uuid not null unique references public.marketplace_orders(id),
 express_due numeric(14,2) not null check(express_due>0),
 primary key(cut_id,order_id)
);
create index if not exists marketplace_weekly_cuts_scope
on public.marketplace_weekly_cuts(channel,zone_id,week_start desc);
alter table public.marketplace_weekly_cuts enable row level security;
alter table public.marketplace_weekly_cut_items enable row level security;
revoke all on public.marketplace_weekly_cuts,public.marketplace_weekly_cut_items
 from public,anon,authenticated;

-- Runs as a trusted database job. Each order can belong to one cut only.
create or replace function public.marketplace_generate_closed_weekly_cuts()
returns integer language plpgsql security definer set search_path=public as $$
declare r record;v_cut uuid;v_created integer:=0;
begin
 for r in
  select o.merchant_id,o.zone_id,o.channel,
    date_trunc('week',o.completed_at at time zone 'UTC')::date as week_start,
    z.currency_code,sum(f.merchant_owes_express)::numeric(14,2) due
  from public.marketplace_orders o
  join public.marketplace_order_financials f on f.order_id=o.id
  join public.service_zones z on z.id=o.zone_id
  where o.status='delivered' and o.completed_at is not null
    and o.completed_at < date_trunc('week',now() at time zone 'UTC')
    and o.collector='merchant' and f.merchant_owes_express>0
    and not exists(select 1 from public.marketplace_weekly_cut_items ci
      where ci.order_id=o.id)
  group by o.merchant_id,o.zone_id,o.channel,week_start,z.currency_code
 loop
  -- concurrent job executions serialize per merchant/channel/week
  perform pg_advisory_xact_lock(hashtextextended(
    r.merchant_id::text||r.channel||r.week_start::text,0));
  insert into public.marketplace_weekly_cuts(
    merchant_id,zone_id,channel,week_start,week_end,amount,currency_code
  ) values(r.merchant_id,r.zone_id,r.channel,r.week_start,
    r.week_start+7,r.due,r.currency_code)
  on conflict(merchant_id,channel,week_start) do nothing
  returning id into v_cut;
  if v_cut is null then continue; end if;
  insert into public.marketplace_weekly_cut_items(cut_id,order_id,express_due)
  select v_cut,o.id,f.merchant_owes_express
  from public.marketplace_orders o
  join public.marketplace_order_financials f on f.order_id=o.id
  where o.merchant_id=r.merchant_id and o.channel=r.channel
    and o.collector='merchant' and o.status='delivered'
    and o.completed_at>=r.week_start::timestamptz
    and o.completed_at<(r.week_start+7)::timestamptz
    and f.merchant_owes_express>0
    and not exists(select 1 from public.marketplace_weekly_cut_items ci
      where ci.order_id=o.id);
  -- The sum is derived from the immutable item snapshot, never client values.
  update public.marketplace_weekly_cuts
   set amount=(select sum(express_due) from public.marketplace_weekly_cut_items
     where cut_id=v_cut),updated_at=now()
   where id=v_cut;
  v_created:=v_created+1;
 end loop;
 return v_created;
end $$;
revoke all on function public.marketplace_generate_closed_weekly_cuts()
 from public,anon,authenticated;
select cron.schedule('express-marketplace-weekly-cuts','0 5 * * 1',
 'select public.marketplace_generate_closed_weekly_cuts()');

create or replace function public.marketplace_merchant_weekly_cuts(
 p_merchant_id uuid,p_channel text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if auth.uid() is null or p_channel not in ('preview','production') or
 not exists(select 1 from public.marketplace_merchant_users mu
  join public.account_runtime_bindings arb on arb.user_id=mu.user_id
  where mu.merchant_id=p_merchant_id and mu.user_id=auth.uid()
    and mu.active and arb.environment=p_channel) then
  raise exception 'No autorizado'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'week_start',c.week_start,'week_end',c.week_end,
  'status',c.status,'amount',c.amount,'currency_code',c.currency_code,
  'reference',c.reference,'payment_method',c.payment_method,
  'reported_at',c.reported_at,'reviewed_at',c.reviewed_at,
  'orders',(select count(*) from public.marketplace_weekly_cut_items ci
    where ci.cut_id=c.id)
 ) order by c.week_start desc),'[]'::jsonb)
 from public.marketplace_weekly_cuts c
 where c.merchant_id=p_merchant_id and c.channel=p_channel);
end $$;
revoke all on function public.marketplace_merchant_weekly_cuts(uuid,text) from public,anon;
grant execute on function public.marketplace_merchant_weekly_cuts(uuid,text) to authenticated;

create or replace function public.marketplace_report_weekly_cut(
 p_cut_id uuid,p_reference text,p_method text,p_receipt_path text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_cut public.marketplace_weekly_cuts%rowtype;
begin
 select * into v_cut from public.marketplace_weekly_cuts
 where id=p_cut_id for update;
 if v_cut.id is null or auth.uid() is null or not exists(
   select 1 from public.marketplace_merchant_users mu
   join public.account_runtime_bindings arb on arb.user_id=mu.user_id
   where mu.merchant_id=v_cut.merchant_id and mu.user_id=auth.uid()
     and mu.active and arb.environment=v_cut.channel) then
   raise exception 'No autorizado'; end if;
 if v_cut.status not in ('pending','rejected') or
    length(trim(coalesce(p_reference,''))) not between 4 and 150 or
    p_method not in ('transfer','deposit') or
    (p_receipt_path is not null and (
      left(p_receipt_path,length(v_cut.id::text)+1)<>v_cut.id::text||'/'
      or not public.marketplace_weekly_receipt_access(p_receipt_path)
    )) then
   raise exception 'Aviso de pago inválido'; end if;
 update public.marketplace_weekly_cuts
 set status='under_review',reference=trim(p_reference),payment_method=p_method,
    receipt_path=nullif(trim(coalesce(p_receipt_path,'')),''),
    reported_by=auth.uid(),reported_at=now(),reviewed_by=null,reviewed_at=null,
    updated_at=now()
 where id=v_cut.id;
 return jsonb_build_object('id',v_cut.id,'status','under_review');
end $$;
revoke all on function public.marketplace_report_weekly_cut(uuid,text,text,text)
 from public,anon;
grant execute on function public.marketplace_report_weekly_cut(uuid,text,text,text)
 to authenticated;

create or replace function public.admin_marketplace_weekly_cuts(
 p_zone_id uuid,p_channel text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_access jsonb:=public.admin_access_context();
begin
 if auth.uid() is null or not public.is_admin() or
 not public.admin_environment_allowed(p_channel) or
 (v_access->>'zone_id' is not null and
  (v_access->>'zone_id')::uuid<>p_zone_id) then
  raise exception 'No autorizado'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'merchant_id',c.merchant_id,'merchant_name',m.name,
  'week_start',c.week_start,'week_end',c.week_end,
  'status',c.status,'amount',c.amount,'currency_code',c.currency_code,
  'payment_method',c.payment_method,'reference',c.reference,
  'receipt_path',c.receipt_path,
  'reported_at',c.reported_at,'reviewed_at',c.reviewed_at,
  'service_fee',coalesce((select sum(o.customer_service_fee)
    from public.marketplace_weekly_cut_items ci
    join public.marketplace_orders o on o.id=ci.order_id
    where ci.cut_id=c.id),0),
  'delivery_spread',c.amount-coalesce((select sum(o.customer_service_fee)
    from public.marketplace_weekly_cut_items ci
    join public.marketplace_orders o on o.id=ci.order_id
    where ci.cut_id=c.id),0)
 ) order by c.week_start desc,m.name),'[]'::jsonb)
 from public.marketplace_weekly_cuts c
 join public.marketplace_merchants m on m.id=c.merchant_id
 where c.zone_id=p_zone_id and c.channel=p_channel);
end $$;
revoke all on function public.admin_marketplace_weekly_cuts(uuid,text) from public,anon;
grant execute on function public.admin_marketplace_weekly_cuts(uuid,text) to authenticated;

create or replace function public.admin_marketplace_review_weekly_cut(
 p_cut_id uuid,p_approve boolean
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_cut public.marketplace_weekly_cuts%rowtype;
v_access jsonb:=public.admin_access_context();v_total numeric;
begin
 if auth.uid() is null or not public.is_admin()
 or v_access->>'role'<>'super_admin'
 then raise exception 'Solo superadministradores';end if;
 select * into v_cut from public.marketplace_weekly_cuts where id=p_cut_id for update;
 if v_cut.id is null or not public.admin_environment_allowed(v_cut.channel)
 or (v_access->>'zone_id' is not null and
 (v_access->>'zone_id')::uuid<>v_cut.zone_id) then
 raise exception 'No autorizado para esta ciudad';end if;
 if v_cut.status<>'under_review' then
 raise exception 'No hay un pago pendiente de aprobación';end if;
 if p_approve then
   select sum(ci.express_due) into v_total
   from public.marketplace_weekly_cut_items ci
   join public.marketplace_order_financials f on f.order_id=ci.order_id
   where ci.cut_id=v_cut.id
     and f.merchant_owes_express=ci.express_due;
   if coalesce(v_total,0)<>v_cut.amount then
     raise exception 'El saldo original cambió. Requiere conciliación manual';
   end if;
   update public.marketplace_order_financials f
   set merchant_owes_express=0,updated_at=now(),
       settlement_status='partial'
   from public.marketplace_weekly_cut_items ci
   where ci.order_id=f.order_id and ci.cut_id=v_cut.id;
 end if;
 update public.marketplace_weekly_cuts set
   status=case when p_approve then 'paid' else 'rejected' end,
   reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now()
 where id=v_cut.id;
 perform public.admin_log_action('review','marketplace_weekly_cut',v_cut.id::text,
   jsonb_build_object('approved',p_approve,'merchant_id',v_cut.merchant_id,
     'amount',v_cut.amount,'currency',v_cut.currency_code,
     'channel',v_cut.channel));
 return jsonb_build_object('id',v_cut.id,
   'status',case when p_approve then 'paid' else 'rejected' end);
end $$;
revoke all on function public.admin_marketplace_review_weekly_cut(uuid,boolean)
 from public,anon;
grant execute on function public.admin_marketplace_review_weekly_cut(uuid,boolean)
 to authenticated;

create or replace function public.marketplace_weekly_receipt_access(p_path text)
returns boolean language sql stable security definer set search_path=public as $$
 select auth.uid() is not null
 and p_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9_-]+[.](jpeg|jpg|png|webp)$'
 and exists(select 1 from public.marketplace_weekly_cuts c
 join public.account_runtime_bindings arb
   on arb.user_id=auth.uid() and arb.environment=c.channel
 where c.id::text=split_part(p_path,'/',1)
   and (exists(select 1 from public.marketplace_merchant_users mu
     where mu.merchant_id=c.merchant_id and mu.user_id=auth.uid()
     and mu.active)
   or (public.is_admin() and public.admin_environment_allowed(c.channel))));
$$;
revoke all on function public.marketplace_weekly_receipt_access(text)
 from public,anon;
grant execute on function public.marketplace_weekly_receipt_access(text)
 to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('marketplace-weekly-receipts','marketplace-weekly-receipts',
 false,5242880,array['image/jpeg','image/png','image/webp']::text[])
on conflict(id) do nothing;
create policy "marketplace_weekly_receipt_read" on storage.objects
for select to authenticated using(
 bucket_id='marketplace-weekly-receipts' and
 public.marketplace_weekly_receipt_access(name));
create policy "marketplace_weekly_receipt_upload" on storage.objects
for insert to authenticated with check(
 bucket_id='marketplace-weekly-receipts' and
 public.marketplace_weekly_receipt_access(name));
commit;