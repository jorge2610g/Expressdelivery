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

function findModule(payload: any, keys: string[]): any {
  if (payload == null) return {};
  if (Array.isArray(payload)) {
    for (const item of payload) {
      const found = findModule(item, keys);
      if (found && Object.keys(found).length > 0) return found;
    }
    return {};
  }
  if (typeof payload !== 'object') return {};
  for (const key of keys) {
    const value = payload[key];
    if (Array.isArray(value) && value.length > 0 && typeof value[0] === 'object') {
      return value[0] ?? {};
    }
    if (value && typeof value === 'object') return value;
  }
  for (const child of Object.values(payload)) {
    const found = findModule(child, keys);
    if (found && Object.keys(found).length > 0) return found;
  }
  return {};
}

function safeResult(payload: any) {
  const idv = findModule(payload, ['id_verification','id_verifications']);
  const fm = findModule(payload, ['face_match','face_matches']);
  const lv = findModule(payload, ['liveness','liveness_checks']);
  return {
    status: findString(payload, ['status']) ?? null,
    document_type: findString(idv, ['document_type']) ?? null,
    issuing_state: findString(idv, ['issuing_state']) ?? null,
    identity: {
      document_number: findString(idv, ['document_number']) ?? null,
      personal_number: findString(idv, ['personal_number']) ?? null,
      first_name: findString(idv, ['first_name','given_name']) ?? null,
      last_name: findString(idv, ['last_name','surname','family_name']) ?? null,
      full_name: findString(idv, ['full_name','name']) ?? null,
      date_of_birth: findString(idv, ['date_of_birth','birth_date']) ?? null,
      expiration_date: findString(idv, ['expiration_date','expiry_date']) ?? null,
      date_of_issue: findString(idv, ['date_of_issue','issue_date']) ?? null,
      nationality: findString(idv, ['nationality']) ?? null,
    },
    warnings: Array.isArray(idv?.warnings)
      ? idv.warnings.map((w:any) => ({
          risk: w?.risk ?? null,
          log_type: w?.log_type ?? null,
          short_description: w?.short_description ?? null,
        })).slice(0,20)
      : [],
    modules: {
      id_verification: findString(idv, ['status']),
      face_match: findString(fm, ['status']),
      liveness: findString(lv, ['status']),
    },
  };
}

function cleanText(value: unknown): string | null {
  const s = String(value ?? '').trim();
  return s ? s : null;
}

async function persistVerifiedIdentity(admin: any, row: any, payload: any) {
  const idv = findModule(payload, ['id_verification','id_verifications']);
  const liveness = findModule(payload, ['liveness','liveness_checks']);
  const faceMatch = findModule(payload, ['face_match','face_matches']);

  const firstName = findString(idv, ['first_name','given_name']);
  const lastName = findString(idv, ['last_name','surname','family_name']);
  const fullName = cleanText(findString(idv, ['full_name','name'])) ??
    cleanText([firstName, lastName].filter(Boolean).join(' '));
  const documentNumber =
    findString(idv, ['document_number','personal_number']);

  let profilePhotoPath: string | null = null;
  const referenceImage =
    findString(liveness, [
      'selfie_image','selfie_url','reference_image','silent_selfie',
      'silent_selfie_image','liveness_image','frame_url','video_frame'
    ]) ??
    findString(faceMatch, ['source_image','selfie_image','reference_image']);

  if (referenceImage) {
    try {
      const imageResponse = await fetch(referenceImage);
      if (imageResponse.ok) {
        const bytes = new Uint8Array(await imageResponse.arrayBuffer());
        if (bytes.length > 0 && bytes.length <= 8 * 1024 * 1024) {
          const contentType =
            imageResponse.headers.get('content-type')?.split(';')[0]?.trim() ||
            'image/jpeg';
          const ext = contentType === 'image/png'
            ? 'png'
            : contentType === 'image/webp'
              ? 'webp'
              : 'jpg';
          profilePhotoPath =
            String(row.user_id) + '/profile/didit-' +
            String(row.provider_session_id || row.id) + '.' + ext;

          const {error:uploadError} = await admin.storage
            .from('driver-onboarding')
            .upload(profilePhotoPath, bytes, {
              upsert: true,
              contentType,
              cacheControl: '3600',
            });
          if (uploadError) {
            console.error('didit profile upload', uploadError);
            profilePhotoPath = null;
          }
        }
      }
    } catch (error) {
      console.error('didit profile image fetch', error);
    }
  }

  if (fullName) {
    const {error:userError} = await admin
      .from('users')
      .update({full_name:fullName,updated_at:new Date().toISOString()})
      .eq('id',row.user_id);
    if (userError) throw userError;
  }

  const profileUpdate:any = {
    id: row.user_id,
    country_code: row.country_code ?? null,
    updated_at: new Date().toISOString(),
  };
  if (profilePhotoPath) profileUpdate.profile_photo_path = profilePhotoPath;

  const {error:profileError} = await admin
    .from('driver_profiles')
    .upsert(profileUpdate,{onConflict:'id'});
  if (profileError) throw profileError;

  return profilePhotoPath;
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

  if (mapped.status === 'verified') {
    await persistVerifiedIdentity(admin, data, payload);
  }
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
        .eq('provider_environment','production')
        .order('created_at',{ascending:false})
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      const {data:profile} = await admin
        .from('driver_profiles')
        .select('profile_photo_path')
        .eq('id',user.id)
        .maybeSingle();
      return json({
        ok:true,
        verification:data ?? null,
        profile_photo_path:profile?.profile_photo_path ?? null,
      });
    }

    const apiKey = Deno.env.get('DIDIT_PROD_API_KEY') ?? '';
    if (!apiKey) {
      return json({
        ok:false,
        code:'didit_production_not_configured',
        error:'Falta configurar la API key de Didit Producción',
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
        .eq('provider_environment','production')
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
      const {data:profile} = await admin
        .from('driver_profiles')
        .select('profile_photo_path')
        .eq('id',user.id)
        .maybeSingle();
      return json({
        ok:true,
        verification:updated,
        profile_photo_path:profile?.profile_photo_path ?? null,
      });
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
      .select('didit_enabled,production_workflow_id')
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
      verificationConfig?.production_workflow_id ||
      Deno.env.get('DIDIT_PROD_WORKFLOW_' + country) ||
      ''
    ).trim();

    if (!workflow) {
      return json({
        ok:false,
        code:'didit_production_not_configured',
        error:'Falta configurar el Workflow ID de Didit Producción',
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
          provider_environment:'production',
          country_code:country,
          workflow_id:workflow,
          verification_url:url,
          provider_status:'Created',
          result:{
            source:'didit_production',
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
