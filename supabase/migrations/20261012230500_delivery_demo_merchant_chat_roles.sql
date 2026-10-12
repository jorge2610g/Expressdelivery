begin;
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
  elsif exists(
    select 1 from public.marketplace_merchant_users mu
    where mu.merchant_id=v_order.merchant_id
      and mu.user_id=v_uid
      and mu.active=true
  ) then
    -- A superadmin explicitly assigned to a demo merchant can act as
    -- merchant in that merchant's own chat, including bank details.
    v_role:='merchant';
  elsif public.is_admin() then
    v_role:='admin';
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
commit;