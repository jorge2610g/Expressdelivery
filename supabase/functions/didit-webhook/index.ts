import { createClient } from 'npm:@supabase/supabase-js@2';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {'Content-Type':'application/json'},
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
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    serviceKey(),
    {auth:{persistSession:false,autoRefreshToken:false}},
  );
}

function normalizeProviderStatus(value: unknown) {
  const raw = String(value ?? '').trim();
  const lower = raw.toLowerCase();
  if (lower === 'approved' || lower === 'verified') return {status:'verified', final:true};
  if (lower === 'declined') return {status:'rejected', final:true};
  if (lower === 'in review' || lower === 'review') return {status:'review', final:false};
  // An expired or abandoned attempt is not a rejected identity.
  if (lower === 'not finished' || lower === 'resubmitted' || lower === 'started' ||
      lower === 'in progress' || lower === 'not started' ||
      lower === 'expired' || lower === 'abandoned' || lower === 'kyc expired') {
    return {status:'processing', final:false};
  }
  return {status:'processing', final:false};
}

function findNumber(value: any, keys: string[]): number | null {
  if (value == null) return null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findNumber(item, keys);
      if (found != null) return found;
    }
    return null;
  }
  if (typeof value !== 'object') return null;
  for (const key of keys) {
    if (value[key] != null && Number.isFinite(Number(value[key]))) {
      return Number(value[key]);
    }
  }
  for (const child of Object.values(value)) {
    const found = findNumber(child, keys);
    if (found != null) return found;
  }
  return null;
}

function findString(value: any, keys: string[]): string | null {
  if (value == null) return null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findString(item, keys);
      if (found) return found;
    }
    return null;
  }
  if (typeof value !== 'object') return null;
  for (const key of keys) {
    if (value[key] != null) {
      const s=String(value[key]).trim();
      if (s) return s;
    }
  }
  for (const child of Object.values(value)) {
    const found = findString(child, keys);
    if (found) return found;
  }
  return null;
}

function canonicalize(value:any): string {
  if (Array.isArray(value)) return '['+value.map(canonicalize).join(',')+']';
  if (value && typeof value === 'object') {
    return '{'+Object.keys(value).sort().map(
      k=>JSON.stringify(k)+':'+canonicalize(value[k])
    ).join(',')+'}';
  }
  return JSON.stringify(value);
}

async function hmacHex(secret:string, data:string) {
  const enc=new TextEncoder();
  const key=await crypto.subtle.importKey(
    'raw',enc.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']
  );
  const sig=await crypto.subtle.sign('HMAC',key,enc.encode(data));
  return [...new Uint8Array(sig)].map(b=>b.toString(16).padStart(2,'0')).join('');
}

function safeEqual(a:string,b:string) {
  if (a.length !== b.length) return false;
  let diff=0;
  for (let i=0;i<a.length;i++) diff |= a.charCodeAt(i)^b.charCodeAt(i);
  return diff===0;
}

function safeResult(payload:any,previous:any={}) {
  const raw=payload?.id_verification ?? payload?.id_verifications ?? {};
  const idv=Array.isArray(raw) ? (raw[0] ?? {}) : raw;
  const fm=payload?.face_match ?? {};
  const lv=payload?.liveness ?? {};
  const last=previous?.identity ?? {};
  const read=(keys:string[],old:any)=>findString(idv,keys) ?? old ?? null;
  return {
    status:findString(payload,['status']),
    webhook_type:payload?.webhook_type ?? null,
    document_type:read(['document_type'],previous?.document_type),
    identity:{
      document_number:read(['document_number','personal_number'],last.document_number),
      full_name:read(['full_name','name'],null) ||
        [findString(idv,['first_name','given_name']),
         findString(idv,['last_name','surname','family_name'])]
         .filter(Boolean).join(' ') || last.full_name || null,
      date_of_birth:read(['date_of_birth','birth_date'],last.date_of_birth),
      date_of_issue:read(['date_of_issue','issue_date'],last.date_of_issue),
      expiration_date:read(['expiration_date','expiry_date'],last.expiration_date),
      nationality:read(['nationality'],last.nationality),
      gender:read(['gender','sex'],last.gender),
    },
    modules:{
      id_verification:findString(idv,['status']),
      face_match:findString(fm,['status']),
      liveness:findString(lv,['status']),
    },
    warnings:Array.isArray(idv?.warnings)
      ? idv.warnings.map((w:any)=>({
          risk:w?.risk ?? null,
          log_type:w?.log_type ?? null,
          short_description:w?.short_description ?? null,
        })).slice(0,20) : [],
  };
}

Deno.serve(async (req:Request)=>{
  if (req.method!=='POST') return json({error:'Método no permitido'},405);
  try {
    const secret=Deno.env.get('DIDIT_SANDBOX_WEBHOOK_SECRET') ?? '';
    if (!secret) return json({error:'Webhook Didit Sandbox no configurado'},503);

    const raw=await req.text();
    let payload:any;
    try { payload=JSON.parse(raw); } catch { return json({error:'JSON inválido'},400); }

    const receivedV2=(req.headers.get('x-signature-v2') ?? '').trim().toLowerCase();
    const receivedRaw=(req.headers.get('x-signature') ?? '').trim().toLowerCase();
    if (!receivedV2 && !receivedRaw) {
      return json({error:'Firma Didit ausente'},401);
    }

    const bodyTimestamp=Number(payload?.timestamp);
    const headerTimestamp=Number(req.headers.get('x-timestamp') ?? '');
    const nowSeconds=Math.floor(Date.now()/1000);
    if (
      !Number.isFinite(bodyTimestamp) ||
      !Number.isFinite(headerTimestamp) ||
      bodyTimestamp !== headerTimestamp ||
      Math.abs(nowSeconds-bodyTimestamp) > 300
    ) {
      return json({error:'Timestamp Didit inválido o vencido'},401);
    }

    // V3 recommends X-Signature-V2 over canonical JSON. Didit also sends the
    // legacy X-Signature over the exact raw bytes, which is a safe HMAC fallback
    // when a numeric JSON representation cannot be reproduced byte-for-byte.
    const canonicalExpected=(await hmacHex(secret,canonicalize(payload))).toLowerCase();
    const rawExpected=(await hmacHex(secret,raw)).toLowerCase();
    const validV2=receivedV2.length===canonicalExpected.length &&
      safeEqual(receivedV2,canonicalExpected);
    const validRaw=receivedRaw.length===rawExpected.length &&
      safeEqual(receivedRaw,rawExpected);
    if (!validV2 && !validRaw) {
      return json({error:'Firma Didit inválida'},401);
    }

    const sessionId=String(
      payload?.session_id ?? payload?.session?.id ?? payload?.id ?? ''
    ).trim();
    if (!sessionId) return json({error:'session_id ausente'},400);

    const providerStatus=
      findString(payload,['status']) ??
      findString(payload?.decision,['status']) ??
      'Unknown';
    const mapped=normalizeProviderStatus(providerStatus);

    const admin=adminClient();
    const {data:existing,error:findError}=await admin
      .from('identity_verifications')
      .select('*')
      .eq('provider','didit')
      .eq('provider_session_id',sessionId)
      .maybeSingle();
    if (findError) throw findError;

    const row=existing;
    // Every Express session is created server-side before the SDK starts.
    // Never trust webhook vendor_data to create a verification for an unknown user.
    if (!row) return json({error:'Sesión Didit desconocida'},404);

    const update:any={
      status:mapped.status,
      provider_status:providerStatus,
      document_score:findNumber(payload,['document_score','authenticity_score','confidence_score']),
      face_match_score:findNumber(payload,['face_match_score','similarity_score','face_similarity','similarity']),
      liveness_score:findNumber(payload,['liveness_score','liveness_probability','probability']),
      result:safeResult(payload,row.result),
      updated_at:new Date().toISOString(),
    };
    if (mapped.final) update.completed_at=new Date().toISOString();

    const {data:updated,error:updateError}=await admin
      .from('identity_verifications')
      .update(update)
      .eq('id',row.id)
      .select('id,user_id,status,provider_status,updated_at')
      .single();
    if (updateError) throw updateError;

    return json({ok:true,verification:updated});
  } catch (error) {
    console.error('didit-webhook',error);
    return json({ok:false,error:error instanceof Error?error.message:String(error)},500);
  }
});
