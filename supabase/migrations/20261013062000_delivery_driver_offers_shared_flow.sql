-- Driver offers for parcel requests; same commercial acceptance flow as Taxi.
-- An offer never changes a marketplace/prepaid order amount.
create table if not exists public.delivery_driver_offers(
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.delivery_requests(id) on delete cascade,
  driver_id uuid not null references public.driver_profiles(id) on delete cascade,
  channel text not null check(channel in ('preview','production')),
  proposed_fare numeric not null check(proposed_fare > 0),
  eta_minutes integer not null default 5 check(eta_minutes between 1 and 120),
  status text not null default 'pending' check(status in ('pending','accepted','declined','expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+ interval '30 seconds'),
  unique(delivery_id,driver_id)
);
create index if not exists idx_delivery_driver_offers_delivery
on public.delivery_driver_offers(delivery_id,status,created_at desc);
alter table public.delivery_driver_offers enable row level security;
revoke all on public.delivery_driver_offers from anon,authenticated;
grant select on public.delivery_driver_offers to authenticated;
drop policy if exists delivery_offers_participants on public.delivery_driver_offers;
create policy delivery_offers_participants on public.delivery_driver_offers
for select to authenticated using (
  driver_id=auth.uid()
  or exists(select 1 from public.delivery_requests d
    where d.id=delivery_id and d.customer_id=auth.uid() and d.channel=channel)
);

create or replace function public.create_delivery_driver_offer(
  p_delivery_id uuid,p_fare numeric,p_eta_minutes integer,p_channel text
) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_delivery public.delivery_requests%rowtype;
  v_id uuid;
  v_expires timestamptz;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'Sesión no válida'; end if;
  select * into v_delivery from public.delivery_requests
  where id=p_delivery_id and channel=v_channel and status='searching'
    and courier_id is null for update;
  if not found then raise exception 'El envío ya no está disponible'; end if;
  if not exists(select 1 from public.driver_profiles dp
    where dp.id=v_uid and dp.approval_status='approved' and dp.online_status='online'
      and dp.zone_id is not null) then raise exception 'Conductor no disponible'; end if;
  if not public.driver_work_permission_allowed(
      v_uid,case when v_delivery.marketplace_order_id is null then 'parcel' else 'market' end,v_channel)
    or not public.driver_delivery_zone_enabled(v_uid,v_channel)
    or not public.same_operational_scope(v_delivery.customer_id,v_uid)
    or not public.delivery_request_matches_driver_zone(
      v_delivery.pickup_latitude,v_delivery.pickup_longitude,
      v_delivery.marketplace_order_id,v_delivery.customer_id,v_uid) then
    raise exception 'No tienes autorización para este envío';
  end if;
  if exists(select 1 from public.trips t where t.driver_id=v_uid
              and t.status not in ('completed','cancelled'))
    or exists(select 1 from public.delivery_requests d where d.courier_id=v_uid
              and d.status not in ('delivered','cancelled')) then
    raise exception 'Ya tienes un servicio activo';
  end if;
  if p_fare is null or p_fare <= 0 or p_fare > 100000000 then
    raise exception 'Monto inválido';
  end if;
  if v_delivery.marketplace_order_id is not null
    and p_fare <> v_delivery.proposed_fare then
    raise exception 'Los pedidos de comercios tienen tarifa fija';
  end if;
  if p_eta_minutes is null or p_eta_minutes not between 1 and 120 then
    raise exception 'Tiempo estimado inválido';
  end if;
  v_expires:=now()+interval '30 seconds';
  insert into public.delivery_driver_offers(
    delivery_id,driver_id,channel,proposed_fare,eta_minutes,status,expires_at
  ) values (p_delivery_id,v_uid,v_channel,p_fare,p_eta_minutes,'pending',v_expires)
  on conflict (delivery_id,driver_id) do update
    set proposed_fare=excluded.proposed_fare,eta_minutes=excluded.eta_minutes,
        status='pending',created_at=now(),expires_at=excluded.expires_at
  returning id into v_id;
  return jsonb_build_object('id',v_id,'expires_at',v_expires,
     'status','pending','delivery_id',p_delivery_id);
end; $$;
revoke all on function public.create_delivery_driver_offer(uuid,numeric,integer,text) from public,anon;
grant execute on function public.create_delivery_driver_offer(uuid,numeric,integer,text) to authenticated;

create or replace function public.my_delivery_driver_offers(
  p_delivery_id uuid,p_channel text
) returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_uid uuid:=auth.uid(); v_channel text:=public.normalize_runtime_channel(p_channel);
begin
  if not exists(select 1 from public.delivery_requests d where
    d.id=p_delivery_id and d.customer_id=v_uid and d.channel=v_channel) then
    raise exception 'No puedes ver las ofertas de este envío';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
   'id',o.id,'driver_id',o.driver_id,'proposed_fare',o.proposed_fare,
   'eta_minutes',o.eta_minutes,'status',o.status,'expires_at',o.expires_at,
   'created_at',o.created_at) order by o.created_at desc),'[]'::jsonb)
   from public.delivery_driver_offers o where o.delivery_id=p_delivery_id
      and o.channel=v_channel and o.status='pending' and o.expires_at>now());
end; $$;
revoke all on function public.my_delivery_driver_offers(uuid,text) from public,anon;
grant execute on function public.my_delivery_driver_offers(uuid,text) to authenticated;

-- The existing claim guard already checks that the driver is approved,
-- online, in the same zone/runtime and has no active work. Let the customer
-- accept only an offer that this secure RPC marked as accepted.
create or replace function public.guard_driver_delivery_claim_permissions()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_service text; v_channel text;
begin
  if new.courier_id is null or old.courier_id is not null
     or new.courier_id is not distinct from old.courier_id then return new; end if;
  v_channel:=public.admin_user_runtime_environment(new.courier_id);
  v_service:=case when new.marketplace_order_id is null then 'parcel' else 'market' end;
  if v_channel is distinct from new.channel then raise exception 'Entorno incorrecto'; end if;
  if auth.uid() is distinct from new.courier_id and not public.is_admin()
     and not (
       auth.uid() = new.customer_id
       and exists(select 1 from public.delivery_driver_offers o
          where o.delivery_id=new.id and o.driver_id=new.courier_id
           and o.channel=new.channel and o.status='accepted'
           and o.expires_at>now() and o.proposed_fare=new.proposed_fare)
     ) then raise exception 'No puedes asignar este envío'; end if;
  if not public.driver_work_permission_allowed(new.courier_id,v_service,v_channel)
     or not public.driver_delivery_zone_enabled(new.courier_id,v_channel) then
    raise exception 'Servicio no aprobado para el conductor'; end if;
  if not exists(select 1 from public.driver_profiles dp where
     dp.id=new.courier_id and dp.approval_status='approved'
     and dp.online_status='online' and dp.zone_id is not null
     and public.delivery_request_matches_driver_zone(new.pickup_latitude,new.pickup_longitude,
         new.marketplace_order_id,new.customer_id,new.courier_id)) then
     raise exception 'Conductor no está disponible en esa zona'; end if;
  if exists(select 1 from public.trips t where t.driver_id=new.courier_id
     and t.status not in ('completed','cancelled'))
     or exists(select 1 from public.delivery_requests d where d.courier_id=new.courier_id
       and d.id<>new.id and d.status not in ('delivered','cancelled')) then
     raise exception 'Conductor ya tiene un trabajo activo'; end if;
  return new;
end; $$;

create or replace function public.accept_delivery_driver_offer(
  p_offer_id uuid,p_channel text
) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid:=auth.uid();
  v_channel text:=public.normalize_runtime_channel(p_channel);
  v_offer public.delivery_driver_offers%rowtype;
  v_delivery public.delivery_requests%rowtype;
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  select * into v_offer from public.delivery_driver_offers
    where id=p_offer_id and channel=v_channel and status='pending'
      and expires_at>now() for update;
  if not found then raise exception 'Oferta vencida o no disponible'; end if;
  select * into v_delivery from public.delivery_requests
    where id=v_offer.delivery_id and customer_id=v_uid and channel=v_channel
       and status='searching' and courier_id is null for update;
  if not found then raise exception 'Este envío ya no está disponible'; end if;
  if v_delivery.marketplace_order_id is not null and
      v_offer.proposed_fare <> v_delivery.proposed_fare then
    raise exception 'No se puede modificar la tarifa del pedido';
  end if;
  update public.delivery_driver_offers set status='accepted' where id=v_offer.id;
  update public.delivery_requests
   set courier_id=v_offer.driver_id,status='accepted',
       proposed_fare=v_offer.proposed_fare,updated_at=now()
   where id=v_delivery.id and status='searching' and courier_id is null;
  if not found then raise exception 'El envío ya fue asignado'; end if;
  update public.delivery_driver_offers set status='declined'
   where delivery_id=v_delivery.id and id<>v_offer.id and status='pending';
  insert into public.delivery_status_history(delivery_id,status,changed_by)
  values(v_delivery.id,'accepted',v_uid);
  update public.driver_profiles set online_status='busy',updated_at=now()
   where id=v_offer.driver_id;
  if v_delivery.marketplace_order_id is not null then
    update public.marketplace_orders set assigned_driver_id=v_offer.driver_id,
       status='driver_assigned',updated_at=now()
     where id=v_delivery.marketplace_order_id;
  end if;
  insert into public.notifications(user_id,title,body,type)
   values(v_offer.driver_id,'Oferta aceptada','El cliente confirmó tu servicio de envío.','delivery_assigned');
  return jsonb_build_object('delivery_id',v_delivery.id,'courier_id',v_offer.driver_id,'status','accepted');
end; $$;
revoke all on function public.accept_delivery_driver_offer(uuid,text) from public,anon;
grant execute on function public.accept_delivery_driver_offer(uuid,text) to authenticated;
