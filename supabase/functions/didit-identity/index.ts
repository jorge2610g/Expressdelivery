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
  if (lower === 'declined') return {status:'rejected', final:true};
  if (lower === 'in review' || lower === 'review') return {status:'review', final:false};
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

function safeResult(payload: any, previous: any = {}) {
  const idv = payload?.id_verification ?? payload?.id_verifications ?? {};
  const fm = payload?.face_match ?? {};
  const lv = payload?.liveness ?? {};
  const source = Array.isArray(idv) ? (idv[0] ?? {}) : idv;
  const last = previous?.identity ?? {};
  const read = (keys: string[], old: any) => findString(source, keys) ?? old ?? null;
  return {
    status: findString(payload, ['status']),
    document_type: read(['document_type'], previous?.document_type),
    identity: {
      document_number: read(['document_number','personal_number'], last.document_number),
      full_name: read(['full_name','name'], null) ||
        [findString(source, ['first_name','given_name']),
         findString(source, ['last_name','surname','family_name'])]
         .filter(Boolean).join(' ') || last.full_name || null,
      date_of_birth: read(['date_of_birth','birth_date'], last.date_of_birth),
      date_of_issue: read(['date_of_issue','issue_date'], last.date_of_issue),
      expiration_date: read(['expiration_date','expiry_date'], last.expiration_date),
      nationality: read(['nationality'], last.nationality),
      gender: read(['gender','sex'], last.gender),
    },
    warnings: Array.isArray(source?.warnings)
      ? source.warnings.map((w:any) => ({
          risk: w?.risk ?? null,
          log_type: w?.log_type ?? null,
          short_description: w?.short_description ?? null,
        })).slice(0,20) : [],
    modules: {
      id_verification: findString(source, ['status']),
      face_match: findString(fm, ['status']),
      liveness: findString(lv, ['status']),
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
    result: safeResult(payload, row.result),
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

    let country = String(profile?.country_code || '').trim().toUpperCase();
    const requestedZoneId = String(body.zone_id || profile?.zone_id || '').trim();

    if (requestedZoneId) {
      const {data:zone,error:zoneError} = await admin
        .from('service_zones')
        .select('id,country_code,active,driver_registration_enabled')
        .eq('id',requestedZoneId)
        .eq('active',true)
        .maybeSingle();
      if (zoneError) throw zoneError;
      if (!zone || zone.driver_registration_enabled === false) {
        return json({
          ok:false,
          code:'service_not_available',
          error:'Express todavía no está disponible para conductores en esta zona.'
        },409);
      }
      country = String(zone.country_code || '').trim().toUpperCase();
    }

    if (!/^[A-Z]{2}$/.test(country)) {
      return json({
        ok:false,
        code:'service_not_available',
        error:'Express todavía no está disponible para conductores en esta zona.'
      },409);
    }

    const {data:countryConfig,error:countryError} = await admin
      .from('service_countries')
      .select('country_code,active,driver_registration_enabled')
      .eq('country_code',country)
      .maybeSingle();
    if (countryError) throw countryError;
    if (!countryConfig?.active || countryConfig.driver_registration_enabled === false) {
      return json({
        ok:false,
        code:'service_not_available',
        error:'Express todavía no está disponible para conductores en esta zona.'
      },409);
    }

    const {data:verificationConfig,error:verificationError} = await admin
      .from('identity_verification_country_settings')
      .select('didit_enabled,sandbox_workflow_id')
      .eq('country_code',country)
      .maybeSingle();
    if (verificationError) throw verificationError;
    if (!verificationConfig?.didit_enabled) {
      return json({
        ok:false,
        code:'didit_disabled',
        error:'La verificación automática de identidad está desactivada para este país.'
      },409);
    }

    const workflow = String(
      verificationConfig?.sandbox_workflow_id ||
      Deno.env.get('DIDIT_SANDBOX_WORKFLOW_' + country) ||
      ''
    ).trim();

    if (!workflow) {
      return json({
        ok:false,
        code:'didit_sandbox_not_configured',
        error:'Falta configurar el Workflow ID de Didit Sandbox',
        country_code:country,
      },503);
    }

    if (action === 'create') {
      // A retry may reuse the SAME unfinished provider session. Never allow
      // app-side creation to bypass a real review or rejection.
      const {data:latest,error:latestError} = await admin
        .from('identity_verifications')
        .select('id,status')
        .eq('user_id',user.id)
        .eq('provider','didit')
        .eq('provider_environment','sandbox')
        .order('created_at',{ascending:false})
        .limit(1)
        .maybeSingle();
      if (latestError) throw latestError;
      if (latest && ['review','rejected','verified'].includes(latest.status)) {
        return json({
          ok:false,code:'verification_' + latest.status,status:latest.status,
          error:latest.status === 'review'
            ? 'Tu identidad está en revisión. Contacta a soporte.'
            : latest.status === 'rejected'
              ? 'Tu verificación fue rechazada. Contacta a soporte.'
              : 'Tu identidad ya está verificada.',
        },409);
      }
      // QA sandbox has its own independently reset 30-slot counter.
      let boliviaClaimId: string | null = null;
      if (country === 'BO') {
        const {data:quota,error:quotaError} = await admin.rpc(
          'driver_kyc_bolivia_reserve_didit',
          {p_user_id:user.id,p_channel:'preview'},
        );
        if (quotaError) throw quotaError;
        if (quota?.ok !== true) {
          return json({
            ok:false,code:'manual_kyc_required',
            error:'Cupo Didit de pruebas agotado. Usa la verificación manual.',
          },409);
        }
        boliviaClaimId=String(quota.claim_id);
      }
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
        if (boliviaClaimId != null) {
          const {error:releaseError}=await admin.rpc(
            'driver_kyc_bolivia_set_claim',
            {p_claim_id:boliviaClaimId,p_status:'released'},
          );
          if (releaseError) console.error('didit sandbox quota release',releaseError);
        }
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

      if (boliviaClaimId != null) {
        const {error:markError}=await admin.rpc(
          'driver_kyc_bolivia_set_claim',
          {p_claim_id:boliviaClaimId,p_status:'started',
           p_provider_session_id:sessionId},
        );
        if (markError) throw markError;
      }

      const {data:existing,error:existingError} = await admin
        .from('identity_verifications')
        .select('id,user_id,status,provider_environment')
        .eq('provider','didit')
        .eq('provider_session_id',sessionId)
        .maybeSingle();
      if (existingError) throw existingError;
      if (existing) {
        if (existing.user_id !== user.id ||
            existing.provider_environment !== 'sandbox') {
          return json({ok:false,code:'session_owner_conflict',
            error:'No se pudo asociar esta sesión. Contacta a soporte.'},409);
        }
        if (['review','rejected','verified'].includes(existing.status)) {
          return json({ok:false,code:'verification_' + existing.status,
            status:existing.status,
            error:'Consulta el estado de tu verificación antes de continuar.'},409);
        }
        return json({
          ok:true,reused:true,session_id:sessionId,
          session_token:sessionToken,url,status:existing.status,
          country_code:country,
        });
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
      if (createError) {
        if (createError.code === '23505') {
          const {data:race,error:raceError} = await admin
            .from('identity_verifications')
            .select('user_id,status,provider_environment')
            .eq('provider','didit')
            .eq('provider_session_id',sessionId)
            .maybeSingle();
          if (raceError) throw raceError;
          if (race?.user_id === user.id &&
              race.provider_environment === 'sandbox' &&
              ['pending','processing'].includes(race.status)) {
            return json({ok:true,reused:true,session_id:sessionId,
              session_token:sessionToken,url,status:race.status,
              country_code:country});
          }
          return json({ok:false,code:'session_owner_conflict',
            error:'No se pudo asociar esta sesión. Contacta a soporte.'},409);
        }
        throw createError;
      }

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
