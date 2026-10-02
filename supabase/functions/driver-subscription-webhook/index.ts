import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200, extraHeaders: Record<string,string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      ...extraHeaders,
      'Content-Type': 'application/json',
    },
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

function adminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    serviceKey(),
    {auth: {persistSession: false, autoRefreshToken: false}},
  );
}

function decodeBasic(header: string | null) {
  if (!header || !header.toLowerCase().startsWith('basic ')) return null;
  try {
    const decoded = atob(header.slice(6).trim());
    const index = decoded.indexOf(':');
    if (index < 0) return null;
    return {
      username: decoded.slice(0, index),
      password: decoded.slice(index + 1),
    };
  } catch {
    return null;
  }
}

function safeEqual(a: string, b: string) {
  const aa = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  let diff = aa.length ^ bb.length;
  const len = Math.max(aa.length, bb.length);
  for (let i = 0; i < len; i++) {
    diff |= (aa[i % Math.max(aa.length, 1)] ?? 0) ^
      (bb[i % Math.max(bb.length, 1)] ?? 0);
  }
  return diff === 0;
}

function findMovementId(value: any): string | null {
  if (value == null) return null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findMovementId(item);
      if (found) return found;
    }
    return null;
  }
  if (typeof value !== 'object') return null;

  for (const key of ['movimiento_id', 'movimientoId', 'movement_id', 'movementId']) {
    if (value[key] != null && String(value[key]).trim()) {
      return String(value[key]).trim();
    }
  }

  for (const item of Object.values(value)) {
    const found = findMovementId(item);
    if (found) return found;
  }
  return null;
}

function joinUrl(base: string, path: string) {
  return base.replace(/\/$/, '') + '/' + path.replace(/^\//, '');
}

async function verifyWithVeriPagos(cfg: any, movementId: string) {
  if (!cfg?.api_base_url || !cfg?.status_path) {
    throw new Error('VeriPagos no tiene ruta de verificación configurada');
  }
  if (!cfg?.username || !cfg?.password || !cfg?.secret_key) {
    throw new Error('VeriPagos no tiene credenciales completas');
  }

  const response = await fetch(
    joinUrl(String(cfg.api_base_url), String(cfg.status_path)),
    {
      method: 'POST',
      headers: {
        'Authorization':
          'Basic ' + btoa(String(cfg.username) + ':' + String(cfg.password)),
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify({
        secret_key: String(cfg.secret_key),
        movimiento_id: movementId,
      }),
    },
  );

  const raw = await response.text();
  let data: any = {};
  try {
    data = raw ? JSON.parse(raw) : {};
  } catch {
    data = {raw};
  }

  if (!response.ok) {
    throw new Error(
      data?.Mensaje ||
      data?.message ||
      ('VeriPagos respondió HTTP ' + response.status)
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

  return {
    approved: state === 'completado',
    state,
    safeData: {
      Codigo: data?.Codigo,
      Mensaje: data?.Mensaje,
      Data: {
        movimiento_id: providerData?.movimiento_id,
        monto: providerData?.monto,
        detalle: providerData?.detalle,
        estado: providerData?.estado,
        estado_notificacion: providerData?.estado_notificacion,
      },
    },
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }
  if (req.method !== 'POST') {
    return json({ok: false, error: 'Método no permitido'}, 405);
  }

  try {
    const admin = adminClient();

    const {data: cfg, error: cfgError} = await admin.rpc(
      'service_get_driver_subscription_provider_settings'
    );
    if (cfgError) throw cfgError;

    const basic = decodeBasic(req.headers.get('authorization'));
    const authOk = basic &&
      safeEqual(String(basic.username), String(cfg?.username || '')) &&
      safeEqual(String(basic.password), String(cfg?.password || ''));

    if (!authOk) {
      return json(
        {ok: false, error: 'No autorizado'},
        401,
        {'WWW-Authenticate': 'Basic realm="Express VeriPagos"'},
      );
    }

    const body = await req.json().catch(() => ({}));
    const movementId = findMovementId(body);

    if (!movementId) {
      return json({
        ok: true,
        accepted: true,
        ignored: true,
        reason: 'Webhook recibido sin movimiento_id',
      });
    }

    const {data: payment, error: paymentError} = await admin
      .from('driver_subscription_payments')
      .select('*')
      .eq('provider', 'veripagos')
      .eq('provider_order_id', movementId)
      .maybeSingle();

    if (paymentError) throw paymentError;

    if (!payment) {
      return json({
        ok: true,
        accepted: true,
        ignored: true,
        reason: 'Movimiento no pertenece a una suscripción Express',
      });
    }

    if (payment.status === 'approved') {
      return json({
        ok: true,
        accepted: true,
        approved: true,
        already_approved: true,
        payment_id: payment.id,
      });
    }

    const checked = await verifyWithVeriPagos(cfg, movementId);

    if (checked.approved) {
      const {data: finalized, error: finalizeError} = await admin.rpc(
        'service_finalize_driver_subscription_payment',
        {
          p_payment_id: payment.id,
          p_provider_order_id: movementId,
          p_provider_data: checked.safeData,
        },
      );
      if (finalizeError) throw finalizeError;

      return json({
        ok: true,
        accepted: true,
        approved: true,
        payment_id: payment.id,
        subscription: finalized,
      });
    }

    return json({
      ok: true,
      accepted: true,
      approved: false,
      status: checked.state || 'pendiente',
      payment_id: payment.id,
    });
  } catch (error) {
    console.error('driver-subscription-webhook', error);
    return json({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});
