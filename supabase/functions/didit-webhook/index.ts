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
  if (lower === 'declined' || lower === 'expired') return {status:'rejected', final:true};
  if (lower === 'in review' || lower === 'review') return {status:'review', final:false};
  if (lower === 'not finished' || lower === 'resubmitted' || lower === 'started') {
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

function safeResult(payload:any) {
  const idv=payload?.id_verification ?? {};
  const fm=payload?.face_match ?? {};
  const lv=payload?.liveness ?? {};
  return {
    status: findString(payload,['status']),
    webhook_type: payload?.webhook_type ?? null,
    document_type: idv?.document_type ?? null,
    issuing_state: idv?.issuing_state ?? null,
    modules:{
      id_verification:idv?.status ?? null,
      face_match:fm?.status ?? null,
      liveness:lv?.status ?? null,
    },
    warnings:Array.isArray(idv?.warnings)
      ? idv.warnings.map((w:any)=>({
          risk:w?.risk ?? null,
          log_type:w?.log_type ?? null,
          short_description:w?.short_description ?? null,
        })).slice(0,20)
      : [],
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

    const received=(req.headers.get('x-signature-v2') ?? '').trim().toLowerCase();
    if (!received) return json({error:'Firma Didit ausente'},401);

    const rawExpected=(await hmacHex(secret,raw)).toLowerCase();
    const canonicalExpected=(await hmacHex(secret,canonicalize(payload))).toLowerCase();
    if (!safeEqual(received,rawExpected) && !safeEqual(received,canonicalExpected)) {
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

    let row=existing;
    if (!row) {
      const vendorData=String(payload?.vendor_data ?? payload?.session?.vendor_data ?? '').trim();
      const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
      if (!uuid.test(vendorData)) return json({error:'Sesión Didit desconocida'},404);
      const {data:created,error:createError}=await admin
        .from('identity_verifications')
        .insert({
          user_id:vendorData,
          subject_role:'driver',
          document_type:'driver_identity',
          status:mapped.status,
          provider:'didit',
          provider_session_id:sessionId,
          provider_environment:'sandbox',
          provider_status:providerStatus,
          result:{source:'didit_sandbox_webhook'},
        })
        .select('*')
        .single();
      if (createError) throw createError;
      row=created;
    }

    const update:any={
      status:mapped.status,
      provider_status:providerStatus,
      document_score:findNumber(payload,['document_score','authenticity_score','confidence_score']),
      face_match_score:findNumber(payload,['face_match_score','similarity_score','face_similarity','similarity']),
      liveness_score:findNumber(payload,['liveness_score','liveness_probability','probability']),
      result:safeResult(payload),
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
