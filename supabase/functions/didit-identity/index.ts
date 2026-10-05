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
      const s = String(value[key]).trim();
      if (s) return s;
    }
  }
  for (const child of Object.values(value)) {
    const found = findString(child, keys);
    if (found) return found;
  }
  return null;
}

function safeResult(payload: any) {
  return {
    status: findString(payload, ['status']) ?? null,
    document_type: findString(payload, ['document_type']) ?? null,
    issuing_state: findString(payload, ['issuing_state']) ?? null,
    warnings: Array.isArray(payload?.warnings)
      ? payload.warnings.map((w:any) => ({
          risk: w?.risk ?? null,
          log_type: w?.log_type ?? null,
          short_description: w?.short_description ?? null,
        })).slice(0,20)
      : [],
    modules: {
      id_verification: findString(payload?.id_verification, ['status']),
      face_match: findString(payload?.face_match, ['status']),
      liveness: findString(payload?.liveness, ['status']),
    },
  };
}

async function applyDecision(admin: any, row: any, payload: any) {
  const providerStatus =
    findString(payload, ['status']) ??
    findString(payload?.decision, ['status']) ??
    row.provider_status ??
    'Unknown';
  const mapped = normalizeProviderStatus(providerStatus);
  const documentScore = findNumber(payload, [
    'document_score','authenticity_score','confidence_score'
  ]);
  const faceScore = findNumber(payload, [
    'face_match_score','similarity_score','face_similarity','similarity'
  ]);
  const livenessScore = findNumber(payload, [
    'liveness_score','liveness_probability','probability'
  ]);

  const update:any = {
    status: mapped.status,
    provider_status: providerStatus,
    document_score: documentScore,
    face_match_score: faceScore,
    liveness_score: livenessScore,
    result: safeResult(payload),
    updated_at: new Date().toISOString(),
  };
  if (mapped.final) update.completed_at = new Date().toISOString();

  const {data,error} = await admin
    .from('identity_verifications')
    .update(update)
    .eq('id', row.id)
    .select('*')
    .single();
  if (error) throw error;
  return data;
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
      const {data,error} = await admin
        .from('identity_verifications')
        .select('*')
        .eq('user_id',user.id)
        .eq('provider','didit')
        .order('created_at',{ascending:false})
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return json({ok:true, verification:data ?? null});
    }

    const apiKey = Deno.env.get('DIDIT_SANDBOX_API_KEY') ?? '';
    if (!apiKey) {
      return json({
        ok:false,
        code:'didit_sandbox_not_configured',
        error:'Falta configurar la API key de Didit Sandbox',
      },503);
    }

    // Refresh must not depend on an onboarding city that has not been saved yet.
    // The verified session itself already identifies the user's latest attempt.
    if (action === 'refresh') {
      const {data:row,error:rowError} = await admin
        .from('identity_verifications')
        .select('*')
        .eq('user_id',user.id)
        .eq('provider','didit')
        .eq('provider_environment','sandbox')
        .order('created_at',{ascending:false})
        .limit(1)
        .maybeSingle();
      if (rowError) throw rowError;
      if (!row?.provider_session_id) {
        return json({ok:true,verification:null});
      }

      const response = await fetch(
        'https://verification.didit.me/v3/session/' +
          encodeURIComponent(String(row.provider_session_id)) +
          '/decision/',
        {
          headers:{
            'x-api-key':apiKey,
            'Accept':'application/json',
          },
        },
      );
      const raw = await response.text();
      let payload:any = {};
      try { payload = raw ? JSON.parse(raw) : {}; } catch { payload = {raw}; }
      if (!response.ok) {
        return json({
          ok:false,
          error:payload?.detail || payload?.message || ('Didit HTTP '+response.status),
        },502);
      }

      const updated = await applyDecision(admin,row,payload);
      return json({ok:true,verification:updated});
    }

    const {data:profile,error:profileError} = await admin
      .from('driver_profiles')
      .select('id,country_code,zone_id,approval_status')
      .eq('id', user.id)
      .maybeSingle();
    if (profileError) throw profileError;

    let country = String(profile?.country_code || '').toUpperCase();
    const requestedZoneId = String(body.zone_id || profile?.zone_id || '').trim();
    if ((!country || !['CL','BO'].includes(country)) && requestedZoneId) {
      const {data:zone,error:zoneError} = await admin
        .from('service_zones')
        .select('id,country_code,active')
        .eq('id',requestedZoneId)
        .eq('active',true)
        .maybeSingle();
      if (zoneError) throw zoneError;
      country = String(zone?.country_code || '').toUpperCase();
    }

    if (!['CL','BO'].includes(country)) {
      return json({
        error:'Selecciona una ciudad activa de Chile o Bolivia antes de verificar tu identidad'
      },409);
    }

    const workflow = country === 'CL'
      ? (Deno.env.get('DIDIT_SANDBOX_WORKFLOW_CL') ?? '')
      : (Deno.env.get('DIDIT_SANDBOX_WORKFLOW_BO') ?? '');

    if (!workflow) {
      return json({
        ok:false,
        code:'didit_sandbox_not_configured',
        error:'Falta configurar el Workflow ID de Didit Sandbox',
        country_code:country,
      },503);
    }

    if (action === 'create') {
      // Native SDK sessions need a short-lived session_token. We intentionally
      // create a fresh attempt instead of reusing a hosted-URL-only pending row.
      const response = await fetch('https://verification.didit.me/v3/session/', {
        method:'POST',
        headers:{
          'x-api-key':apiKey,
          'Content-Type':'application/json',
          'Accept':'application/json',
        },
        body:JSON.stringify({
          workflow_id:workflow,
          vendor_data:user.id,
        }),
      });

      const raw = await response.text();
      let payload:any = {};
      try { payload = raw ? JSON.parse(raw) : {}; } catch { payload = {raw}; }
      if (!response.ok) {
        console.error('didit create session', response.status, raw.slice(0,500));
        return json({
          ok:false,
          error:payload?.detail || payload?.message || ('Didit HTTP '+response.status),
        },502);
      }

      const sessionId = String(payload?.session_id || payload?.id || '').trim();
      const sessionToken = String(payload?.session_token || '').trim();
      const url = String(payload?.url || payload?.verification_url || '').trim();
      if (!sessionId || !sessionToken || !url) {
        return json({
          ok:false,
          error:'Didit no devolvió session_id/session_token/url',
        },502);
      }

      const {data:created,error:createError} = await admin
        .from('identity_verifications')
        .insert({
          user_id:user.id,
          subject_role:'driver',
          document_type:'driver_identity',
          status:'pending',
          provider:'didit',
          provider_session_id:sessionId,
          provider_environment:'sandbox',
          country_code:country,
          workflow_id:workflow,
          verification_url:url,
          provider_status:'Created',
          result:{
            source:'didit_sandbox',
            zone_id:requestedZoneId || null,
          },
        })
        .select('*')
        .single();
      if (createError) throw createError;

      return json({
        ok:true,
        reused:false,
        session_id:sessionId,
        session_token:sessionToken,
        url,
        status:created.status,
        country_code:country,
      });
    }

    return json({error:'Acción no soportada'},400);
  } catch (error) {
    console.error('didit-identity', error);
    return json({
      ok:false,
      error:error instanceof Error ? error.message : String(error),
    },500);
  }
});
