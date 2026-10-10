import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-retry-count, traceparent, tracestate, baggage',
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

async function assertAdmin(req: Request) {
  const authorization = req.headers.get('authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) {
    throw new Error('Sesión administrativa requerida');
  }
  const client = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      global: {headers: {Authorization: authorization}},
      auth: {persistSession: false, autoRefreshToken: false},
    },
  );
  const {data: allowed, error} = await client.rpc('is_admin');
  if (error || allowed !== true) throw new Error('No autorizado');
  // E1-20261010: payment credentials are Production data; a Preview-only
  // administrator must not read or change them.
  const {data: prodAllowed, error: prodError} = await client.rpc(
    'admin_environment_allowed',
    {p_channel: 'production'},
  );
  if (prodError || prodAllowed !== true) throw new Error('No autorizado para Producción');
  const {data, error: userError} = await client.auth.getUser();
  if (userError || !data.user) throw new Error('Sesión inválida');
  return data.user;
}

async function verifyMercadoPago(accessToken: string) {
  if (!accessToken) throw new Error('Ingresa el Access Token de Mercado Pago');

  const response = await fetch('https://api.mercadolibre.com/users/me', {
    headers: {
      Authorization: 'Bearer ' + accessToken,
      Accept: 'application/json',
    },
  });

  const raw = await response.text();
  let data: any = {};
  try {
    data = raw ? JSON.parse(raw) : {};
  } catch {
    data = {raw};
  }

  if (!response.ok) {
    throw new Error(
      data?.message ||
        data?.error ||
        ('Mercado Pago respondió HTTP ' + response.status),
    );
  }

  const siteId = String(data?.site_id || '').toUpperCase();
  if (siteId && siteId !== 'MLC') {
    throw new Error(
      'Las credenciales corresponden al sitio ' +
        siteId +
        '. Para Iquique se requieren credenciales de Mercado Pago Chile (MLC).',
    );
  }

  return {
    id: data?.id == null ? null : String(data.id),
    nickname: data?.nickname == null ? null : String(data.nickname),
    email: data?.email == null ? null : String(data.email),
    site_id: siteId || 'MLC',
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }
  if (req.method !== 'POST') return json({error: 'Método no permitido'}, 405);

  try {
    const caller = await assertAdmin(req);
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      serviceKey(),
      {auth: {persistSession: false, autoRefreshToken: false}},
    );
    const body = await req.json().catch(() => ({}));
    const action = String(body.action || 'get');
    const zoneId = String(body.zone_id || '').trim();
    if (!zoneId) return json({ok: false, error: 'Zona requerida'}, 400);

    const {data: zone, error: zoneError} = await admin
      .from('service_zones')
      .select('id,zone_key,name,country,currency_code,payment_provider,payment_enabled')
      .eq('id', zoneId)
      .single();
    if (zoneError || !zone) {
      return json({ok: false, error: 'Zona no encontrada'}, 404);
    }
    if (String(zone.country || '').toLowerCase() !== 'chile') {
      return json(
        {ok: false, error: 'Mercado Pago solo se configura para zonas de Chile'},
        409,
      );
    }

    const currentRes = await admin.rpc(
      'service_get_zone_payment_provider_settings',
      {p_zone_id: zoneId},
    );
    if (currentRes.error) throw currentRes.error;
    const current = currentRes.data || {};
    const currentExtra = current?.extra_config || {};

    if (action === 'get') {
      return json({
        ok: true,
        zone,
        provider: 'mercado_pago',
        configured: !!(
          current?.access_token &&
          currentExtra?.verified_at &&
          currentExtra?.site_id === 'MLC'
        ),
        credentials_configured: !!current?.access_token,
        settings: {
          public_key: current?.public_key || '',
          has_access_token: !!current?.access_token,
          verified_at: currentExtra?.verified_at || null,
          account_id: currentExtra?.account_id || null,
          nickname: currentExtra?.nickname || null,
          account_email: currentExtra?.account_email || null,
          site_id: currentExtra?.site_id || null,
        },
      });
    }

    if (action === 'save_and_verify' || action === 'verify') {
      const publicKey = String(
        body.public_key || current?.public_key || '',
      ).trim();
      const accessToken = String(
        body.access_token || current?.access_token || '',
      ).trim();
      const verified = await verifyMercadoPago(accessToken);

      const extra = {
        ...currentExtra,
        verified_at: new Date().toISOString(),
        account_id: verified.id,
        nickname: verified.nickname,
        account_email: verified.email,
        site_id: verified.site_id,
      };

      const {data: saved, error: saveError} = await admin.rpc(
        'service_set_zone_payment_provider_settings',
        {
          p_zone_id: zoneId,
          p_provider: 'mercado_pago',
          p_public_key: publicKey,
          p_access_token: accessToken,
          p_extra_config: extra,
          p_updated_by: caller.id,
        },
      );
      if (saveError) throw saveError;

      await admin
        .from('service_zones')
        .update({
          payment_provider: 'mercado_pago',
          payment_enabled: true,
          updated_at: new Date().toISOString(),
        })
        .eq('id', zoneId);

      return json({
        ok: true,
        configured: true,
        connected: true,
        provider: 'mercado_pago',
        zone_id: zoneId,
        account: {
          id: verified.id,
          nickname: verified.nickname,
          email: verified.email,
          site_id: verified.site_id,
        },
        settings: {
          public_key: saved?.public_key || publicKey,
          has_access_token: true,
          verified_at: extra.verified_at,
        },
        message: 'Mercado Pago Chile conectado y verificado.',
      });
    }

    return json({ok: false, error: 'Acción no soportada'}, 400);
  } catch (error) {
    console.error('zone-payment-admin', error);
    return json(
      {
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});
