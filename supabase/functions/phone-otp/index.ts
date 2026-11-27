// Verificación del teléfono por SMS con Unimatrix (solo Bolivia, +591).
// Unimatrix genera y valida el código (otp.send / otp.verify); aquí solo se
// controlan límites de uso y se registra el intento en phone_otp_challenges.
// Las claves viven únicamente en los secretos de Edge Functions:
//   UNIMTX_ACCESS_KEY_ID, UNIMTX_ACCESS_KEY_SECRET (opcional), UNIMTX_AUTH_MODE (opcional).
import {createClient} from 'npm:@supabase/supabase-js@2.95.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const otpTtlSeconds = 300;
const resendCooldownSeconds = 60;
const maxDailyRequestsPerUser = 10;
const maxDailyRequestsPerPhone = 6;
const maxVerifyAttempts = 5;
const dialCode = '+591';
const unimatrixIntent = 'express_phone_verify';

class HttpError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

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
  if (!raw) throw new Error('No hay clave de servicio Supabase disponible');
  const parsed = JSON.parse(raw);
  if (!parsed.default) throw new Error('No hay secret key default');
  return parsed.default;
}

function adminClient() {
  return createClient(Deno.env.get('SUPABASE_URL')!, serviceKey(), {
    auth: {persistSession: false, autoRefreshToken: false},
  });
}

async function requireUser(req: Request) {
  const authorization = req.headers.get('authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) {
    throw new HttpError(401, 'session_required', 'Sesión requerida');
  }
  const client = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    {
      global: {headers: {Authorization: authorization}},
      auth: {persistSession: false, autoRefreshToken: false},
    },
  );
  const token = authorization.replace(/^Bearer\s+/i, '');
  const {data, error} = await client.auth.getUser(token);
  if (error || !data.user) {
    throw new HttpError(401, 'invalid_session', 'Sesión inválida');
  }
  return data.user;
}

function normalizePhone(value: unknown) {
  const phone = '+' + String(value ?? '').replace(/\D/g, '');
  if (!/^\+[1-9][0-9]{6,14}$/.test(phone)) {
    throw new HttpError(400, 'invalid_phone', 'Número de teléfono inválido');
  }
  if (!phone.startsWith(dialCode)) {
    throw new HttpError(
      400, 'country_not_supported',
      'La verificación por SMS solo está disponible para números de Bolivia (+591)',
    );
  }
  return phone;
}

function randomHex(bytesLength = 16) {
  const bytes = new Uint8Array(bytesLength);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (v) => v.toString(16).padStart(2, '0')).join('');
}

async function hmacSha256Base64(secret: string, value: string) {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    {name: 'HMAC', hash: 'SHA-256'}, false, ['sign'],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value)),
  );
  let binary = '';
  for (const v of sig) binary += String.fromCharCode(v);
  return btoa(binary);
}

async function unimatrixUrl(action: string) {
  const accessKeyId = Deno.env.get('UNIMTX_ACCESS_KEY_ID') ?? '';
  if (!accessKeyId) {
    throw new HttpError(503, 'provider_not_configured', 'Proveedor SMS no configurado');
  }
  const params: Record<string, string> = {action, accessKeyId};
  const secret = Deno.env.get('UNIMTX_ACCESS_KEY_SECRET') ?? '';
  const configured = (Deno.env.get('UNIMTX_AUTH_MODE') ?? '').trim().toLowerCase();
  const authMode = configured || (secret ? 'hmac' : 'simple');
  if (authMode === 'hmac') {
    if (!secret) {
      throw new HttpError(503, 'provider_not_configured', 'Proveedor SMS no configurado');
    }
    params.algorithm = 'hmac-sha256';
    params.timestamp = Date.now().toString();
    params.nonce = randomHex(16);
    const signingText = Object.keys(params).sort()
      .map((k) => k + '=' + params[k]).join('&');
    params.signature = await hmacSha256Base64(secret, signingText);
  }
  const url = new URL(Deno.env.get('UNIMTX_API_URL') ?? 'https://api.unimtx.com/');
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return url;
}

async function sendOtp(phone: string) {
  const response = await fetch(await unimatrixUrl('otp.send'), {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    body: JSON.stringify({to: phone, intent: unimatrixIntent, channel: 'sms', ttl: otpTtlSeconds}),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || String(payload?.code ?? '') !== '0') {
    console.error('unimatrix send failed', response.status, payload?.code, payload?.message);
    throw new HttpError(502, 'provider_send_failed', 'No se pudo enviar el SMS. Inténtalo en unos minutos.');
  }
  return {messageId: String(payload?.data?.id ?? ''), price: payload?.data?.price ?? null};
}

async function checkOtp(phone: string, code: string) {
  const response = await fetch(await unimatrixUrl('otp.verify'), {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    body: JSON.stringify({to: phone, code, intent: unimatrixIntent, ttl: otpTtlSeconds}),
  });
  const payload = await response.json().catch(() => ({}));
  return response.ok && String(payload?.code ?? '') === '0' && payload?.data?.valid === true;
}

async function accountChannel(admin: ReturnType<typeof adminClient>, userId: string) {
  const {data} = await admin.from('account_runtime_bindings')
    .select('environment').eq('user_id', userId).maybeSingle();
  return data?.environment === 'preview' ? 'preview' : 'production';
}

async function enforceRateLimits(admin: ReturnType<typeof adminClient>, userId: string, phone: string) {
  const cooldownSince = new Date(Date.now() - resendCooldownSeconds * 1000).toISOString();
  const {count: recent, error: e1} = await admin.from('phone_otp_challenges')
    .select('id', {count: 'exact', head: true})
    .eq('user_id', userId).eq('phone', phone).gte('created_at', cooldownSince);
  if (e1) throw e1;
  if ((recent ?? 0) > 0) {
    throw new HttpError(429, 'resend_cooldown', 'Espera 60 segundos antes de pedir otro código');
  }
  const daySince = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const [u, p] = await Promise.all([
    admin.from('phone_otp_challenges').select('id', {count: 'exact', head: true})
      .eq('user_id', userId).gte('created_at', daySince),
    admin.from('phone_otp_challenges').select('id', {count: 'exact', head: true})
      .eq('phone', phone).gte('created_at', daySince),
  ]);
  if (u.error) throw u.error;
  if (p.error) throw p.error;
  if ((u.count ?? 0) >= maxDailyRequestsPerUser || (p.count ?? 0) >= maxDailyRequestsPerPhone) {
    throw new HttpError(429, 'daily_rate_limit', 'Alcanzaste el límite de códigos de hoy. Inténtalo mañana.');
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', {headers: corsHeaders});
  if (req.method !== 'POST') return json({ok: false, code: 'method_not_allowed'}, 405);

  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const action = String(body?.action ?? '').trim().toLowerCase();
    const admin = adminClient();

    // El servidor decide si hay que verificar: interruptor de la base de datos.
    const {data: settings} = await admin.from('app_settings')
      .select('sms_verification_passenger_enabled, sms_verification_driver_enabled')
      .eq('id', true).maybeSingle();
    if (!settings?.sms_verification_passenger_enabled && !settings?.sms_verification_driver_enabled) {
      throw new HttpError(409, 'sms_disabled', 'La verificación por SMS no está activa');
    }

    if (action === 'send') {
      const phone = normalizePhone(body?.phone);
      await enforceRateLimits(admin, user.id, phone);
      const channel = await accountChannel(admin, user.id);
      const sent = await sendOtp(phone);
      const now = Date.now();
      const {error} = await admin.from('phone_otp_challenges').insert({
        id: crypto.randomUUID(),
        user_id: user.id,
        channel,
        country_code: 'BO',
        phone,
        provider: 'unimatrix',
        provider_message_id: sent.messageId || null,
        status: 'sent',
        max_attempts: maxVerifyAttempts,
        expires_at: new Date(now + otpTtlSeconds * 1000).toISOString(),
        sent_at: new Date(now).toISOString(),
        provider_meta: {price: sent.price},
        updated_at: new Date(now).toISOString(),
      });
      if (error) throw error;
      return json({ok: true, status: 'sent', expires_in: otpTtlSeconds, resend_in: resendCooldownSeconds});
    }

    if (action === 'verify') {
      const phone = normalizePhone(body?.phone);
      const code = String(body?.code ?? '').replace(/\D/g, '');
      if (code.length < 4 || code.length > 8) {
        throw new HttpError(400, 'invalid_code', 'Código inválido');
      }
      const {data: challenge, error} = await admin.from('phone_otp_challenges')
        .select('*').eq('user_id', user.id).eq('phone', phone).eq('status', 'sent')
        .order('created_at', {ascending: false}).limit(1).maybeSingle();
      if (error) throw error;
      if (!challenge) throw new HttpError(404, 'no_challenge', 'Pide un código nuevo');
      if (new Date(challenge.expires_at).getTime() < Date.now()) {
        await admin.from('phone_otp_challenges')
          .update({status: 'expired', updated_at: new Date().toISOString()}).eq('id', challenge.id);
        throw new HttpError(410, 'code_expired', 'El código venció. Pide uno nuevo.');
      }
      const attempts = (challenge.attempts ?? 0) + 1;
      const valid = await checkOtp(phone, code);
      if (!valid) {
        await admin.from('phone_otp_challenges').update({
          attempts,
          status: attempts >= (challenge.max_attempts ?? maxVerifyAttempts) ? 'failed' : 'sent',
          error_code: 'invalid_code',
          updated_at: new Date().toISOString(),
        }).eq('id', challenge.id);
        throw new HttpError(
          422, attempts >= (challenge.max_attempts ?? maxVerifyAttempts) ? 'too_many_attempts' : 'wrong_code',
          attempts >= (challenge.max_attempts ?? maxVerifyAttempts)
            ? 'Demasiados intentos. Pide un código nuevo.'
            : 'Código incorrecto',
        );
      }
      const verifiedAt = new Date().toISOString();
      const {error: userError} = await admin.from('users').update({
        phone, phone_country_code: 'BO', phone_verified_at: verifiedAt, updated_at: verifiedAt,
      }).eq('id', user.id);
      if (userError) throw userError;
      await admin.from('phone_otp_challenges').update({
        attempts, status: 'verified', verified_at: verifiedAt, updated_at: verifiedAt, error_code: null,
      }).eq('id', challenge.id);
      return json({ok: true, verified: true, verified_at: verifiedAt});
    }

    return json({ok: false, code: 'unsupported_action'}, 400);
  } catch (error) {
    if (error instanceof HttpError) {
      return json({ok: false, code: error.code, message: error.message}, error.status);
    }
    console.error('phone-otp error', error);
    return json({ok: false, code: 'internal_error', message: 'No se pudo completar la verificación'}, 500);
  }
});
