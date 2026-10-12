-- Private chat files, protected by the actual order participant and runtime.
begin;
create or replace function public.marketplace_chat_can_access(p_object_path text)
returns boolean language sql stable security definer set search_path=public as $$
  select auth.uid() is not null
    and p_object_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9_-]+[.](jpeg|jpg|png|webp)$'
    and exists(
      select 1 from public.marketplace_orders o
      join public.account_runtime_bindings arb on arb.user_id=auth.uid()
        and arb.environment=o.channel
      where o.id::text=split_part(p_object_path,'/',1)
        and (o.customer_id=auth.uid() or exists(
          select 1 from public.marketplace_merchant_users mu
          where mu.merchant_id=o.merchant_id and mu.user_id=auth.uid()
            and mu.active
        ) or (public.is_admin() and public.admin_environment_allowed(o.channel)))
    );
$$;
revoke all on function public.marketplace_chat_can_access(text) from public,anon;
grant execute on function public.marketplace_chat_can_access(text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('marketplace-order-chat','marketplace-order-chat',false,5242880,
array['image/jpeg','image/png','image/webp']::text[])
on conflict(id) do nothing;

create policy "marketplace_chat_participant_read"
on storage.objects for select to authenticated
using(bucket_id='marketplace-order-chat' and public.marketplace_chat_can_access(name));
create policy "marketplace_chat_participant_upload"
on storage.objects for insert to authenticated
with check(bucket_id='marketplace-order-chat' and public.marketplace_chat_can_access(name));

CREATE OR REPLACE FUNCTION public.marketplace_send_order_message(p_order_id uuid, p_body text DEFAULT NULL::text, p_attachment_url text DEFAULT NULL::text, p_message_type text DEFAULT 'text'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_role text;
  v_message public.marketplace_order_messages%rowtype;
begin
  if v_uid is null then raise exception 'No autorizado'; end if;

  select * into v_order
  from public.marketplace_orders
  where id=p_order_id;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if v_order.customer_id=v_uid then
    v_role:='customer';
  elsif public.is_admin() then
    v_role:='admin';
  elsif exists(
    select 1 from public.marketplace_merchant_users mu
    where mu.merchant_id=v_order.merchant_id
      and mu.user_id=v_uid
      and mu.active=true
  ) then
    v_role:='merchant';
  else
    raise exception 'No autorizado';
  end if;

  if p_message_type='bank_details' then
    if v_role<>'merchant' or v_order.payment_method<>'transfer'
       or v_order.status not in ('awaiting_transfer','payment_review') then
      raise exception 'Datos bancarios solo tras aceptación del restaurante';
    end if;
  end if;
  if p_message_type='receipt' then
    if v_role<>'customer' or v_order.payment_method<>'transfer'
       or v_order.status<>'awaiting_transfer'
       or (coalesce(nullif(trim(p_body),''),nullif(trim(p_attachment_url),'')) is null) then
      raise exception 'Comprobante solo después de que el restaurante acepte el pedido';
    end if;
  end if;
  if p_attachment_url is not null and trim(p_attachment_url)<>'' then
    if left(trim(p_attachment_url),length(p_order_id::text)+1)<>p_order_id::text||'/'
       or not public.marketplace_chat_can_access(trim(p_attachment_url)) then
      raise exception 'El comprobante debe adjuntarse en el chat privado del pedido';
    end if;
  end if;
  if p_message_type='image' and nullif(trim(coalesce(p_attachment_url,'')),'') is null then
    raise exception 'Adjunta una imagen para enviarla';
  end if;
  insert into public.marketplace_order_messages(
    order_id,sender_id,sender_role,message_type,body,attachment_url
  )
  values(
    p_order_id,v_uid,v_role,
    case when p_message_type in ('text','bank_details','receipt','image')
      then p_message_type else 'text' end,
    nullif(trim(coalesce(p_body,'')),''),
    nullif(trim(coalesce(p_attachment_url,'')),'')
  )
  returning * into v_message;

  if v_role='customer'
     and v_message.message_type='receipt'
     and v_order.payment_method='transfer' then
    update public.marketplace_orders
    set
      transfer_receipt_url=v_message.attachment_url,
      transfer_submitted_at=now(),
      payment_status='under_review',
      status='payment_review',
      updated_at=now()
    where id=p_order_id;
  end if;

  return to_jsonb(v_message);
end;
$function$;

CREATE OR REPLACE FUNCTION public.marketplace_order_detail(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_allowed boolean:=false;
begin
  if v_uid is null then raise exception 'No autorizado'; end if;

  select * into v_order
  from public.marketplace_orders
  where id=p_order_id;
  if not found then raise exception 'Pedido no encontrado'; end if;

  v_allowed:=v_order.customer_id=v_uid
    or v_order.assigned_driver_id=v_uid
    or public.is_admin()
    or exists(
      select 1
      from public.marketplace_merchant_users mu
      where mu.merchant_id=v_order.merchant_id
        and mu.user_id=v_uid
        and mu.active=true
    );

  if not v_allowed then raise exception 'No autorizado'; end if;

  return jsonb_build_object(
    'order',to_jsonb(v_order) - 'express_margin' - 'driver_base_payout'
      - 'driver_distance_payout' - 'driver_priority_bonus'
      - 'driver_pickup_payout' - 'driver_dropoff_payout',
    'merchant',(
      select to_jsonb(m) - 'transfer_instructions'
      from public.marketplace_merchants m
      where m.id=v_order.merchant_id
    ),
    'items',(
      select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]'::jsonb)
      from public.marketplace_order_items i
      where i.order_id=p_order_id
    ),
    'messages',(
      select coalesce(
        jsonb_agg(to_jsonb(msg) order by msg.created_at),
        '[]'::jsonb
      )
      from public.marketplace_order_messages msg
      where msg.order_id=p_order_id
    ),
    'financials',(
      select case
        when public.is_admin() then to_jsonb(f)
        when exists(select 1 from public.marketplace_merchant_users mu
          where mu.merchant_id=v_order.merchant_id
          and mu.user_id=v_uid and mu.active) then
          jsonb_build_object(
            'customer_total',f.customer_total,
            'merchant_products_amount',f.merchant_products_amount,
            'driver_payout',f.driver_payout,
            'driver_tip',f.driver_tip,
            'merchant_owes_driver',f.merchant_owes_driver,
            'merchant_owes_express',f.merchant_owes_express,
            'driver_owes_merchant',f.driver_owes_merchant,
            'settlement_status',f.settlement_status
          )
        else '{}'::jsonb end
      from public.marketplace_order_financials f
      where f.order_id=p_order_id
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.marketplace_merchant_orders(p_merchant_id uuid, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'No autorizado'; end if;

  if not public.is_admin()
     and not exists(
       select 1
       from public.marketplace_merchant_users mu
       where mu.merchant_id=p_merchant_id
         and mu.user_id=v_uid
         and mu.active=true
     ) then
    raise exception 'No autorizado';
  end if;

  return (
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.created_at desc),
      '[]'::jsonb
    )
    from (
      select
        o.id,o.status,o.payment_method,o.payment_status,
        o.currency_code,o.total_amount,o.tip_amount,
        o.driver_payout,o.created_at,
        o.transfer_receipt_url,o.transfer_submitted_at,
        o.assigned_driver_id,o.is_priority,
        u.full_name customer_name,
        u.phone customer_phone
      from public.marketplace_orders o
      left join public.users u on u.id=o.customer_id
      where o.merchant_id=p_merchant_id
        and exists(select 1 from public.account_runtime_bindings arb
          where arb.user_id=v_uid and arb.environment=o.channel)
      order by o.created_at desc
      limit greatest(least(coalesce(p_limit,50),100),1)
    ) x
  );
end;
$function$;
commit;