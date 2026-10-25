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

function joinUrl(base: string, path: string) {
  return base.replace(/\/$/, '') + '/' + path.replace(/^\//, '');
}

function validityMinutes(raw: string) {
  const match = String(raw || '').match(/^(\d+)\/(\d{1,2}):(\d{1,2})$/);
  if (!match) return 15;
  const minutes = Number(match[1]) * 1440 + Number(match[2]) * 60 +
    Number(match[3]);
  return Math.max(1, Math.min(minutes, 30));
}

function normalizedValidity(raw: string) {
  const minutes = validityMinutes(raw);
  return `0/00:${String(minutes).padStart(2,'0')}`;
}

function veripagosHeaders(cfg: any) {
  const headers: Record<string,string> = {
    'Content-Type':'application/json',
    'Accept':'application/json',
  };
  if (cfg.username && cfg.password) {
    headers.Authorization = 'Basic ' + btoa(
      String(cfg.username) + ':' + String(cfg.password),
    );
  }
  return headers;
}

async function createVeripagosQr(cfg: any, settings: any, order: any) {
  if (!cfg.api_base_url || !cfg.create_path || !cfg.username ||
      !cfg.password || !cfg.secret_key) {
    throw new Error('El QR Global no está completamente configurado');
  }
  const expiresAt = new Date(
    Date.now() + validityMinutes(String(settings.qr_validity || '0/00:15')) * 60000,
  ).toISOString();
  const res = await fetch(joinUrl(cfg.api_base_url, cfg.create_path), {
    method:'POST',
    headers:veripagosHeaders(cfg),
    body:JSON.stringify({
      secret_key:String(cfg.secret_key),
      monto:Number(order.total_amount),
      data:[{
        source:'express',
        type:'marketplace_order',
        order_id:String(order.id),
        customer_id:String(order.customer_id),
        merchant_id:String(order.merchant_id),
        channel:'production',
      }],
      vigencia:normalizedValidity(String(settings.qr_validity || '0/00:15')),
      uso_unico:true,
      detalle:'Express Delivery · Pedido ' + String(order.id).slice(0,8),
    }),
  });
  const raw = await res.text();
  let data: any = {};
  try { data = raw ? JSON.parse(raw) : {}; } catch { data = {raw}; }
  if (!res.ok || Number(data?.Codigo) !== 0) {
    throw new Error(data?.Mensaje || data?.message ||
      ('VeriPagos respondió HTTP ' + res.status));
  }
  const qr = data?.Data?.qr;
  const movement = data?.Data?.movimiento_id;
  if (!qr || !movement) {
    throw new Error('VeriPagos no devolvió un QR válido para el pedido');
  }
  return {
    qr:String(qr),
    movement:String(movement),
    expiresAt,
    providerData:{
      veripagos_global_qr:{
        Codigo:data?.Codigo,
        Mensaje:data?.Mensaje,
        Data:{movimiento_id:String(movement)},
      },
    },
  };
}

async function verifyVeripagosQr(cfg: any, order: any) {
  if (!cfg.api_base_url || !cfg.status_path || !cfg.username ||
      !cfg.password || !cfg.secret_key || !order.provider_reference) {
    throw new Error('No se pudo verificar el QR Global');
  }
  const res = await fetch(joinUrl(cfg.api_base_url, cfg.status_path), {
    method:'POST',
    headers:veripagosHeaders(cfg),
    body:JSON.stringify({
      secret_key:String(cfg.secret_key),
      movimiento_id:String(order.provider_reference),
    }),
  });
  const raw = await res.text();
  let data: any = {};
  try { data = raw ? JSON.parse(raw) : {}; } catch { data = {raw}; }
  if (!res.ok || Number(data?.Codigo) !== 0) {
    throw new Error(data?.Mensaje || data?.message ||
      ('VeriPagos respondió HTTP ' + res.status));
  }
  const payment = data?.Data || {};
  const state = String(payment?.estado || 'Pendiente').trim().toLowerCase();
  const paid = state === 'completado';
  if (paid && (
    String(payment?.movimiento_id || '') !== String(order.provider_reference) ||
    Math.abs(Number(payment?.monto) - Number(order.total_amount)) >= 0.001
  )) {
    throw new Error('VeriPagos devolvió un pago que no coincide con el pedido');
  }
  return {
    paid,
    expired:['vencido','expirado'].includes(state),
    rejected:['rechazado','cancelado','fallido'].includes(state),
    state,
    data:{
      movimiento_id:payment?.movimiento_id,
      monto:payment?.monto,
      estado:payment?.estado,
      detalle:payment?.detalle,
    },
  };
}

async function getOwnedGlobalQrOrder(admin: any, orderId: string, userId: string) {
  const {data:order,error} = await admin.from('marketplace_orders')
    .select('*').eq('id',orderId).single();
  if (error || !order) throw new Error('Pedido no encontrado');
  if (order.customer_id !== userId) throw new Error('No autorizado');
  if (order.payment_method !== 'global_qr' ||
      !['production','preview'].includes(order.channel) ||
      order.currency_code !== 'BOB') {
    throw new Error('Este pedido no usa QR Global');
  }
  const {data:binding,error:bindingError} = await admin
    .from('account_runtime_bindings').select('environment')
    .eq('user_id',userId).maybeSingle();
  if (bindingError) throw bindingError;
  if (binding?.environment !== order.channel) {
    throw new Error('El pedido no pertenece al entorno activo de la cuenta');
  }
  if (order.channel === 'preview') return order;

  if (binding?.environment !== 'production') {
    throw new Error('Los pagos reales requieren una cuenta de Producción');
  }
  const {data:isAudit,error:auditError} = await admin.rpc(
    'is_active_audit_user',{p_user_id:userId},
  );
  if (auditError || isAudit !== false) {
    throw new Error('Los pagos reales no están disponibles para esta cuenta');
  }
  return order;
}

async function veripagosSettings(admin: any) {
  const {data:settings,error:settingsError} = await admin
    .from('driver_subscription_settings')
    .select('provider_enabled,qr_validity').eq('id',true).maybeSingle();
  if (settingsError) throw settingsError;
  if (settings?.provider_enabled !== true) {
    throw new Error('El QR Global no está habilitado');
  }
  const {data:cfg,error:cfgError} = await admin.rpc(
    'service_get_driver_subscription_provider_settings',
  );
  if (cfgError) throw cfgError;
  if (!cfg?.api_base_url || !cfg?.create_path || !cfg?.status_path ||
      !cfg?.username || !cfg?.password || !cfg?.secret_key) {
    throw new Error('El QR Global no está completamente configurado');
  }
  return {settings,cfg};
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

    if (action === 'global_qr_create' || action === 'global_qr_verify' ||
        action === 'global_qr_cancel' || action === 'global_qr_simulate') {
      const orderId = String(body.order_id || '');
      if (!orderId) return json({error:'Pedido inválido'},400);
      const order = await getOwnedGlobalQrOrder(admin,orderId,user.id);

      // Preview orders use a synthetic QR code and a manual test confirmation.
      // This branch never calls VeriPagos or changes Production payments.
      if (order.channel === 'preview') {
        if (order.provider_data?.preview_test_qr !== true) {
          throw new Error('Este pedido no tiene habilitado el QR de prueba');
        }
        if (order.payment_status === 'paid') {
          return json({ok:true,status:'paid',approved:true,order_id:order.id,
            preview_test:true});
        }
        if (action === 'global_qr_create') {
          if (order.payment_status !== 'qr_pending' ||
              order.status !== 'awaiting_payment') {
            return json({ok:false,status:order.payment_status,
              error:'Este QR ya no está pendiente'},409);
          }
          if (order.payment_expires_at &&
              new Date(order.payment_expires_at).getTime()<=Date.now()) {
            const {data:expired,error:expireError} = await admin.rpc(
              'service_marketplace_global_qr_finish',
              {p_order_id:order.id,p_status:'expired'},
            );
            if (expireError) throw expireError;
            return json({ok:true,status:expired?.state || 'expired',
              order_id:order.id,preview_test:true});
          }
          if (order.provider_reference && order.online_checkout_url) {
            return json({ok:true,status:'qr_pending',order_id:order.id,
              qr:order.online_checkout_url,
              expires_at:order.payment_expires_at,reused:true,
              preview_test:true});
          }
          const expiresAt = order.payment_expires_at ||
            new Date(Date.now()+15*60000).toISOString();
          const {data:claim,error:claimError} = await admin.rpc(
            'service_marketplace_global_qr_claim',
            {p_order_id:order.id,p_expires_at:expiresAt},
          );
          if (claimError) throw claimError;
          if (claim?.state === 'ready') {
            return json({ok:true,status:'qr_pending',order_id:order.id,
              qr:claim.order?.online_checkout_url,
              expires_at:claim.order?.payment_expires_at,reused:true,
              preview_test:true});
          }
          if (claim?.state !== 'claimed') {
            return json({ok:true,status:claim?.state || 'generating',
              order_id:order.id,preview_test:true});
          }
          const qrPayload = `express-preview-payment://${order.id}`;
          const providerReference = 'preview:' + crypto.randomUUID();
          const {data:saved,error:saveError} = await admin.rpc(
            'service_marketplace_global_qr_save',
            {
              p_order_id:order.id,
              p_provider_reference:providerReference,
              p_qr_payload:qrPayload,
              p_provider_data:{preview_test_qr:true,provider:'preview_simulator'},
            },
          );
          if (saveError) throw saveError;
          return json({ok:true,provider:'preview_simulator',status:'qr_pending',
            order_id:order.id,qr:saved?.online_checkout_url,
            expires_at:saved?.payment_expires_at,reused:false,
            preview_test:true});
        }

        if (action === 'global_qr_simulate') {
          if (order.payment_status !== 'qr_pending' ||
              order.status !== 'awaiting_payment' ||
              !order.provider_reference || !order.online_checkout_url) {
            return json({ok:false,status:order.payment_status,
              error:'No hay un QR de prueba pendiente'},409);
          }
          if (order.payment_expires_at &&
              new Date(order.payment_expires_at).getTime()<=Date.now()) {
            const {data:expired,error:expireError} = await admin.rpc(
              'service_marketplace_global_qr_finish',
              {p_order_id:order.id,p_status:'expired'},
            );
            if (expireError) throw expireError;
            return json({ok:true,status:expired?.state || 'expired',
              order_id:order.id,preview_test:true});
          }
          const {data:paid,error:paidError} = await admin.rpc(
            'service_marketplace_global_qr_finish',
            {
              p_order_id:order.id,p_status:'paid',
              p_provider_reference:order.provider_reference,
              p_provider_data:{preview_simulated_payment:true,
                simulated_at:new Date().toISOString()},
            },
          );
          if (paidError) throw paidError;
          return json({ok:true,status:paid?.state || 'paid',approved:true,
            order_id:order.id,preview_test:true});
        }

        if (action === 'global_qr_cancel') {
          const {data:closed,error:closeError} = await admin.rpc(
            'service_marketplace_global_qr_finish',
            {p_order_id:order.id,p_status:'disabled'},
          );
          if (closeError) throw closeError;
          return json({ok:true,status:closed?.state || 'disabled',
            order_id:order.id,preview_test:true});
        }

        return json({ok:true,status:order.payment_status,
          order_id:order.id,expires_at:order.payment_expires_at,
          qr:order.online_checkout_url,preview_test:true});
      }

      if (action === 'global_qr_create') {
        const {settings,cfg} = await veripagosSettings(admin);
        if (order.payment_status === 'paid') {
          return json({ok:true,status:'paid',approved:true,order_id:order.id});
        }
        if (order.payment_status !== 'qr_pending' ||
            order.status !== 'awaiting_payment') {
          return json({ok:false,status:order.payment_status,
            error:'Este QR ya no está pendiente'},409);
        }
        const minutes = validityMinutes(String(settings.qr_validity || '0/00:15'));
        const expiresAt = new Date(Date.now()+minutes*60000).toISOString();
        const {data:claim,error:claimError} = await admin.rpc(
          'service_marketplace_global_qr_claim',
          {p_order_id:order.id,p_expires_at:expiresAt},
        );
        if (claimError) throw claimError;
        const claimed = claim?.order || {};
        if (claim?.state === 'ready') {
          return json({ok:true,status:'qr_pending',order_id:order.id,
            qr:claimed.online_checkout_url,
            expires_at:claimed.payment_expires_at,reused:true});
        }
        if (claim?.state === 'generating') {
          return json({ok:true,status:'generating',order_id:order.id});
        }
        if (claim?.state !== 'claimed') {
          return json({ok:true,status:claim?.state || 'expired',
            order_id:order.id});
        }
        const created = await createVeripagosQr(cfg,settings,claimed);
        const {data:saved,error:saveError} = await admin.rpc(
          'service_marketplace_global_qr_save',
          {
            p_order_id:order.id,
            p_provider_reference:created.movement,
            p_qr_payload:created.qr,
            p_provider_data:created.providerData,
          },
        );
        if (saveError) throw saveError;
        return json({ok:true,provider:'veripagos',status:'qr_pending',
          order_id:order.id,qr:saved?.online_checkout_url,
          expires_at:saved?.payment_expires_at,reused:false});
      }

      if (order.payment_status === 'paid') {
        return json({ok:true,approved:true,status:'paid',order_id:order.id});
      }
      if (!order.provider_reference) {
        if (action === 'global_qr_cancel') {
          const {data:closed,error:closeError} = await admin.rpc(
            'service_marketplace_global_qr_finish',
            {p_order_id:order.id,p_status:'disabled'},
          );
          if (closeError) throw closeError;
          return json({ok:true,status:closed?.state || 'disabled',
            order_id:order.id});
        }
        return json({ok:true,status:order.payment_status,
          order_id:order.id,expires_at:order.payment_expires_at});
      }

      let settings: any;
      let cfg: any;
      try {
        ({settings,cfg} = await veripagosSettings(admin));
      } catch (error) {
        if (action !== 'global_qr_cancel') throw error;
        const {data:closed,error:closeError} = await admin.rpc(
          'service_marketplace_global_qr_finish',
          {
            p_order_id:order.id,p_status:'disabled',
            p_provider_data:{
              global_qr_disabled_at:new Date().toISOString(),
              global_qr_status_check_unavailable:true,
            },
          },
        );
        if (closeError) throw closeError;
        return json({ok:true,status:closed?.state || 'disabled',
          order_id:order.id,provider_status_unchecked:true});
      }

      // Check with VeriPagos before accepting a local cancellation or expiry.
      // This prevents hiding a payment that completed just before the action.
      let checked: any;
      try {
        checked = await verifyVeripagosQr(cfg,order);
      } catch (error) {
        if (action !== 'global_qr_cancel') throw error;
        const {data:closed,error:closeError} = await admin.rpc(
          'service_marketplace_global_qr_finish',
          {
            p_order_id:order.id,p_status:'disabled',
            p_provider_data:{
              global_qr_disabled_at:new Date().toISOString(),
              global_qr_status_check_unavailable:true,
            },
          },
        );
        if (closeError) throw closeError;
        return json({ok:true,status:closed?.state || 'disabled',
          order_id:order.id,provider_status_unchecked:true});
      }
      if (checked.paid) {
        const {data:closed,error:finishError} = await admin.rpc(
          'service_marketplace_global_qr_finish',
          {
            p_order_id:order.id,p_status:'paid',
            p_provider_reference:order.provider_reference,
            p_provider_data:{veripagos_global_qr_payment:checked.data},
          },
        );
        if (finishError) throw finishError;
        return json({ok:true,approved:true,status:'paid',order_id:order.id,
          late_after_close:closed?.order?.status==='cancelled'});
      }

      const alreadyClosed = ['cancelled','expired','disabled'].includes(order.payment_status);
      if (action === 'global_qr_cancel' && !alreadyClosed) {
        const {data:closed,error:closeError} = await admin.rpc(
          'service_marketplace_global_qr_finish',
          {
            p_order_id:order.id,p_status:'disabled',
            p_provider_data:{global_qr_disabled_at:new Date().toISOString()},
          },
        );
        if (closeError) throw closeError;
        return json({ok:true,status:closed?.state || 'disabled',
          order_id:order.id});
      }

      if (!alreadyClosed && (
        checked.expired || checked.rejected ||
        (order.payment_expires_at &&
          new Date(order.payment_expires_at).getTime()<=Date.now())
      )) {
        const {data:closed,error:closeError} = await admin.rpc(
          'service_marketplace_global_qr_finish',
          {
            p_order_id:order.id,p_status:'expired',
            p_provider_data:{veripagos_global_qr_payment:checked.data},
          },
        );
        if (closeError) throw closeError;
        return json({ok:true,status:closed?.state || 'expired',
          order_id:order.id,expires_at:order.payment_expires_at});
      }

      return json({ok:true,status:order.payment_status,
        order_id:order.id,expires_at:order.payment_expires_at,
        qr:order.online_checkout_url});
    }

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
