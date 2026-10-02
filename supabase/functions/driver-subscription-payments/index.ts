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
    data,
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
      const {data:state,error} = await userSb.rpc('my_driver_subscription_state');
      if (error) throw error;
      const {data:plans,error:plansError} = await userSb.from('driver_subscription_plans').select('*').eq('active',true).order('sort_order');
      if (plansError) throw plansError;
      return json({ok:true,state,plans:plans || []});
    }

    const {data:settings,error:settingsError} = await admin.from('driver_subscription_settings').select('*').eq('id',true).single();
    if (settingsError) throw settingsError;

    if (action === 'create') {
      if (!settings.enabled) return json({error:'Las suscripciones no están habilitadas'},409);
      if (!settings.provider_enabled) return json({error:'QR Bolivia todavía está en configuración'},503);
      const planId = Number(body.plan_id || 0);
      if (!planId) return json({error:'Plan inválido'},400);
      const {data:plan,error:planError} = await admin.from('driver_subscription_plans').select('*').eq('id',planId).eq('active',true).single();
      if (planError || !plan) return json({error:'Plan no disponible'},404);
      const {data:cfg,error:cfgError} = await admin.rpc('service_get_driver_subscription_provider_settings');
      if (cfgError) throw cfgError;
      if (!cfg?.api_base_url || !cfg?.create_path || !cfg?.username || !cfg?.password || !cfg?.secret_key) {
        return json({error:'VeriPagos no está completamente configurado'},503);
      }
      const expires = new Date(Date.now()+validityMinutes(settings.qr_validity)*60000).toISOString();
      const {data:payment,error:paymentError} = await admin.rpc('service_create_driver_subscription_payment',{
        p_driver_id:user.id,p_plan_id:planId,p_provider:'veripagos',p_expires_at:expires
      });
      if (paymentError) throw paymentError;
      if (payment.qr_payload && payment.provider_order_id) {
        return json({ok:true,payment_id:payment.id,amount:payment.amount,currency_code:payment.currency_code,qr:payment.qr_payload,status:payment.status,expires_at:payment.expires_at,reused:true});
      }
      const created = await providerCreate(cfg,settings,payment,plan);
      const {data:updated,error:updateError} = await admin.rpc('service_update_driver_subscription_payment_provider',{
        p_payment_id:payment.id,p_provider_order_id:created.movement,p_qr_payload:created.qr,
        p_provider_data:created.data,p_expires_at:expires
      });
      if (updateError) throw updateError;
      return json({ok:true,payment_id:updated.id,amount:updated.amount,currency_code:updated.currency_code,qr:updated.qr_payload,status:updated.status,expires_at:updated.expires_at,reused:false});
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
        return json({ok:true,approved:true,status:'approved',payment_id:payment.id});
      }
      if (!payment.provider_order_id) return json({error:'El pago todavía no tiene movimiento VeriPagos'},409);
      const {data:cfg,error:cfgError} = await admin.rpc('service_get_driver_subscription_provider_settings');
      if (cfgError) throw cfgError;
      const checked = await providerStatus(cfg,payment);
      if (checked.approved) {
        const {data:finalized,error} = await admin.rpc('service_finalize_driver_subscription_payment',{
          p_payment_id:payment.id,p_provider_order_id:payment.provider_order_id,p_provider_data:checked.data
        });
        if (error) throw error;
        return json({ok:true,approved:true,status:'approved',payment_id:payment.id,subscription:finalized,qr:payment.qr_payload,amount:payment.amount,currency_code:payment.currency_code});
      }
      if (checked.rejected && payment.status === 'pending') {
        await admin.rpc('service_cancel_driver_subscription_payment',{
          p_payment_id:payment.id,
          p_status:'rejected',
          p_provider_data:checked.data,
        });
        return json({
          ok:true,
          approved:false,
          status:'rejected',
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
        await admin.rpc('service_cancel_driver_subscription_payment',{
          p_payment_id:payment.id,
          p_status:'expired',
          p_provider_data:checked.data,
        });
        return json({
          ok:true,
          approved:false,
          status:'expired',
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
