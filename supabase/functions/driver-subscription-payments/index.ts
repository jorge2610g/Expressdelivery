import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-retry-count, traceparent, tracestate, baggage',
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
  if (!raw) throw new Error('No hay clave de servicio disponible');
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

function joinUrl(base: string, path: string) {
  return base.replace(/\/$/, '') + '/' + path.replace(/^\//, '');
}

function findValue(value: any, keys: string[]): any {
  if (value == null) return null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findValue(item, keys);
      if (found != null) return found;
    }
    return null;
  }
  if (typeof value !== 'object') return null;
  for (const key of keys) {
    if (value[key] != null) return value[key];
  }
  for (const item of Object.values(value)) {
    const found = findValue(item, keys);
    if (found != null) return found;
  }
  return null;
}

function validityMinutes(raw: string) {
  const match = String(raw || '').match(/^(\d+)\/(\d{1,2}):(\d{1,2})$/);
  if (!match) return 15;
  return Math.max(1, Number(match[1]) * 1440 + Number(match[2]) * 60 + Number(match[3]));
}

function providerHeaders(cfg: any) {
  const headers: Record<string,string> = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  if (cfg.username && cfg.password) {
    headers['Authorization'] =
      'Basic ' + btoa(String(cfg.username) + ':' + String(cfg.password));
  }
  return headers;
}

async function providerCreate(
  cfg: any,
  settings: any,
  payment: any,
  plan: any,
) {
  if (!cfg.api_base_url || !cfg.create_path) {
    throw new Error('VeriPagos todavía no tiene endpoint de generación configurado');
  }
  if (!cfg.username || !cfg.password || !cfg.secret_key) {
    throw new Error('VeriPagos no tiene credenciales completas');
  }

  const body = {
    secret_key: String(cfg.secret_key),
    monto: Number(payment.amount),
    data: [
      {
        source: 'express',
        type: 'driver_subscription',
        payment_id: payment.id,
        driver_id: payment.driver_id,
        plan_id: payment.plan_id,
      },
    ],
    vigencia: String(settings.qr_validity || '0/00:15'),
    uso_unico: true,
    detalle: 'Express · Suscripción ' + String(plan.name || ''),
  };

  // No live VeriPagos traffic is allowed from Express Preview.
  // If enabled, the configured host must be a dedicated sandbox endpoint.
  if ((Deno.env.get('SUPABASE_URL') ?? '').includes('xbphilqezmwfjfpdbwad')) {
    const allowed = (Deno.env.get('EXPRESS_PREVIEW_VERIPAGOS_SANDBOX_HOST') ?? '').trim().toLowerCase();
    const actual = new URL(joinUrl(cfg.api_base_url, cfg.create_path)).hostname.toLowerCase();
    if (!allowed || actual !== allowed) {
      throw new Error('VeriPagos Preview requiere un servidor sandbox independiente.');
    }
  }
  const res = await fetch(joinUrl(cfg.api_base_url, cfg.create_path), {
    method: 'POST',
    headers: providerHeaders(cfg),
    body: JSON.stringify(body),
  });

  const raw = await res.text();
  let data: any = {};
  try { data = raw ? JSON.parse(raw) : {}; } catch { data = {raw}; }

  if (!res.ok) {
    throw new Error(
      data?.Mensaje ||
      data?.message ||
      ('VeriPagos respondió HTTP ' + res.status)
    );
  }

  if (Number(data?.Codigo) !== 0) {
    throw new Error(data?.Mensaje || 'VeriPagos rechazó la generación del QR');
  }

  const qr = data?.Data?.qr;
  const movement = data?.Data?.movimiento_id;
  if (!qr || !movement) {
    throw new Error(
      'VeriPagos respondió, pero no se encontró Data.qr o Data.movimiento_id'
    );
  }

  return {
    data: {
      Codigo: data?.Codigo,
      Mensaje: data?.Mensaje,
      Data: {
        movimiento_id: movement,
      },
    },
    qr: String(qr),
    movement: String(movement),
  };
}

async function providerStatus(cfg: any, payment: any) {
  if (!cfg.api_base_url || !cfg.status_path) {
    throw new Error('VeriPagos todavía no tiene endpoint de verificación configurado');
  }
  if (!cfg.username || !cfg.password || !cfg.secret_key) {
    throw new Error('VeriPagos no tiene credenciales completas');
  }
  if (!payment.provider_order_id) {
    throw new Error('El pago no tiene movimiento_id de VeriPagos');
  }

  // No live VeriPagos traffic is allowed from Express Preview.
  // If enabled, the configured host must be a dedicated sandbox endpoint.
  if ((Deno.env.get('SUPABASE_URL') ?? '').includes('xbphilqezmwfjfpdbwad')) {
    const allowed = (Deno.env.get('EXPRESS_PREVIEW_VERIPAGOS_SANDBOX_HOST') ?? '').trim().toLowerCase();
    const actual = new URL(joinUrl(cfg.api_base_url, cfg.status_path)).hostname.toLowerCase();
    if (!allowed || actual !== allowed) {
      throw new Error('VeriPagos Preview requiere un servidor sandbox independiente.');
    }
  }
  const res = await fetch(joinUrl(cfg.api_base_url, cfg.status_path), {
    method: 'POST',
    headers: providerHeaders(cfg),
    body: JSON.stringify({
      secret_key: String(cfg.secret_key),
      movimiento_id: String(payment.provider_order_id),
    }),
  });

  const raw = await res.text();
  let data: any = {};
  try { data = raw ? JSON.parse(raw) : {}; } catch { data = {raw}; }

  if (!res.ok) {
    throw new Error(
      data?.Mensaje ||
      data?.message ||
      ('VeriPagos respondió HTTP ' + res.status)
    );
  }

  if (Number(data?.Codigo) !== 0) {
    throw new Error(
      data?.Mensaje ||
      'VeriPagos rechazó la consulta del estado QR'
    );
  }

  const providerData = data?.Data || {};
  const state = String(providerData?.estado || 'Pendiente')
    .trim()
    .toLowerCase();

  const approved = state === 'completado';
  const rejected = [
    'rechazado',
    'cancelado',
    'vencido',
    'fallido',
  ].includes(state);

  const safeData = {
    Codigo: data?.Codigo,
    Mensaje: data?.Mensaje,
    Data: {
      movimiento_id: providerData?.movimiento_id,
      monto: providerData?.monto,
      detalle: providerData?.detalle,
      estado: providerData?.estado,
      estado_notificacion: providerData?.estado_notificacion,
    },
  };

  return {
    data: safeData,
    state,
    approved,
    rejected,
  };
}


async function mercadoPagoConfig(admin: any, zoneId: string) {
  const {data:cfg,error} = await admin.rpc(
    'service_get_zone_payment_provider_settings',
    {p_zone_id: zoneId},
  );
  if (error) throw error;
  // Preview must NEVER use a real merchant access token for QA checkout.
  // Mercado Pago test tokens begin with TEST-. No network call is permitted
  // unless the designated Preview project uses test credentials.
  if ((Deno.env.get('SUPABASE_URL') ?? '').includes('xbphilqezmwfjfpdbwad') &&
      cfg?.access_token && !String(cfg.access_token).startsWith('TEST-')) {
    throw new Error('Preview requiere credenciales TEST- de Mercado Pago. No se cobran pagos reales.');
  }
  if (
    !cfg ||
    cfg.provider !== 'mercado_pago' ||
    !cfg.access_token ||
    cfg?.extra_config?.site_id !== 'MLC'
  ) {
    throw new Error('Mercado Pago Chile no está configurado para esta zona');
  }
  return cfg;
}

async function mercadoPagoCreate(
  cfg: any,
  payment: any,
  plan: any,
  user: any,
) {
  const externalReference = 'driver_subscription:' + String(payment.id);
  const body: any = {
    items: [
      {
        id: String(plan.id),
        title: 'Express · Suscripción ' + String(plan.name || ''),
        description: 'Suscripción de conductor Express',
        quantity: 1,
        currency_id: String(payment.currency_code || 'CLP'),
        unit_price: Number(payment.amount),
      },
    ],
    external_reference: externalReference,
    metadata: {
      source: 'express',
      type: 'driver_subscription',
      payment_id: String(payment.id),
      driver_id: String(payment.driver_id),
      plan_id: String(payment.plan_id),
    },
    statement_descriptor: 'EXPRESS',
  };

  if (user?.email) {
    body.payer = {email: String(user.email)};
  }

  const res = await fetch(
    'https://api.mercadopago.com/checkout/preferences',
    {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + String(cfg.access_token),
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );

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
    externalReference,
    data: {
      id: data.id,
      external_reference: data.external_reference,
      init_point: data.init_point,
      sandbox_init_point: data.sandbox_init_point,
      date_created: data.date_created,
    },
  };
}

async function mercadoPagoStatus(
  cfg: any,
  payment: any,
) {
  const externalReference =
    'driver_subscription:' + String(payment.id);
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
      'Authorization': 'Bearer ' + String(cfg.access_token),
      'Accept': 'application/json',
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
  const matched = results.find((item: any) => {
    const sameCurrency =
      String(item?.currency_id || '') === String(payment.currency_code || '');
    const sameAmount =
      Math.abs(Number(item?.transaction_amount || 0) - Number(payment.amount || 0)) < 0.001;
    return sameCurrency && sameAmount;
  });

  if (!matched) {
    return {
      approved: false,
      rejected: false,
      state: 'pending',
      paymentId: null,
      data: {
        external_reference: externalReference,
        results_found: results.length,
      },
    };
  }

  const state = String(matched.status || 'pending').toLowerCase();
  const approved = state === 'approved';
  const rejected = [
    'rejected',
    'cancelled',
    'refunded',
    'charged_back',
  ].includes(state);

  return {
    approved,
    rejected,
    state,
    paymentId: matched.id ? String(matched.id) : null,
    data: {
      id: matched.id,
      status: matched.status,
      status_detail: matched.status_detail,
      external_reference: matched.external_reference,
      transaction_amount: matched.transaction_amount,
      currency_id: matched.currency_id,
      date_created: matched.date_created,
      date_approved: matched.date_approved,
      payment_method_id: matched.payment_method_id,
      payment_type_id: matched.payment_type_id,
    },
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', {headers: corsHeaders});
  if (req.method !== 'POST') return json({error:'Método no permitido'},405);
  try {
    const userSb = userClient(req);
    const {data:userData,error:userError} = await userSb.auth.getUser();
    if (userError || !userData.user) return json({error:'Sesión inválida'},401);
    const user = userData.user;
    const admin = adminClient();
    const body = await req.json().catch(()=>({}));
    const action = String(body.action || 'state');

    if (action === 'state') {
      const [{data:state,error},{data:catalog,error:catalogError}] = await Promise.all([
        userSb.rpc('my_driver_subscription_state'),
        userSb.rpc('driver_subscription_catalog_for_me'),
      ]);
      if (error) throw error;
      if (catalogError) throw catalogError;
      return json({
        ok:true,
        state,
        zone:catalog?.zone || null,
        plans:Array.isArray(catalog?.plans) ? catalog.plans : [],
        feature_enabled:catalog?.enabled === true,
        enforce_access:catalog?.enforce_access === true,
        provider:catalog?.provider || null,
        provider_enabled:catalog?.provider_enabled === true,
        provider_configured:catalog?.provider_configured === true,
        payment_provider_key:catalog?.payment_provider_key || null,
        payment_provider_label:catalog?.payment_provider_label || null,
      });
    }

    if (action === 'create') {
      const {data:catalog,error:catalogError} =
        await userSb.rpc('driver_subscription_catalog_for_me');
      if (catalogError) throw catalogError;
      if (!catalog?.zone) {
        return json({
          error:'Activa tu ubicación dentro de una zona de Express para ver planes'
        },409);
      }
      if (catalog.enabled !== true) {
        return json({
          error:'Las suscripciones no están habilitadas en esta zona'
        },409);
      }

      const providerKey = String(catalog?.payment_provider_key || '');
      const providerLabel = String(
        catalog?.payment_provider_label || 'El método de pago'
      );

      if (catalog.provider_enabled !== true) {
        return json({
          error: providerLabel + ' todavía no está disponible para suscripciones'
        },503);
      }

      const planId = Number(body.plan_id || 0);
      if (!planId) return json({error:'Plan inválido'},400);

      const zonePlans = Array.isArray(catalog.plans) ? catalog.plans : [];
      const plan = zonePlans.find(
        (item:any) => Number(item?.id) === planId
      );
      if (!plan) {
        return json({error:'Plan no disponible en tu zona actual'},404);
      }

      if (providerKey === 'mercado_pago') {
        const cfg = await mercadoPagoConfig(admin, String(catalog.zone.id));
        const expires = new Date(
          Date.now() + 30 * 60 * 1000
        ).toISOString();

        const {data:payment,error:paymentError} = await admin.rpc(
          'service_create_driver_subscription_payment',
          {
            p_driver_id:user.id,
            p_plan_id:planId,
            p_provider:'mercado_pago',
            p_expires_at:expires,
          },
        );
        if (paymentError) throw paymentError;

        if (payment.provider_order_id && payment.qr_payload) {
          return json({
            ok:true,
            provider:'mercado_pago',
            payment_id:payment.id,
            amount:payment.amount,
            currency_code:payment.currency_code,
            checkout_url:payment.qr_payload,
            status:payment.status,
            expires_at:payment.expires_at,
            reused:true,
            zone:catalog.zone,
          });
        }

        const created = await mercadoPagoCreate(
          cfg,
          payment,
          plan,
          user,
        );

        const {data:updated,error:updateError} = await admin.rpc(
          'service_update_driver_subscription_payment_provider',
          {
            p_payment_id:payment.id,
            p_provider_order_id:created.preferenceId,
            p_qr_payload:created.checkoutUrl,
            p_provider_data:{
              mercado_pago_preference:created.data,
              external_reference:created.externalReference,
            },
            p_expires_at:expires,
          },
        );
        if (updateError) throw updateError;

        return json({
          ok:true,
          provider:'mercado_pago',
          payment_id:updated.id,
          amount:updated.amount,
          currency_code:updated.currency_code,
          checkout_url:created.checkoutUrl,
          status:updated.status,
          expires_at:updated.expires_at,
          reused:false,
          zone:catalog.zone,
        });
      }

      if (providerKey !== 'veripagos_qr') {
        return json({
          error:providerLabel + ' no está soportado para suscripciones'
        },503);
      }

      const {data:cfg,error:cfgError} =
        await admin.rpc('service_get_driver_subscription_provider_settings');
      if (cfgError) throw cfgError;
      if (
        !cfg?.api_base_url ||
        !cfg?.create_path ||
        !cfg?.username ||
        !cfg?.password ||
        !cfg?.secret_key
      ) {
        return json({error:'VeriPagos no está completamente configurado'},503);
      }

      const expires = new Date(
        Date.now() +
        validityMinutes(String(catalog.qr_validity || '0/00:15')) * 60000
      ).toISOString();

      const {data:payment,error:paymentError} = await admin.rpc(
        'service_create_driver_subscription_payment',
        {
          p_driver_id:user.id,
          p_plan_id:planId,
          p_provider:'veripagos',
          p_expires_at:expires,
        },
      );
      if (paymentError) throw paymentError;

      if (payment.qr_payload && payment.provider_order_id) {
        return json({
          ok:true,
          provider:'veripagos',
          payment_id:payment.id,
          amount:payment.amount,
          currency_code:payment.currency_code,
          qr:payment.qr_payload,
          status:payment.status,
          expires_at:payment.expires_at,
          reused:true,
          zone:catalog.zone,
        });
      }

      const created = await providerCreate(cfg,catalog,payment,plan);
      const {data:updated,error:updateError} = await admin.rpc(
        'service_update_driver_subscription_payment_provider',
        {
          p_payment_id:payment.id,
          p_provider_order_id:created.movement,
          p_qr_payload:created.qr,
          p_provider_data:created.data,
          p_expires_at:expires,
        },
      );
      if (updateError) throw updateError;

      return json({
        ok:true,
        provider:'veripagos',
        payment_id:updated.id,
        amount:updated.amount,
        currency_code:updated.currency_code,
        qr:updated.qr_payload,
        status:updated.status,
        expires_at:updated.expires_at,
        reused:false,
        zone:catalog.zone,
      });
    }

    const paymentId = Number(body.payment_id || 0);
    if (!paymentId) return json({error:'Pago inválido'},400);
    const {data:payment,error:paymentError} = await admin.from('driver_subscription_payments').select('*').eq('id',paymentId).eq('driver_id',user.id).single();
    if (paymentError || !payment) return json({error:'Pago no encontrado'},404);

    if (action === 'cancel') {
      if (payment.status !== 'pending') return json({ok:true,status:payment.status});
      const {data:cancelled,error} = await admin.rpc('service_cancel_driver_subscription_payment',{p_payment_id:payment.id,p_status:'cancelled',p_provider_data:{cancelled_by_driver:true}});
      if (error) throw error;
      return json({ok:true,status:cancelled?.status || 'cancelled'});
    }

    if (action === 'verify' || action === 'resume') {
      if (payment.status === 'approved') {
        return json({
          ok:true,
          approved:true,
          status:'approved',
          provider:payment.provider,
          payment_id:payment.id,
        });
      }

      if (payment.provider === 'mercado_pago') {
        const {data:catalog,error:catalogError} =
          await userSb.rpc('driver_subscription_catalog_for_me');
        if (catalogError) throw catalogError;
        if (!catalog?.zone?.id) {
          return json({error:'No se pudo determinar la zona del conductor'},409);
        }

        const cfg = await mercadoPagoConfig(
          admin,
          String(catalog.zone.id),
        );
        const checked = await mercadoPagoStatus(cfg,payment);

        if (checked.approved) {
          const {data:finalized,error} = await admin.rpc(
            'service_finalize_driver_subscription_payment',
            {
              p_payment_id:payment.id,
              p_provider_order_id:checked.paymentId,
              p_provider_data:{
                mercado_pago_payment:checked.data,
              },
            },
          );
          if (error) throw error;

          return json({
            ok:true,
            approved:true,
            status:'approved',
            provider:'mercado_pago',
            payment_id:payment.id,
            provider_payment_id:checked.paymentId,
            subscription:finalized,
            checkout_url:payment.qr_payload,
            amount:payment.amount,
            currency_code:payment.currency_code,
          });
        }

        if (checked.rejected && payment.status === 'pending') {
          await admin.rpc(
            'service_cancel_driver_subscription_payment',
            {
              p_payment_id:payment.id,
              p_status:'rejected',
              p_provider_data:{
                mercado_pago_payment:checked.data,
              },
            },
          );
          return json({
            ok:true,
            approved:false,
            status:'rejected',
            provider:'mercado_pago',
            payment_id:payment.id,
            checkout_url:payment.qr_payload,
            amount:payment.amount,
            currency_code:payment.currency_code,
          });
        }

        return json({
          ok:true,
          approved:false,
          status:checked.state || 'pending',
          provider:'mercado_pago',
          payment_id:payment.id,
          checkout_url:payment.qr_payload,
          amount:payment.amount,
          currency_code:payment.currency_code,
          expires_at:payment.expires_at,
        });
      }

      if (!payment.provider_order_id) {
        return json({
          error:'El pago todavía no tiene movimiento VeriPagos'
        },409);
      }

      const {data:cfg,error:cfgError} =
        await admin.rpc('service_get_driver_subscription_provider_settings');
      if (cfgError) throw cfgError;

      const checked = await providerStatus(cfg,payment);
      if (checked.approved) {
        const {data:finalized,error} = await admin.rpc(
          'service_finalize_driver_subscription_payment',
          {
            p_payment_id:payment.id,
            p_provider_order_id:payment.provider_order_id,
            p_provider_data:checked.data,
          },
        );
        if (error) throw error;
        return json({
          ok:true,
          approved:true,
          status:'approved',
          provider:'veripagos',
          payment_id:payment.id,
          subscription:finalized,
          qr:payment.qr_payload,
          amount:payment.amount,
          currency_code:payment.currency_code,
        });
      }

      if (checked.rejected && payment.status === 'pending') {
        await admin.rpc(
          'service_cancel_driver_subscription_payment',
          {
            p_payment_id:payment.id,
            p_status:'rejected',
            p_provider_data:checked.data,
          },
        );
        return json({
          ok:true,
          approved:false,
          status:'rejected',
          provider:'veripagos',
          payment_id:payment.id,
          qr:payment.qr_payload,
          amount:payment.amount,
          currency_code:payment.currency_code,
          expires_at:payment.expires_at,
        });
      }

      const expired =
        payment.expires_at &&
        new Date(payment.expires_at).getTime() <= Date.now();

      if (expired && payment.status === 'pending') {
        await admin.rpc(
          'service_cancel_driver_subscription_payment',
          {
            p_payment_id:payment.id,
            p_status:'expired',
            p_provider_data:checked.data,
          },
        );
        return json({
          ok:true,
          approved:false,
          status:'expired',
          provider:'veripagos',
          payment_id:payment.id,
          qr:payment.qr_payload,
          amount:payment.amount,
          currency_code:payment.currency_code,
          expires_at:payment.expires_at,
        });
      }

      return json({
        ok:true,
        approved:false,
        status:checked.state || payment.status,
        provider:'veripagos',
        payment_id:payment.id,
        qr:payment.qr_payload,
        amount:payment.amount,
        currency_code:payment.currency_code,
        expires_at:payment.expires_at,
      });
    }

    return json({error:'Acción no soportada'},400);
  } catch (error) {
    console.error('driver-subscription-payments', error);
    return json({ok:false,error:error instanceof Error?error.message:String(error)},500);
  }
});
