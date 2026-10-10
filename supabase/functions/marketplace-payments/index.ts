import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {...corsHeaders, 'Content-Type': 'application/json'},
  });
}

function serviceKey() {
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) return legacy;
  const raw = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (!raw) throw new Error('No hay clave de servicio');
  const parsed = JSON.parse(raw);
  if (!parsed.default) throw new Error('No hay secret key default');
  return parsed.default;
}

function userClient(req: Request) {
  const authorization = req.headers.get('authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) throw new Error('Sesión requerida');
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      global: {headers: {Authorization: authorization}},
      auth: {persistSession: false, autoRefreshToken: false},
    },
  );
}

function adminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    serviceKey(),
    {auth: {persistSession: false, autoRefreshToken: false}},
  );
}

async function zoneMercadoPago(admin: any, zoneId: string) {
  const {data:cfg,error} = await admin.rpc(
    'service_get_zone_payment_provider_settings',
    {p_zone_id: zoneId},
  );
  if (error) throw error;
  if (
    !cfg ||
    cfg.provider !== 'mercado_pago' ||
    !cfg.access_token ||
    cfg?.extra_config?.site_id !== 'MLC'
  ) {
    throw new Error('Mercado Pago no está configurado en esta zona');
  }
  return cfg;
}

async function createPreference(
  cfg: any,
  input: {
    title: string;
    description: string;
    amount: number;
    currency: string;
    externalReference: string;
    metadata: Record<string, unknown>;
    email?: string | null;
  },
) {
  const body: any = {
    items: [{
      id: input.externalReference,
      title: input.title,
      description: input.description,
      quantity: 1,
      currency_id: input.currency,
      unit_price: input.amount,
    }],
    external_reference: input.externalReference,
    metadata: input.metadata,
    statement_descriptor: 'EXPRESS',
  };
  if (input.email) body.payer = {email: input.email};

  const res = await fetch('https://api.mercadopago.com/checkout/preferences', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + String(cfg.access_token),
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify(body),
  });

  const raw = await res.text();
  let data: any = {};
  try { data = raw ? JSON.parse(raw) : {}; } catch { data = {raw}; }

  if (!res.ok || !data?.id || !data?.init_point) {
    throw new Error(
      data?.message ||
      data?.error ||
      ('Mercado Pago respondió HTTP ' + res.status),
    );
  }

  return {
    preferenceId: String(data.id),
    checkoutUrl: String(data.init_point),
    data: {
      id: data.id,
      external_reference: data.external_reference,
      init_point: data.init_point,
      sandbox_init_point: data.sandbox_init_point,
      date_created: data.date_created,
    },
  };
}

async function searchPayment(
  cfg: any,
  externalReference: string,
  expectedAmount: number,
  expectedCurrency: string,
) {
  const url =
    'https://api.mercadopago.com/v1/payments/search?' +
    new URLSearchParams({
      external_reference: externalReference,
      sort: 'date_created',
      criteria: 'desc',
      limit: '10',
    }).toString();

  const res = await fetch(url, {
    headers: {
      Authorization: 'Bearer ' + String(cfg.access_token),
      Accept: 'application/json',
    },
  });

  const raw = await res.text();
  let data: any = {};
  try { data = raw ? JSON.parse(raw) : {}; } catch { data = {raw}; }

  if (!res.ok) {
    throw new Error(
      data?.message ||
      data?.error ||
      ('Mercado Pago respondió HTTP ' + res.status),
    );
  }

  const results = Array.isArray(data?.results) ? data.results : [];
  const match = results.find((item: any) =>
    String(item?.currency_id || '') === expectedCurrency &&
    Math.abs(Number(item?.transaction_amount || 0) - expectedAmount) < 0.001
  );

  if (!match) {
    return {approved:false,rejected:false,status:'pending',id:null,data:null};
  }

  const status = String(match.status || 'pending').toLowerCase();
  return {
    approved: status === 'approved',
    rejected: ['rejected','cancelled','refunded','charged_back'].includes(status),
    status,
    id: match.id ? String(match.id) : null,
    data: {
      id: match.id,
      status: match.status,
      status_detail: match.status_detail,
      external_reference: match.external_reference,
      transaction_amount: match.transaction_amount,
      currency_id: match.currency_id,
      date_created: match.date_created,
      date_approved: match.date_approved,
      payment_method_id: match.payment_method_id,
      payment_type_id: match.payment_type_id,
    },
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }
  if (req.method !== 'POST') return json({error:'Método no permitido'},405);

  try {
    const userSb = userClient(req);
    const {data:userData,error:userError} = await userSb.auth.getUser();
    if (userError || !userData.user) return json({error:'Sesión inválida'},401);
    const user = userData.user;
    const admin = adminClient();
    const body = await req.json().catch(()=>({}));
    const action = String(body.action || '');

    if (action === 'order_create') {
      const orderId = String(body.order_id || '');
      if (!orderId) return json({error:'Pedido inválido'},400);

      const {data:order,error} = await admin
        .from('marketplace_orders')
        .select('*')
        .eq('id',orderId)
        .single();
      if (error || !order) return json({error:'Pedido no encontrado'},404);
      if (order.customer_id !== user.id) return json({error:'No autorizado'},403);
      if (order.payment_method !== 'mercado_pago') {
        return json({error:'El pedido no usa Mercado Pago'},409);
      }
      if (order.payment_status === 'paid') {
        return json({
          ok:true,approved:true,status:'paid',order_id:order.id,
          checkout_url:order.online_checkout_url,
        });
      }

      if (order.online_checkout_url && order.provider_reference) {
        return json({
          ok:true,
          approved:false,
          status:order.payment_status,
          order_id:order.id,
          checkout_url:order.online_checkout_url,
          reused:true,
        });
      }

      const cfg = await zoneMercadoPago(admin, String(order.zone_id));
      const externalReference = 'marketplace_order:' + String(order.id);
      const created = await createPreference(cfg, {
        title: 'Express Delivery · Pedido',
        description: 'Pedido de Express Delivery',
        amount: Number(order.total_amount),
        currency: String(order.currency_code),
        externalReference,
        metadata: {
          source:'express',
          type:'marketplace_order',
          order_id:String(order.id),
          customer_id:String(order.customer_id),
          merchant_id:String(order.merchant_id),
        },
        email:user.email,
      });

      const {error:updateError} = await admin
        .from('marketplace_orders')
        .update({
          provider_reference:created.preferenceId,
          online_checkout_url:created.checkoutUrl,
          provider_data:{
            mercado_pago_preference:created.data,
            external_reference:externalReference,
          },
          updated_at:new Date().toISOString(),
        })
        .eq('id',order.id);
      if (updateError) throw updateError;

      return json({
        ok:true,
        provider:'mercado_pago',
        order_id:order.id,
        status:'pending',
        checkout_url:created.checkoutUrl,
        reused:false,
      });
    }

    if (action === 'order_verify') {
      const orderId = String(body.order_id || '');
      const {data:order,error} = await admin
        .from('marketplace_orders')
        .select('*')
        .eq('id',orderId)
        .single();
      if (error || !order) return json({error:'Pedido no encontrado'},404);
      if (order.customer_id !== user.id) return json({error:'No autorizado'},403);

      if (order.payment_status === 'paid') {
        return json({ok:true,approved:true,status:'paid',order_id:order.id});
      }

      const cfg = await zoneMercadoPago(admin, String(order.zone_id));
      const externalReference = 'marketplace_order:' + String(order.id);
      const checked = await searchPayment(
        cfg,
        externalReference,
        Number(order.total_amount),
        String(order.currency_code),
      );

      if (checked.approved) {
        const {data:detail,error:markError} = await admin.rpc(
          'marketplace_order_mark_paid',
          {
            p_order_id:order.id,
            p_provider_reference:checked.id,
            p_provider_data:{mercado_pago_payment:checked.data},
          },
        );
        if (markError) throw markError;
        return json({
          ok:true,
          approved:true,
          status:'paid',
          order_id:order.id,
          detail,
        });
      }

      if (checked.rejected) {
        await admin
          .from('marketplace_orders')
          .update({
            payment_status:'rejected',
            provider_data:{
              ...(order.provider_data || {}),
              mercado_pago_payment:checked.data,
            },
            updated_at:new Date().toISOString(),
          })
          .eq('id',order.id);
      }

      return json({
        ok:true,
        approved:false,
        status:checked.status,
        order_id:order.id,
        checkout_url:order.online_checkout_url,
      });
    }

    if (action === 'plus_create') {
      const planId = String(body.plan_id || '');
      const {data:plan,error} = await admin
        .from('marketplace_plus_plans')
        .select('*')
        .eq('id',planId)
        .eq('active',true)
        .single();
      if (error || !plan) return json({error:'Plan no disponible'},404);
      if (Number(plan.monthly_price || 0) <= 0) {
        return json({
          error:'Express Plus todavía no tiene un precio mensual válido'
        },409);
      }

      const cfg = await zoneMercadoPago(admin, String(plan.zone_id));

      const {data:pending,error:existingError} = await admin
        .from('marketplace_plus_payments')
        .select('*')
        .eq('customer_id',user.id)
        .eq('plan_id',plan.id)
        .eq('status','pending')
        .order('created_at',{ascending:false})
        .limit(1)
        .maybeSingle();
      if (existingError) throw existingError;

      if (pending?.checkout_url && pending?.provider_reference) {
        return json({
          ok:true,
          provider:'mercado_pago',
          payment_id:pending.id,
          checkout_url:pending.checkout_url,
          status:'pending',
          reused:true,
        });
      }

      const paymentId = crypto.randomUUID();
      const externalReference = 'marketplace_plus:' + paymentId;
      const created = await createPreference(cfg, {
        title:String(plan.name || 'Express Plus'),
        description:'Suscripción mensual Express Plus',
        amount:Number(plan.monthly_price),
        currency:String(plan.currency_code),
        externalReference,
        metadata:{
          source:'express',
          type:'marketplace_plus',
          payment_id:paymentId,
          customer_id:user.id,
          plan_id:plan.id,
        },
        email:user.email,
      });

      const {error:insertError} = await admin
        .from('marketplace_plus_payments')
        .insert({
          id:paymentId,
          customer_id:user.id,
          plan_id:plan.id,
          amount:plan.monthly_price,
          currency_code:plan.currency_code,
          provider:'mercado_pago',
          status:'pending',
          provider_reference:created.preferenceId,
          checkout_url:created.checkoutUrl,
          provider_data:{
            mercado_pago_preference:created.data,
            external_reference:externalReference,
          },
        });
      if (insertError) throw insertError;

      return json({
        ok:true,
        provider:'mercado_pago',
        payment_id:paymentId,
        checkout_url:created.checkoutUrl,
        status:'pending',
        reused:false,
      });
    }

    if (action === 'plus_verify') {
      const paymentId = String(body.payment_id || '');
      const {data:payment,error} = await admin
        .from('marketplace_plus_payments')
        .select('*, marketplace_plus_plans(*)')
        .eq('id',paymentId)
        .single();
      if (error || !payment) return json({error:'Pago no encontrado'},404);
      if (payment.customer_id !== user.id) return json({error:'No autorizado'},403);

      if (payment.status === 'approved') {
        return json({ok:true,approved:true,status:'approved',payment_id:paymentId});
      }

      const plan = payment.marketplace_plus_plans;
      const cfg = await zoneMercadoPago(admin, String(plan.zone_id));
      const externalReference = 'marketplace_plus:' + paymentId;
      const checked = await searchPayment(
        cfg,
        externalReference,
        Number(payment.amount),
        String(payment.currency_code),
      );

      if (checked.approved) {
        const {data:activated,error:activateError} = await admin.rpc(
          'marketplace_activate_plus',
          {
            p_customer_id:user.id,
            p_plan_id:payment.plan_id,
            p_provider:'mercado_pago',
            p_provider_reference:checked.id,
          },
        );
        if (activateError) throw activateError;

        await admin
          .from('marketplace_plus_payments')
          .update({
            status:'approved',
            paid_at:new Date().toISOString(),
            provider_reference:checked.id,
            provider_data:{
              ...(payment.provider_data || {}),
              mercado_pago_payment:checked.data,
            },
            updated_at:new Date().toISOString(),
          })
          .eq('id',paymentId);

        return json({
          ok:true,
          approved:true,
          status:'approved',
          payment_id:paymentId,
          subscription:activated,
        });
      }

      if (checked.rejected) {
        await admin
          .from('marketplace_plus_payments')
          .update({
            status:'rejected',
            provider_data:{
              ...(payment.provider_data || {}),
              mercado_pago_payment:checked.data,
            },
            updated_at:new Date().toISOString(),
          })
          .eq('id',paymentId);
      }

      return json({
        ok:true,
        approved:false,
        status:checked.status,
        payment_id:paymentId,
        checkout_url:payment.checkout_url,
      });
    }

    return json({error:'Acción no soportada'},400);
  } catch (error) {
    console.error('marketplace-payments',error);
    return json({
      ok:false,
      error:error instanceof Error ? error.message : String(error),
    },500);
  }
});
