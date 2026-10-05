import {createClient} from 'npm:@supabase/supabase-js@2.95.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const firebaseDailyFreeLimit = 10;
const otpTtlSeconds = 300;
const firebaseChallengeTtlSeconds = 600;
const resendCooldownSeconds = 60;
const maxDailyRequestsPerUser = 20;
const maxDailyRequestsPerPhone = 10;
const unimatrixIntent = 'express_phone_verify';

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

function normalizeChannel(value: unknown) {
  return String(value ?? '').trim().toLowerCase() === 'preview'
    ? 'preview'
    : 'production';
}

function normalizeCountry(value: unknown) {
  const country = String(value ?? '').trim().toUpperCase();
  if (country !== 'CL' && country !== 'BO') {
    throw new Error('País no habilitado para verificación telefónica');
  }
  return country;
}

function normalizePhone(value: unknown) {
  const raw = String(value ?? '').trim();
  const phone = '+' + raw.replace(/\D/g, '');
  if (!/^\+[1-9][0-9]{6,14}$/.test(phone)) {
    throw new Error('Número de teléfono inválido');
  }
  return phone;
}

function assertPhoneCountry(phone: string, country: string) {
  const dial = country === 'CL' ? '+56' : '+591';
  if (!phone.startsWith(dial)) {
    throw new Error('El número no coincide con el país seleccionado');
  }
}

function packageForChannel(channel: string) {
  return channel === 'preview'
    ? 'com.express.usuario.preview'
    : 'com.express.usuario1';
}

async function resolveFirebaseConfig(channel: string) {
  const base = Deno.env.get('SUPABASE_URL');
  if (!base) throw new Error('SUPABASE_URL no disponible');
  const url = new URL(base + '/functions/v1/express-push-dispatch');
  url.searchParams.set('client_config', 'android');
  url.searchParams.set('package', packageForChannel(channel));

  const response = await fetch(url, {
    headers: {'Accept': 'application/json'},
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload?.found !== true) {
    throw new Error('Firebase no está configurado para este entorno');
  }
  const apiKey = String(payload.apiKey ?? '');
  const projectId = String(payload.projectId ?? '');
  if (!apiKey || !projectId) {
    throw new Error('Configuración Firebase incompleta');
  }
  return {apiKey, projectId};
}

function randomDigits(length = 6) {
  const bytes = new Uint32Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (value) => String(value % 10)).join('');
}

function randomHex(bytesLength = 16) {
  const bytes = new Uint8Array(bytesLength);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = '';
  for (const value of bytes) binary += String.fromCharCode(value);
  return btoa(binary);
}

async function hmacSha256Base64(secret: string, value: string) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    {name: 'HMAC', hash: 'SHA-256'},
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(value));
  return bytesToBase64(new Uint8Array(signature));
}

function constantTimeEqual(left: string, right: string) {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let i = 0; i < left.length; i++) {
    mismatch |= left.charCodeAt(i) ^ right.charCodeAt(i);
  }
  return mismatch === 0;
}

async function challengeCodeHash(
  challengeId: string,
  phone: string,
  code: string,
) {
  const pepper = Deno.env.get('PHONE_OTP_PEPPER') ?? '';
  if (!pepper) {
    throw new Error('PHONE_OTP_PEPPER no configurado');
  }
  return await hmacSha256Base64(
    pepper,
    challengeId + ':' + phone + ':' + code,
  );
}

async function sendLetel(phone: string, code: string) {
  const apiKey = Deno.env.get('LETEL_API_KEY') ?? '';
  if (!apiKey) throw new Error('LETEL_API_KEY no configurada');
  const endpoint =
    Deno.env.get('LETEL_API_URL') ?? 'https://api.letel.cl/v1/sms/send';
  const sender = Deno.env.get('LETEL_SENDER_ID') ?? 'EXPRESS';
  const message =
    'Express: tu codigo de verificacion es ' + code + '. Vence en 5 min.';

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ' + apiKey,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: JSON.stringify({phone, message, sender}),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload?.success === false) {
    const detail = String(payload?.message ?? payload?.error ?? response.status);
    throw new Error('LETEL_SEND_FAILED:' + detail);
  }
  return {
    messageId: String(payload?.messageId ?? payload?.id ?? ''),
    rawStatus: String(payload?.status ?? 'sent'),
  };
}

async function unimatrixUrl(action: string) {
  const accessKeyId = Deno.env.get('UNIMTX_ACCESS_KEY_ID') ?? '';
  if (!accessKeyId) throw new Error('UNIMTX_ACCESS_KEY_ID no configurada');

  const params: Record<string, string> = {action, accessKeyId};
  const secret = Deno.env.get('UNIMTX_ACCESS_KEY_SECRET') ?? '';
  if (secret) {
    params.algorithm = 'hmac-sha256';
    params.timestamp = Date.now().toString();
    params.nonce = randomHex(16);
    const signingText = Object.keys(params)
      .sort()
      .map((key) => key + '=' + params[key])
      .join('&');
    params.signature = await hmacSha256Base64(secret, signingText);
  }

  const endpoint = Deno.env.get('UNIMTX_API_URL') ?? 'https://api.unimtx.com/';
  const url = new URL(endpoint);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }
  return url;
}

async function sendUnimatrixOtp(phone: string) {
  const url = await unimatrixUrl('otp.send');
  const response = await fetch(url, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    body: JSON.stringify({
      to: phone,
      intent: unimatrixIntent,
      channel: 'sms',
      ttl: otpTtlSeconds,
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || String(payload?.code ?? '') !== '0') {
    throw new Error(
      'UNIMATRIX_SEND_FAILED:' +
        String(payload?.message ?? payload?.code ?? response.status),
    );
  }
  return {
    messageId: String(payload?.data?.id ?? ''),
    price: payload?.data?.price ?? null,
  };
}

async function verifyUnimatrixOtp(phone: string, code: string) {
  const url = await unimatrixUrl('otp.verify');
  const response = await fetch(url, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    body: JSON.stringify({
      to: phone,
      code,
      intent: unimatrixIntent,
      ttl: otpTtlSeconds,
    }),
  });
  const payload = await response.json().catch(() => ({}));
  return response.ok &&
    String(payload?.code ?? '') === '0' &&
    payload?.data?.valid === true;
}

async function verifyFirebaseIdToken(
  idToken: string,
  apiKey: string,
  expectedPhone: string,
) {
  const endpoint =
    'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=' +
    encodeURIComponent(apiKey);
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    body: JSON.stringify({idToken}),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) return false;
  const users = Array.isArray(payload?.users) ? payload.users : [];
  const account = users[0] ?? null;
  return account != null &&
    String(account.phoneNumber ?? '') === expectedPhone &&
    account.disabled !== true;
}

async function requireUser(req: Request) {
  const client = userClient(req);
  const authorization = req.headers.get('authorization') ?? '';
  const token = authorization.replace(/^Bearer\s+/i, '');
  const {data, error} = await client.auth.getUser(token);
  if (error || !data.user) throw new Error('Sesión inválida');
  return data.user;
}

async function enforceRateLimits(
  admin: ReturnType<typeof adminClient>,
  userId: string,
  phone: string,
) {
  const cooldownSince =
    new Date(Date.now() - resendCooldownSeconds * 1000).toISOString();
  const {count: recentCount, error: recentError} = await admin
    .from('phone_otp_challenges')
    .select('id', {count: 'exact', head: true})
    .eq('user_id', userId)
    .eq('phone', phone)
    .gte('created_at', cooldownSince);
  if (recentError) throw recentError;
  if ((recentCount ?? 0) > 0) {
    const error = new Error('Espera 60 segundos antes de reenviar el código');
    (error as any).status = 429;
    (error as any).code = 'resend_cooldown';
    throw error;
  }

  const daySince = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const [{count: userCount, error: userError}, {count: phoneCount, error: phoneError}] =
    await Promise.all([
      admin
        .from('phone_otp_challenges')
        .select('id', {count: 'exact', head: true})
        .eq('user_id', userId)
        .gte('created_at', daySince),
      admin
        .from('phone_otp_challenges')
        .select('id', {count: 'exact', head: true})
        .eq('phone', phone)
        .gte('created_at', daySince),
    ]);
  if (userError) throw userError;
  if (phoneError) throw phoneError;

  if ((userCount ?? 0) >= maxDailyRequestsPerUser ||
      (phoneCount ?? 0) >= maxDailyRequestsPerPhone) {
    const error = new Error('Límite diario de códigos alcanzado');
    (error as any).status = 429;
    (error as any).code = 'daily_rate_limit';
    throw error;
  }
}

async function createChallenge(
  admin: ReturnType<typeof adminClient>,
  params: {
    id?: string;
    userId: string;
    channel: string;
    country: string;
    phone: string;
    provider: string;
    providerKey?: string | null;
    codeHash?: string | null;
    status?: string;
    expiresInSeconds: number;
    providerMessageId?: string | null;
    providerMeta?: Record<string, unknown>;
  },
) {
  const id = params.id ?? crypto.randomUUID();
  const now = Date.now();
  const row = {
    id,
    user_id: params.userId,
    channel: params.channel,
    country_code: params.country,
    phone: params.phone,
    provider: params.provider,
    provider_key: params.providerKey ?? null,
    provider_message_id: params.providerMessageId ?? null,
    code_hash: params.codeHash ?? null,
    status: params.status ?? 'reserved',
    expires_at: new Date(now + params.expiresInSeconds * 1000).toISOString(),
    sent_at: params.status === 'sent' ? new Date(now).toISOString() : null,
    provider_meta: params.providerMeta ?? {},
    updated_at: new Date(now).toISOString(),
  };
  const {error} = await admin.from('phone_otp_challenges').insert(row);
  if (error) throw error;
  return id;
}

async function finalizeVerifiedPhone(
  admin: ReturnType<typeof adminClient>,
  challenge: any,
) {
  const verifiedAt = new Date().toISOString();
  const {error: userError} = await admin
    .from('users')
    .update({
      phone: challenge.phone,
      phone_country_code: challenge.country_code,
      phone_verified_at: verifiedAt,
      updated_at: verifiedAt,
    })
    .eq('id', challenge.user_id);
  if (userError) throw userError;

  const {error: challengeError} = await admin
    .from('phone_otp_challenges')
    .update({
      status: 'verified',
      verified_at: verifiedAt,
      updated_at: verifiedAt,
      error_code: null,
    })
    .eq('id', challenge.id)
    .eq('user_id', challenge.user_id);
  if (challengeError) throw challengeError;

  if (challenge.channel === 'production') {
    const {error: settingsError} = await admin
      .from('app_settings')
      .update({
        sms_provider_verified_at: verifiedAt,
        updated_at: verifiedAt,
      })
      .eq('id', true);
    if (settingsError) throw settingsError;
  }

  return verifiedAt;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {headers: corsHeaders});
  }
  if (req.method !== 'POST') {
    return json({ok: false, code: 'method_not_allowed'}, 405);
  }

  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const action = String(body?.action ?? '').trim().toLowerCase();
    const admin = adminClient();

    if (action === 'send') {
      const channel = normalizeChannel(body?.channel);
      const country = normalizeCountry(body?.countryCode);
      const phone = normalizePhone(body?.phone);
      assertPhoneCountry(phone, country);
      await enforceRateLimits(admin, user.id, phone);

      const firebase = await resolveFirebaseConfig(channel);
      const firebaseProviderKey = 'firebase:' + firebase.projectId;
      const {data: reservation, error: reserveError} = await admin.rpc(
        'reserve_phone_otp_daily_slot',
        {
          p_provider_key: firebaseProviderKey,
          p_limit: firebaseDailyFreeLimit,
        },
      );
      if (reserveError) throw reserveError;

      if (reservation?.reserved === true) {
        const challengeId = await createChallenge(admin, {
          userId: user.id,
          channel,
          country,
          phone,
          provider: 'firebase',
          providerKey: firebaseProviderKey,
          status: 'reserved',
          expiresInSeconds: firebaseChallengeTtlSeconds,
          providerMeta: {
            firebase_project_id: firebase.projectId,
            quota_used: reservation?.used ?? null,
            quota_limit: firebaseDailyFreeLimit,
          },
        });
        return json({
          ok: true,
          provider: 'firebase',
          challengeId,
          phone,
          expiresInSeconds: firebaseChallengeTtlSeconds,
          resendAfterSeconds: resendCooldownSeconds,
          firebaseDailyUsed: reservation?.used ?? null,
          firebaseDailyLimit: firebaseDailyFreeLimit,
        });
      }

      if (country === 'CL') {
        const configured =
          Boolean(Deno.env.get('LETEL_API_KEY')) &&
          Boolean(Deno.env.get('PHONE_OTP_PEPPER'));
        if (!configured) {
          return json({
            ok: false,
            code: 'provider_credentials_missing',
            provider: 'letel',
            message:
              'Se agotó el cupo diario de Firebase y LETEL todavía no tiene credenciales configuradas.',
            firebaseDailyUsed: reservation?.used ?? firebaseDailyFreeLimit,
            firebaseDailyLimit: firebaseDailyFreeLimit,
          }, 503);
        }

        const challengeId = crypto.randomUUID();
        const code = randomDigits(6);
        const codeHash = await challengeCodeHash(challengeId, phone, code);
        await createChallenge(admin, {
          id: challengeId,
          userId: user.id,
          channel,
          country,
          phone,
          provider: 'letel',
          providerKey: 'letel:cl',
          codeHash,
          status: 'reserved',
          expiresInSeconds: otpTtlSeconds,
        });

        try {
          const result = await sendLetel(phone, code);
          await admin.from('phone_otp_challenges').update({
            status: 'sent',
            sent_at: new Date().toISOString(),
            provider_message_id: result.messageId || null,
            provider_meta: {status: result.rawStatus},
            updated_at: new Date().toISOString(),
          }).eq('id', challengeId);
          return json({
            ok: true,
            provider: 'letel',
            challengeId,
            phone,
            expiresInSeconds: otpTtlSeconds,
            resendAfterSeconds: resendCooldownSeconds,
          });
        } catch (error) {
          await admin.from('phone_otp_challenges').update({
            status: 'failed',
            error_code: 'send_failed',
            updated_at: new Date().toISOString(),
          }).eq('id', challengeId);
          throw error;
        }
      }

      const unimatrixConfigured = Boolean(Deno.env.get('UNIMTX_ACCESS_KEY_ID'));
      if (!unimatrixConfigured) {
        return json({
          ok: false,
          code: 'provider_credentials_missing',
          provider: 'unimatrix',
          message:
            'Se agotó el cupo diario de Firebase y Unimatrix todavía no tiene credenciales configuradas.',
          firebaseDailyUsed: reservation?.used ?? firebaseDailyFreeLimit,
          firebaseDailyLimit: firebaseDailyFreeLimit,
        }, 503);
      }

      const challengeId = await createChallenge(admin, {
        userId: user.id,
        channel,
        country,
        phone,
        provider: 'unimatrix',
        providerKey: 'unimatrix:bo',
        status: 'reserved',
        expiresInSeconds: otpTtlSeconds,
      });

      try {
        const result = await sendUnimatrixOtp(phone);
        await admin.from('phone_otp_challenges').update({
          status: 'sent',
          sent_at: new Date().toISOString(),
          provider_message_id: result.messageId || null,
          provider_meta: {price: result.price},
          updated_at: new Date().toISOString(),
        }).eq('id', challengeId);
        return json({
          ok: true,
          provider: 'unimatrix',
          challengeId,
          phone,
          expiresInSeconds: otpTtlSeconds,
          resendAfterSeconds: resendCooldownSeconds,
        });
      } catch (error) {
        await admin.from('phone_otp_challenges').update({
          status: 'failed',
          error_code: 'send_failed',
          updated_at: new Date().toISOString(),
        }).eq('id', challengeId);
        throw error;
      }
    }

    if (action === 'verify') {
      const challengeId = String(body?.challengeId ?? '').trim();
      if (!/^[0-9a-f-]{36}$/i.test(challengeId)) {
        return json({ok: false, code: 'invalid_challenge'}, 400);
      }

      const {data: challenge, error: challengeError} = await admin
        .from('phone_otp_challenges')
        .select('*')
        .eq('id', challengeId)
        .eq('user_id', user.id)
        .maybeSingle();
      if (challengeError) throw challengeError;
      if (!challenge) return json({ok: false, code: 'challenge_not_found'}, 404);
      if (challenge.status === 'verified') {
        return json({
          ok: true,
          alreadyVerified: true,
          provider: challenge.provider,
          phone: challenge.phone,
        });
      }
      if (challenge.status === 'failed' || challenge.status === 'expired') {
        return json({ok: false, code: 'challenge_closed'}, 410);
      }
      if (new Date(challenge.expires_at).getTime() < Date.now()) {
        await admin.from('phone_otp_challenges').update({
          status: 'expired',
          updated_at: new Date().toISOString(),
        }).eq('id', challenge.id);
        return json({ok: false, code: 'code_expired'}, 410);
      }
      if ((challenge.attempts ?? 0) >= (challenge.max_attempts ?? 5)) {
        return json({ok: false, code: 'too_many_attempts'}, 429);
      }

      const nextAttempts = Number(challenge.attempts ?? 0) + 1;
      await admin.from('phone_otp_challenges').update({
        attempts: nextAttempts,
        updated_at: new Date().toISOString(),
      }).eq('id', challenge.id);

      let valid = false;
      if (challenge.provider === 'firebase') {
        const idToken = String(body?.firebaseIdToken ?? '').trim();
        if (!idToken) return json({ok: false, code: 'firebase_token_required'}, 400);
        const firebase = await resolveFirebaseConfig(challenge.channel);
        if (challenge.provider_key !== 'firebase:' + firebase.projectId) {
          return json({ok: false, code: 'firebase_project_mismatch'}, 400);
        }
        valid = await verifyFirebaseIdToken(
          idToken,
          firebase.apiKey,
          challenge.phone,
        );
      } else {
        const code = String(body?.code ?? '').replace(/\D/g, '');
        if (code.length < 4 || code.length > 8) {
          return json({ok: false, code: 'invalid_code_format'}, 400);
        }

        if (challenge.provider === 'letel') {
          const expected = String(challenge.code_hash ?? '');
          const actual = await challengeCodeHash(
            challenge.id,
            challenge.phone,
            code,
          );
          valid = expected.length > 0 && constantTimeEqual(expected, actual);
        } else if (challenge.provider === 'unimatrix') {
          valid = await verifyUnimatrixOtp(challenge.phone, code);
        }
      }

      if (!valid) {
        if (nextAttempts >= (challenge.max_attempts ?? 5)) {
          await admin.from('phone_otp_challenges').update({
            status: 'failed',
            error_code: 'too_many_attempts',
            updated_at: new Date().toISOString(),
          }).eq('id', challenge.id);
        }
        return json({ok: false, code: 'invalid_code'}, 400);
      }

      const verifiedAt = await finalizeVerifiedPhone(admin, challenge);
      return json({
        ok: true,
        provider: challenge.provider,
        phone: challenge.phone,
        countryCode: challenge.country_code,
        verifiedAt,
      });
    }

    return json({ok: false, code: 'unsupported_action'}, 400);
  } catch (error) {
    console.error('phone-otp error', error);
    const status = Number((error as any)?.status ?? 500);
    const code = String((error as any)?.code ?? 'phone_otp_error');
    const rawMessage = error instanceof Error ? error.message : String(error);
    const safeMessage =
      status >= 500
        ? 'No pudimos procesar la verificación telefónica.'
        : rawMessage;
    return json({ok: false, code, message: safeMessage}, status);
  }
});
