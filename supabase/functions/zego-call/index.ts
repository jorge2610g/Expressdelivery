import {createClient} from 'npm:@supabase/supabase-js@2.95.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const activeTripStatuses = new Set([
  'driver_assigned',
  'driver_arriving',
  'driver_waiting',
  'in_progress',
]);

const tokenTtlSeconds = 6 * 60 * 60;
const callInviteTimeoutSeconds = 30;
const maxCallSeconds = 5 * 60;

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

async function requireUser(req: Request) {
  const client = userClient(req);
  const authorization = req.headers.get('authorization') ?? '';
  const token = authorization.replace(/^Bearer\s+/i, '');
  const {data, error} = await client.auth.getUser(token);
  if (error || !data.user) throw new Error('Sesión inválida');
  return data.user;
}

function normalizeChannel(value: unknown) {
  return String(value ?? '').trim().toLowerCase() === 'preview'
    ? 'preview'
    : 'production';
}

function zegoUserId(userId: string) {
  // ZEGOCLOUD/ZIM limits userID length. A UUID without hyphens is exactly
  // 32 characters and remains deterministic/unique without exposing phone data.
  return userId.replace(/-/g, '');
}

function callId() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return 'c_' +
    Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
}

function configured() {
  const appId = Number(Deno.env.get('ZEGO_APP_ID') ?? '');
  const serverSecret = Deno.env.get('ZEGO_SERVER_SECRET') ?? '';
  return Number.isInteger(appId) && appId > 0 && serverSecret.length === 32;
}

function publicConfig() {
  return {
    configured: configured(),
    appID: configured() ? Number(Deno.env.get('ZEGO_APP_ID')) : null,
    resourceID: (Deno.env.get('ZEGO_RESOURCE_ID') ?? '').trim() || null,
    inviteTimeoutSeconds: callInviteTimeoutSeconds,
    maxCallSeconds,
  };
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = '';
  for (const value of bytes) binary += String.fromCharCode(value);
  return btoa(binary);
}

function asciiRandom(length: number) {
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
  const random = new Uint8Array(length);
  crypto.getRandomValues(random);
  return Array.from(random, (value) => alphabet[value % alphabet.length]).join('');
}

async function generateToken04(
  appId: number,
  userId: string,
  secret: string,
  effectiveTimeInSeconds: number,
) {
  if (!Number.isInteger(appId) || appId <= 0) throw new Error('ZEGO_APP_ID inválido');
  if (!userId) throw new Error('ZEGO userID inválido');
  if (secret.length !== 32) throw new Error('ZEGO_SERVER_SECRET debe tener 32 caracteres');

  const createTime = Math.floor(Date.now() / 1000);
  const expire = createTime + effectiveTimeInSeconds;
  const nonceArray = new Int32Array(1);
  crypto.getRandomValues(nonceArray);
  const tokenInfo = {
    app_id: appId,
    user_id: userId,
    nonce: nonceArray[0],
    ctime: createTime,
    expire,
    payload: '',
  };

  const ivText = asciiRandom(16);
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    {name: 'AES-CBC'},
    false,
    ['encrypt'],
  );
  const encrypted = new Uint8Array(
    await crypto.subtle.encrypt(
      {name: 'AES-CBC', iv: encoder.encode(ivText)},
      key,
      encoder.encode(JSON.stringify(tokenInfo)),
    ),
  );
  const ivBytes = encoder.encode(ivText);

  const packed = new Uint8Array(
    8 + 2 + ivBytes.length + 2 + encrypted.length,
  );
  const view = new DataView(packed.buffer);
  view.setBigInt64(0, BigInt(expire), false);
  view.setUint16(8, ivBytes.length, false);
  packed.set(ivBytes, 10);
  const encryptedLengthOffset = 10 + ivBytes.length;
  view.setUint16(encryptedLengthOffset, encrypted.length, false);
  packed.set(encrypted, encryptedLengthOffset + 2);

  return '04' + bytesToBase64(packed);
}

async function userSummary(
  admin: ReturnType<typeof adminClient>,
  userId: string,
) {
  const {data, error} = await admin
    .from('users')
    .select('id,full_name,account_status')
    .eq('id', userId)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error('Usuario no encontrado');
  return data;
}

async function issueToken(userId: string) {
  if (!configured()) return null;
  const appId = Number(Deno.env.get('ZEGO_APP_ID'));
  const secret = Deno.env.get('ZEGO_SERVER_SECRET')!;
  return await generateToken04(
    appId,
    zegoUserId(userId),
    secret,
    tokenTtlSeconds,
  );
}

function safeDisplayName(fullName: unknown) {
  const name = String(fullName ?? '').trim();
  if (!name) return 'Usuario Express';
  const first = name.split(/\s+/)[0].replace(/[^\p{L}\p{N}_-]/gu, '');
  return first || 'Usuario Express';
}

async function resolveActiveTrip(
  admin: ReturnType<typeof adminClient>,
  tripId: string,
  userId: string,
  channel: string,
) {
  const {data: trip, error} = await admin
    .from('trips')
    .select('id,passenger_id,driver_id,status,channel')
    .eq('id', tripId)
    .maybeSingle();
  if (error) throw error;
  if (!trip) {
    const e = new Error('Viaje no encontrado');
    (e as any).status = 404;
    (e as any).code = 'trip_not_found';
    throw e;
  }
  if (trip.channel !== channel) {
    const e = new Error('El viaje pertenece a otro entorno');
    (e as any).status = 409;
    (e as any).code = 'channel_mismatch';
    throw e;
  }
  if (!activeTripStatuses.has(String(trip.status))) {
    const e = new Error('Las llamadas solo están disponibles durante un viaje activo');
    (e as any).status = 409;
    (e as any).code = 'trip_not_active';
    throw e;
  }
  if (trip.passenger_id !== userId && trip.driver_id !== userId) {
    const e = new Error('No perteneces a este viaje');
    (e as any).status = 403;
    (e as any).code = 'not_trip_participant';
    throw e;
  }
  if (!trip.passenger_id || !trip.driver_id) {
    const e = new Error('El viaje todavía no tiene ambas partes asignadas');
    (e as any).status = 409;
    (e as any).code = 'trip_participants_incomplete';
    throw e;
  }
  return trip;
}

async function enforceCallCooldown(
  admin: ReturnType<typeof adminClient>,
  tripId: string,
  callerId: string,
) {
  const since = new Date(Date.now() - 30 * 1000).toISOString();
  const {count, error} = await admin
    .from('private_voice_calls')
    .select('id', {count: 'exact', head: true})
    .eq('trip_id', tripId)
    .eq('caller_id', callerId)
    .gte('initiated_at', since);
  if (error) throw error;
  if ((count ?? 0) > 0) {
    const e = new Error('Espera unos segundos antes de volver a llamar');
    (e as any).status = 429;
    (e as any).code = 'call_cooldown';
    throw e;
  }
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
    const channel = normalizeChannel(body?.channel);
    const admin = adminClient();
    const me = await userSummary(admin, user.id);

    if (action === 'bootstrap') {
      const cfg = publicConfig();
      if (!cfg.configured) {
        return json({
          ok: true,
          ...cfg,
        });
      }
      const token = await issueToken(user.id);
      return json({
        ok: true,
        ...cfg,
        userID: zegoUserId(user.id),
        userName: safeDisplayName(me.full_name),
        token,
        tokenExpiresInSeconds: tokenTtlSeconds,
      });
    }

    if (action === 'prepare') {
      if (!configured()) {
        return json({
          ok: false,
          code: 'zego_not_configured',
          message: 'ZEGOCLOUD todavía no tiene credenciales configuradas.',
          ...publicConfig(),
        }, 503);
      }
      const tripId = String(body?.tripId ?? '').trim();
      if (!/^[0-9a-f-]{36}$/i.test(tripId)) {
        return json({ok: false, code: 'invalid_trip_id'}, 400);
      }

      const trip = await resolveActiveTrip(admin, tripId, user.id, channel);
      const callerIsPassenger = trip.passenger_id === user.id;
      const peerId = callerIsPassenger ? trip.driver_id : trip.passenger_id;
      const callerRole = callerIsPassenger ? 'passenger' : 'driver';
      const [peer, freshMe] = await Promise.all([
        userSummary(admin, peerId),
        userSummary(admin, user.id),
      ]);

      await enforceCallCooldown(admin, trip.id, user.id);
      const zCallId = callId();
      const {data: callRow, error: callError} = await admin
        .from('private_voice_calls')
        .insert({
          trip_id: trip.id,
          channel,
          call_id: zCallId,
          caller_id: user.id,
          callee_id: peerId,
          caller_role: callerRole,
          provider: 'zegocloud',
          status: 'initiated',
          metadata: {
            privacy: 'phone_numbers_hidden',
            audio_recorded: false,
            max_call_seconds: maxCallSeconds,
          },
        })
        .select('id')
        .single();
      if (callError) throw callError;

      const token = await issueToken(user.id);
      return json({
        ok: true,
        ...publicConfig(),
        callLogID: callRow.id,
        callID: zCallId,
        userID: zegoUserId(user.id),
        userName: safeDisplayName(freshMe.full_name),
        peerUserID: zegoUserId(peerId),
        peerUserName: callerIsPassenger ? 'Conductor Express' : 'Pasajero Express',
        token,
        tokenExpiresInSeconds: tokenTtlSeconds,
        privacy: {
          phoneNumbersShared: false,
          audioRecorded: false,
        },
      });
    }

    if (action === 'event') {
      const callLogId = String(body?.callLogID ?? '').trim();
      const event = String(body?.event ?? '').trim().toLowerCase();
      if (!/^[0-9a-f-]{36}$/i.test(callLogId)) {
        return json({ok: false, code: 'invalid_call_log_id'}, 400);
      }
      const allowedEvents = new Set([
        'accepted',
        'declined',
        'missed',
        'cancelled',
        'ended',
        'failed',
      ]);
      if (!allowedEvents.has(event)) {
        return json({ok: false, code: 'invalid_call_event'}, 400);
      }

      const {data: row, error} = await admin
        .from('private_voice_calls')
        .select('*')
        .eq('id', callLogId)
        .maybeSingle();
      if (error) throw error;
      if (!row) return json({ok: false, code: 'call_not_found'}, 404);
      if (row.caller_id !== user.id && row.callee_id !== user.id) {
        return json({ok: false, code: 'not_call_participant'}, 403);
      }

      const now = new Date();
      const update: Record<string, unknown> = {
        status: event,
        updated_at: now.toISOString(),
      };
      if (event === 'accepted' && !row.answered_at) {
        update.answered_at = now.toISOString();
      }
      if (['declined', 'missed', 'cancelled', 'ended', 'failed'].includes(event)) {
        update.ended_at = now.toISOString();
        if (row.answered_at) {
          const answered = new Date(row.answered_at).getTime();
          update.duration_seconds = Math.max(
            0,
            Math.min(maxCallSeconds, Math.round((now.getTime() - answered) / 1000)),
          );
        }
      }
      const {error: updateError} = await admin
        .from('private_voice_calls')
        .update(update)
        .eq('id', callLogId);
      if (updateError) throw updateError;
      return json({ok: true});
    }

    return json({ok: false, code: 'unsupported_action'}, 400);
  } catch (error) {
    console.error('zego-call error', error);
    const status = Number((error as any)?.status ?? 500);
    const code = String((error as any)?.code ?? 'zego_call_error');
    const rawMessage = error instanceof Error ? error.message : String(error);
    return json({
      ok: false,
      code,
      message:
        status >= 500
          ? 'No pudimos preparar la llamada privada.'
          : rawMessage,
    }, status);
  }
});
