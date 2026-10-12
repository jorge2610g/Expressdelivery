-- Scoped Delivery safety: never alter Taxi, no new money flows.
begin;
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

  if not exists(
    select 1 from public.account_runtime_bindings arb
    where arb.user_id=v_uid and arb.environment=v_order.channel
  ) then raise exception 'Pedido de otro entorno no autorizado'; end if;

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

  if not exists(
    select 1 from public.account_runtime_bindings arb
    where arb.user_id=v_uid and arb.environment=v_order.channel
  ) then raise exception 'Pedido de otro entorno no autorizado'; end if;

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

CREATE OR REPLACE FUNCTION public.marketplace_merchant_accept_transfer(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_order public.marketplace_orders%rowtype; v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'No autorizado'; end if;
 select * into v_order from public.marketplace_orders where id=p_order_id for update;
 if v_order.id is null or not (
   public.is_admin() or exists(select 1 from public.marketplace_merchant_users mu
     where mu.merchant_id=v_order.merchant_id and mu.user_id=v_uid and mu.active)
 ) then raise exception 'No autorizado para aceptar este pedido'; end if;
  if not exists(
    select 1 from public.account_runtime_bindings arb
    where arb.user_id=v_uid and arb.environment=v_order.channel
  ) then raise exception 'Pedido de otro entorno no autorizado'; end if;
 if v_order.payment_method<>'transfer' or v_order.status<>'awaiting_merchant'
   or v_order.payment_status<>'awaiting_merchant' then
   raise exception 'Este pedido no espera aceptación para transferencia'; end if;
 update public.marketplace_orders set status='awaiting_transfer',
    payment_status='awaiting_receipt',updated_at=now() where id=p_order_id;
 insert into public.marketplace_order_messages(
   order_id,sender_id,sender_role,message_type,body
 ) values (p_order_id,v_uid,'merchant','system',
   'Restaurante disponible. Puedes solicitar los datos bancarios y transferir.');
 return public.marketplace_order_detail(p_order_id);
end $function$;

CREATE OR REPLACE FUNCTION public.marketplace_review_transfer(p_order_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  where id=p_order_id
  for update;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if not exists(
    select 1 from public.account_runtime_bindings arb
    where arb.user_id=v_uid and arb.environment=v_order.channel
  ) then raise exception 'Pedido de otro entorno no autorizado'; end if;

  v_allowed:=public.is_admin()
    or exists(
      select 1
      from public.marketplace_merchant_users mu
      where mu.merchant_id=v_order.merchant_id
        and mu.user_id=v_uid
        and mu.active=true
    );
  if not v_allowed then raise exception 'No autorizado'; end if;

  if v_order.payment_method<>'transfer' then
    raise exception 'El pedido no usa transferencia';
  end if;

  if v_order.status<>'payment_review'
     or v_order.payment_status<>'under_review'
     or v_order.transfer_submitted_at is null then
    raise exception 'No hay un comprobante pendiente de revisión';
  end if;
  if p_approve then
    update public.marketplace_orders
    set
      payment_status='paid',
      status='confirmed',
      transfer_reviewed_at=now(),
      transfer_reviewed_by=v_uid,
      updated_at=now()
    where id=p_order_id;
  else
    update public.marketplace_orders
    set
      payment_status='rejected',
      status='awaiting_transfer',
      transfer_reviewed_at=now(),
      transfer_reviewed_by=v_uid,
      updated_at=now()
    where id=p_order_id;
  end if;

  if nullif(trim(coalesce(p_note,'')),'') is not null then
    insert into public.marketplace_order_messages(
      order_id,sender_id,sender_role,message_type,body
    )
    values(
      p_order_id,v_uid,
      case when public.is_admin() then 'admin' else 'merchant' end,
      'text',trim(p_note)
    );
  end if;

  return public.marketplace_order_detail(p_order_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.marketplace_mark_driver_paid(p_order_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  where id=p_order_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if not exists(
    select 1 from public.account_runtime_bindings arb
    where arb.user_id=v_uid and arb.environment=v_order.channel
  ) then raise exception 'Pedido de otro entorno no autorizado'; end if;
  if v_order.assigned_driver_id is null or v_order.status not in
    ('ready','searching_driver','driver_assigned','picked_up') then
    raise exception 'Debe existir un repartidor asignado y la recogida en curso';
  end if;
  if not exists(
    select 1 from public.marketplace_order_financials
    where order_id=p_order_id and merchant_owes_driver>0
  ) then
    raise exception 'Pago al repartidor ya confirmado o no requerido';
  end if;
  v_allowed:=public.is_admin()
    or exists(
      select 1
      from public.marketplace_merchant_users mu
      where mu.merchant_id=v_order.merchant_id
        and mu.user_id=v_uid
        and mu.active=true
    );
  if not v_allowed then raise exception 'No autorizado'; end if;

  update public.marketplace_order_financials
  set
    merchant_owes_driver=0,
    settlement_status=case
      when merchant_owes_express=0
       and driver_owes_merchant=0
       and driver_owes_express=0
       and express_owes_merchant=0
       and express_owes_driver=0
      then 'settled'
      else 'partial'
    end,
    updated_at=now()
  where order_id=p_order_id;

  insert into public.marketplace_order_messages(
    order_id,sender_id,sender_role,message_type,body
  )
  values(
    p_order_id,v_uid,
    case when public.is_admin() then 'admin' else 'merchant' end,
    'system',
    coalesce(
      nullif(trim(coalesce(p_note,'')),''),
      'El comercio confirmó el pago de la tarifa al repartidor.'
    )
  );

  return public.marketplace_order_detail(p_order_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.marketplace_verify_order_code(p_order_id uuid, p_kind text, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_order public.marketplace_orders%rowtype;
  v_kind text:=lower(trim(coalesce(p_kind,'')));
  v_hash text:=encode(extensions.digest(trim(coalesce(p_code,'')),'sha256'),'hex');
begin
  if v_uid is null or not public.is_account_active() then raise exception 'No autorizado'; end if;
  select * into v_order from public.marketplace_orders where id=p_order_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if not exists(
    select 1 from public.account_runtime_bindings arb
    where arb.user_id=v_uid and arb.environment=v_order.channel
  ) then raise exception 'Pedido de otro entorno no autorizado'; end if;
  if v_order.assigned_driver_id is distinct from v_uid then
    raise exception 'Solo el repartidor asignado puede validar el código';
  end if;

  if v_kind='pickup' then
    if v_order.pickup_verified_at is not null
      or v_order.status not in ('ready','searching_driver','driver_assigned') then
      raise exception 'Recogida fuera de estado o ya verificada';
    end if;
    if v_order.collector='merchant' and exists(
      select 1 from public.marketplace_order_financials f
      where f.order_id=v_order.id and f.merchant_owes_driver>0
    ) then
      raise exception 'El restaurante debe pagar al repartidor antes del retiro';
    end if;
    if v_order.pickup_code_hash is null or v_order.pickup_code_hash<>v_hash then
      raise exception 'Código de retiro incorrecto';
    end if;
    update public.marketplace_orders
    set pickup_verified_at=now(),status='picked_up',updated_at=now()
    where id=p_order_id;
  elsif v_kind='delivery' then
    if v_order.pickup_verified_at is null or v_order.delivery_verified_at is not null
      or v_order.status not in ('picked_up','delivering') then
      raise exception 'Entrega fuera de estado o ya verificada';
    end if;
    if v_order.delivery_code_hash is null or v_order.delivery_code_hash<>v_hash then
      raise exception 'Código de entrega incorrecto';
    end if;
    update public.marketplace_orders
    set delivery_verified_at=now(),status='delivered',completed_at=coalesce(completed_at,now()),updated_at=now()
    where id=p_order_id;
  else
    raise exception 'Tipo de código no válido';
  end if;

  return jsonb_build_object('ok',true,'kind',v_kind,'order_id',p_order_id);
end;
$function$;
commit;
