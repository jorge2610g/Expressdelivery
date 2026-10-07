import { createClient } from 'npm:@supabase/supabase-js@2';
import { createRemoteJWKSet, jwtVerify } from 'npm:jose@5';

const allowedRepository = 'jorge2610g/Expressdelivery';
const expectedAudience = 'supabase-android-build-worker';
const issuer = 'https://token.actions.githubusercontent.com';
const jwks = createRemoteJWKSet(
  new URL('https://token.actions.githubusercontent.com/.well-known/jwks'),
);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {'Content-Type': 'application/json'},
  });
}

async function verifyGithub(req: Request) {
  const auth = req.headers.get('authorization') ?? '';
  if (!auth.startsWith('Bearer ')) throw new Error('Falta token OIDC');
  const token = auth.slice(7);
  const {payload} = await jwtVerify(token, jwks, {
    issuer,
    audience: expectedAudience,
  });

  if (payload.repository !== allowedRepository) {
    throw new Error('Repositorio no autorizado');
  }
  if (payload.ref !== 'refs/heads/main') {
    throw new Error('Rama no autorizada');
  }
  const workflowRef = payload.workflow_ref?.toString() ?? '';
  const allowedWorkflows = [
    '/.github/workflows/build-android.yml@refs/heads/main',
    '/.github/workflows/shorebird-preview-codepush.yml@refs/heads/main',
    '/.github/workflows/express-qa.yml@refs/heads/main',
  ];
  if (!allowedWorkflows.some((path) => workflowRef.includes(path))) {
    throw new Error('Workflow no autorizado');
  }
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

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

function bytesToBase64Url(bytes: Uint8Array) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function textToBase64Url(value: string) {
  return bytesToBase64Url(new TextEncoder().encode(value));
}

function pemPkcs8Bytes(pem: string) {
  const clean = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');
  const raw = atob(clean);
  return Uint8Array.from(raw, (char) => char.charCodeAt(0));
}

async function firebaseScopedAccessToken(
  account: FirebaseServiceAccount,
  scope: string,
) {
  const now = Math.floor(Date.now() / 1000);
  const tokenUri =
    account.token_uri || 'https://oauth2.googleapis.com/token';
  const header = textToBase64Url(
    JSON.stringify({alg: 'RS256', typ: 'JWT'}),
  );
  const payload = textToBase64Url(
    JSON.stringify({
      iss: account.client_email,
      scope,
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = header + '.' + payload;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemPkcs8Bytes(account.private_key),
    {name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256'},
    false,
    ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  const assertion = unsigned + '.' + bytesToBase64Url(signature);
  const response = await fetch(tokenUri, {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(
      'No se pudo autenticar Firebase Management: ' +
        (await response.text()),
    );
  }
  const body = await response.json();
  const token = body?.access_token?.toString() ?? '';
  if (!token) throw new Error('Firebase Management no devolvió access_token');
  return token;
}

async function firebaseAndroidConfig(
  packageName: string,
  displayName: string,
) {
  const allowedPackages = new Set([
    'com.express.usuario.preview',
    'com.express.usuario1',
  ]);
  if (!allowedPackages.has(packageName)) {
    throw new Error('Package Firebase no autorizado');
  }

  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') ?? '';
  if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON no configurado');
  const account = JSON.parse(raw) as FirebaseServiceAccount;
  if (!account.project_id || !account.client_email || !account.private_key) {
    throw new Error('Service account Firebase incompleta');
  }

  const accessToken = await firebaseScopedAccessToken(
    account,
    'https://www.googleapis.com/auth/cloud-platform',
  );
  const authHeaders = {
    Authorization: 'Bearer ' + accessToken,
    'Content-Type': 'application/json',
  };
  const project = encodeURIComponent(account.project_id);
  const listUrl =
    'https://firebase.googleapis.com/v1beta1/projects/' +
    project +
    '/androidApps';

  async function listApps() {
    const response = await fetch(listUrl, {headers: authHeaders});
    if (!response.ok) {
      throw new Error(
        'Firebase Android app list failed: ' +
          response.status +
          ' ' +
          (await response.text()),
      );
    }
    const body = await response.json();
    return Array.isArray(body?.apps) ? body.apps : [];
  }

  let apps = await listApps();
  let app = apps.find(
    (item: Record<string, unknown>) =>
      item?.packageName?.toString() === packageName,
  );
  let created = false;

  if (!app) {
    const createResponse = await fetch(listUrl, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({
        displayName,
        packageName,
      }),
    });
    if (!createResponse.ok) {
      throw new Error(
        'Firebase Android app create failed: ' +
          createResponse.status +
          ' ' +
          (await createResponse.text()),
      );
    }
    created = true;
    const operation = await createResponse.json();
    const operationName = operation?.name?.toString() ?? '';

    if (operationName) {
      const operationUrl =
        'https://firebase.googleapis.com/v1beta1/' + operationName;
      for (let attempt = 0; attempt < 20; attempt++) {
        await new Promise((resolve) => setTimeout(resolve, 1500));
        const opResponse = await fetch(operationUrl, {headers: authHeaders});
        if (!opResponse.ok) continue;
        const opBody = await opResponse.json();
        if (opBody?.done === true) {
          if (opBody?.error) {
            throw new Error(
              'Firebase Android app operation failed: ' +
                JSON.stringify(opBody.error),
            );
          }
          break;
        }
      }
    }

    for (let attempt = 0; attempt < 10 && !app; attempt++) {
      if (attempt > 0) {
        await new Promise((resolve) => setTimeout(resolve, 1500));
      }
      apps = await listApps();
      app = apps.find(
        (item: Record<string, unknown>) =>
          item?.packageName?.toString() === packageName,
      );
    }
  }

  if (!app?.appId) {
    throw new Error('Firebase Android app no disponible para ' + packageName);
  }

  const configResponse = await fetch(
    'https://firebase.googleapis.com/v1beta1/projects/-/androidApps/' +
      encodeURIComponent(app.appId.toString()) +
      '/config',
    {headers: authHeaders},
  );
  if (!configResponse.ok) {
    throw new Error(
      'Firebase Android config failed: ' +
        configResponse.status +
        ' ' +
        (await configResponse.text()),
    );
  }
  const configEnvelope = await configResponse.json();
  const encoded = configEnvelope?.configFileContents?.toString() ?? '';
  if (!encoded) throw new Error('Firebase Android config vacía');

  const googleServices = JSON.parse(atob(encoded));
  const projectInfo = googleServices?.project_info ?? {};
  const clients = Array.isArray(googleServices?.client)
    ? googleServices.client
    : [];
  const client = clients.find(
    (item: Record<string, any>) =>
      item?.client_info?.android_client_info?.package_name === packageName,
  );
  const apiKeys = Array.isArray(client?.api_key) ? client.api_key : [];
  const apiKey = apiKeys[0]?.current_key?.toString() ?? '';
  const appId = client?.client_info?.mobilesdk_app_id?.toString() ?? '';
  const messagingSenderId = projectInfo?.project_number?.toString() ?? '';
  const projectId = projectInfo?.project_id?.toString() ?? account.project_id;
  const storageBucket = projectInfo?.storage_bucket?.toString() ?? '';

  if (!apiKey || !appId || !messagingSenderId || !projectId) {
    throw new Error('Firebase Android config incompleta para ' + packageName);
  }

  return {
    found: true,
    created,
    package_name: packageName,
    api_key: apiKey,
    app_id: appId,
    messaging_sender_id: messagingSenderId,
    project_id: projectId,
    storage_bucket: storageBucket,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({error: 'Método no permitido'}, 405);

  try {
    await verifyGithub(req);
    const payload = await req.json().catch(() => ({}));
    const action = payload.action?.toString() ?? '';

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const admin = createClient(supabaseUrl, serviceKey(), {
      auth: {persistSession: false, autoRefreshToken: false},
    });

    if (action === 'preview_base_published') {
      const commitSha = payload.commit_sha?.toString().trim() ?? '';
      const versionName = payload.version_name?.toString().trim() ?? '';
      const buildNumber = Number(payload.build_number);
      const runId = payload.run_id?.toString().trim() ?? '';
      const apkUrl = payload.apk_url?.toString().trim() ?? '';

      if (
        !/^[0-9a-f]{40}$/i.test(commitSha) ||
        !versionName ||
        !Number.isInteger(buildNumber) ||
        buildNumber <= 0 ||
        !runId ||
        !apkUrl
      ) {
        return json({error: 'Identidad de base Preview inválida'}, 400);
      }

      const expectedTag =
        'preview-shorebird-v' + versionName + '-build' + buildNumber;
      const expectedApkUrl =
        'https://github.com/jorge2610g/Expressdelivery/releases/download/' +
        expectedTag +
        '/app-release.apk';
      if (apkUrl !== expectedApkUrl) {
        return json({
          error: 'APK Preview bloqueado: URL no corresponde a la identidad publicada.',
          expected_apk_url: expectedApkUrl,
          received_apk_url: apkUrl,
        }, 409);
      }

      const {data: currentGate, error: currentGateError} = await admin
        .from('app_release_gate')
        .select(
          'preview_build_id,preview_version_name,preview_build_number,preview_base_commit_sha,preview_commit_sha',
        )
        .eq('platform', 'android')
        .maybeSingle();
      if (currentGateError) throw currentGateError;

      if (
        currentGate?.preview_build_number &&
        Number(currentGate.preview_build_number) > buildNumber
      ) {
        return json({
          error: 'Base Preview obsoleta: el gate ya contiene un build más nuevo.',
          current: {
            version_name: currentGate.preview_version_name,
            build_number: currentGate.preview_build_number,
            commit_sha: currentGate.preview_commit_sha,
          },
          received: {
            version_name: versionName,
            build_number: buildNumber,
            commit_sha: commitSha,
          },
        }, 409);
      }

      if (
        currentGate?.preview_build_number &&
        Number(currentGate.preview_build_number) === buildNumber &&
        (
          currentGate.preview_version_name !== versionName ||
          (
            currentGate.preview_commit_sha &&
            currentGate.preview_commit_sha !== commitSha
          )
        )
      ) {
        return json({
          error:
            'Colisión de identidad Preview: el mismo build ya está asociado a otra versión/SHA. Incrementa el build.',
          current: {
            version_name: currentGate.preview_version_name,
            build_number: currentGate.preview_build_number,
            commit_sha: currentGate.preview_commit_sha,
          },
          received: {
            version_name: versionName,
            build_number: buildNumber,
            commit_sha: commitSha,
          },
        }, 409);
      }

      const {data: existingJobs, error: existingError} = await admin
        .from('build_jobs')
        .select('id,status,commit_sha,version_name,build_number,artifact_type,apk_url')
        .eq('platform', 'android')
        .eq('artifact_type', 'preview-apk')
        .eq('status', 'ready')
        .eq('version_name', versionName)
        .eq('build_number', buildNumber)
        .eq('commit_sha', commitSha)
        .order('created_at', {ascending: false})
        .limit(1);
      if (existingError) throw existingError;

      let buildId = existingJobs?.[0]?.id?.toString() ?? '';
      const now = new Date().toISOString();

      if (buildId) {
        const {error: updateExistingError} = await admin
          .from('build_jobs')
          .update({
            workflow_run_id: runId,
            artifact_url: apkUrl,
            apk_url: apkUrl,
            aab_url: null,
            run_url:
              'https://github.com/jorge2610g/Expressdelivery/actions/runs/' +
              runId,
            signing_mode: 'production',
            completed_at: now,
            updated_at: now,
            error_message: null,
          })
          .eq('id', buildId);
        if (updateExistingError) throw updateExistingError;
      } else {
        const {data: creatorRows, error: creatorError} = await admin
          .from('build_jobs')
          .select('created_by')
          .eq('platform', 'android')
          .in('artifact_type', ['preview-apk', 'preview-apk+aab'])
          .order('created_at', {ascending: false})
          .limit(1);
        if (creatorError) throw creatorError;

        const createdBy = creatorRows?.[0]?.created_by?.toString() ?? '';
        if (!createdBy) {
          return json({
            error:
              'No existe identidad creadora previa para registrar la base Preview.',
          }, 409);
        }

        const {data: inserted, error: insertError} = await admin
          .from('build_jobs')
          .insert({
            platform: 'android',
            artifact_type: 'preview-apk',
            version_name: versionName,
            build_number: buildNumber,
            status: 'ready',
            changelog:
              'Base Preview Shorebird publicada y registrada automáticamente.',
            commit_sha: commitSha,
            workflow_run_id: runId,
            artifact_url: apkUrl,
            created_by: createdBy,
            completed_at: now,
            apk_url: apkUrl,
            aab_url: null,
            run_url:
              'https://github.com/jorge2610g/Expressdelivery/actions/runs/' +
              runId,
            error_message: null,
            signing_mode: 'production',
            started_at: now,
            updated_at: now,
          })
          .select('id')
          .single();
        if (insertError) throw insertError;
        buildId = inserted.id.toString();
      }

      const {data: gate, error: gateError} = await admin
        .from('app_release_gate')
        .select(
          'preview_build_id,preview_version_name,preview_build_number,preview_base_commit_sha,preview_commit_sha',
        )
        .eq('platform', 'android')
        .maybeSingle();
      if (gateError) throw gateError;

      const exactGate =
        gate?.preview_build_id === buildId &&
        gate?.preview_version_name === versionName &&
        Number(gate?.preview_build_number) === buildNumber &&
        gate?.preview_base_commit_sha === commitSha &&
        gate?.preview_commit_sha === commitSha;

      if (!exactGate) {
        return json({
          error:
            'Base Preview publicada pero el release gate no quedó en la misma identidad.',
          expected: {
            preview_build_id: buildId,
            version_name: versionName,
            build_number: buildNumber,
            commit_sha: commitSha,
          },
          gate: gate ?? null,
        }, 409);
      }

      return json({
        ok: true,
        preview_build_id: buildId,
        version_name: versionName,
        build_number: buildNumber,
        preview_base_commit_sha: commitSha,
        preview_commit_sha: commitSha,
        apk_url: apkUrl,
      });
    }

    if (action === 'preview_patch_published') {
      const commitSha = payload.commit_sha?.toString().trim() ?? '';
      const versionName = payload.version_name?.toString().trim() ?? '';
      const buildNumber = Number(payload.build_number);
      const runId = payload.run_id?.toString().trim() ?? '';

      if (!/^[0-9a-f]{40}$/i.test(commitSha) || !versionName || !Number.isInteger(buildNumber)) {
        return json({error: 'Identidad de patch Preview inválida'}, 400);
      }

      const {data: gate, error: gateError} = await admin
        .from('app_release_gate')
        .select(
          'preview_build_id,preview_base_commit_sha,preview_commit_sha,preview_version_name,preview_build_number,approved_preview_build_id,approved_commit_sha,approved_by,approved_at,qa_preview_build_id,qa_commit_sha,qa_workflow_run_id,qa_passed_at,production_candidate_build_id,production_candidate_commit_sha,production_candidate_version_name,production_candidate_build_number,production_candidate_ready_at,production_candidate_promoted_at',
        )
        .eq('platform', 'android')
        .maybeSingle();
      if (gateError) throw gateError;

      if (
        !gate?.preview_build_id ||
        gate.preview_version_name !== versionName ||
        Number(gate.preview_build_number) !== buildNumber
      ) {
        return json({
          error:
            'Patch Preview bloqueado: versión/build no coincide con la base Preview vigente.',
          expected: gate
            ? {
                version_name: gate.preview_version_name,
                build_number: gate.preview_build_number,
              }
            : null,
          received: {version_name: versionName, build_number: buildNumber},
        }, 409);
      }

      const {data: baseJob, error: baseError} = await admin
        .from('build_jobs')
        .select('id,status,commit_sha,version_name,build_number,artifact_type')
        .eq('id', gate.preview_build_id)
        .maybeSingle();
      if (baseError) throw baseError;
      if (
        !baseJob ||
        baseJob.status !== 'ready' ||
        !['preview-apk', 'preview-apk+aab'].includes(baseJob.artifact_type)
      ) {
        return json({error: 'Patch Preview bloqueado: la base no está lista.'}, 409);
      }

      const sameCurrentSha = gate.preview_commit_sha === commitSha;
      const now = new Date().toISOString();
      const {error: updateError} = await admin
        .from('app_release_gate')
        .update({
          preview_base_commit_sha:
            gate.preview_base_commit_sha || baseJob.commit_sha,
          preview_commit_sha: commitSha,
          preview_ready_at: now,
          preview_patch_workflow_run_id: runId || null,
          preview_patch_at: now,
          approved_preview_build_id: sameCurrentSha
            ? gate.approved_preview_build_id
            : null,
          approved_commit_sha: sameCurrentSha
            ? gate.approved_commit_sha
            : null,
          approved_by: sameCurrentSha ? gate.approved_by : null,
          approved_at: sameCurrentSha ? gate.approved_at : null,
          qa_preview_build_id: sameCurrentSha ? gate.qa_preview_build_id : null,
          qa_commit_sha: sameCurrentSha ? gate.qa_commit_sha : null,
          qa_workflow_run_id: sameCurrentSha ? gate.qa_workflow_run_id : null,
          qa_passed_at: sameCurrentSha ? gate.qa_passed_at : null,
          production_candidate_build_id: sameCurrentSha ? gate.production_candidate_build_id : null,
          production_candidate_commit_sha: sameCurrentSha ? gate.production_candidate_commit_sha : null,
          production_candidate_version_name: sameCurrentSha ? gate.production_candidate_version_name : null,
          production_candidate_build_number: sameCurrentSha ? gate.production_candidate_build_number : null,
          production_candidate_ready_at: sameCurrentSha ? gate.production_candidate_ready_at : null,
          production_candidate_promoted_at: sameCurrentSha ? gate.production_candidate_promoted_at : null,
          updated_at: now,
        })
        .eq('platform', 'android');
      if (updateError) throw updateError;

      return json({
        ok: true,
        version_name: versionName,
        build_number: buildNumber,
        preview_commit_sha: commitSha,
        base_commit_sha: gate.preview_base_commit_sha || baseJob.commit_sha,
        approval_cleared: !sameCurrentSha,
      });
    }

    if (action === 'queue_production_candidate') {
      const commitSha = payload.commit_sha?.toString().trim() ?? '';
      const versionName = payload.version_name?.toString().trim() ?? '';
      const previewBuildNumber = Number(payload.preview_build_number);

      if (
        !/^[0-9a-f]{40}$/i.test(commitSha) ||
        !versionName ||
        !Number.isInteger(previewBuildNumber) ||
        previewBuildNumber <= 0
      ) {
        return json({error: 'Identidad Preview inválida para candidato Producción'}, 400);
      }

      const {data: gate, error: gateError} = await admin
        .from('app_release_gate')
        .select(
          'preview_build_id,preview_commit_sha,preview_version_name,preview_build_number,production_store_build_number,next_production_build_number',
        )
        .eq('platform', 'android')
        .maybeSingle();
      if (gateError) throw gateError;

      if (
        !gate?.preview_build_id ||
        gate.preview_commit_sha !== commitSha ||
        gate.preview_version_name !== versionName ||
        Number(gate.preview_build_number) !== previewBuildNumber
      ) {
        return json({
          error:
            'Candidato Producción bloqueado: Preview vigente no coincide con SHA/versión/build recibido.',
          expected: gate ?? null,
          received: {
            commit_sha: commitSha,
            version_name: versionName,
            preview_build_number: previewBuildNumber,
          },
        }, 409);
      }

      const productionStoreBuildNumber = Number(gate.production_store_build_number);
      if (
        !Number.isInteger(productionStoreBuildNumber) ||
        productionStoreBuildNumber < 0
      ) {
        return json({error: 'No existe baseline de Google Play configurado'}, 409);
      }

      const productionBuildNumber = productionStoreBuildNumber + 1;
      if (Number(gate.next_production_build_number) !== productionBuildNumber) {
        return json({
          error:
            'Contador Producción inconsistente: next_production_build_number debe ser Google Play + 1.',
          production_store_build_number: productionStoreBuildNumber,
          expected_next_production_build_number: productionBuildNumber,
          received_next_production_build_number: gate.next_production_build_number,
        }, 409);
      }

      const {data: previewJob, error: previewJobError} = await admin
        .from('build_jobs')
        .select('created_by')
        .eq('id', gate.preview_build_id)
        .maybeSingle();
      if (previewJobError) throw previewJobError;

      const createdBy = previewJob?.created_by?.toString() ?? '';
      if (!createdBy) {
        return json({error: 'No se pudo resolver creador del candidato Producción'}, 409);
      }

      const {data: existing, error: existingError} = await admin
        .from('build_jobs')
        .select('id,status,commit_sha,version_name,build_number,workflow_run_id,apk_url,aab_url')
        .eq('platform', 'android')
        .eq('artifact_type', 'candidate-apk+aab')
        .eq('version_name', versionName)
        .eq('build_number', productionBuildNumber)
        .eq('commit_sha', commitSha)
        .order('created_at', {ascending: false})
        .limit(1);
      if (existingError) throw existingError;

      const existingJob = existing?.[0];
      if (existingJob && ['queued', 'building', 'ready'].includes(existingJob.status)) {
        return json({
          ok: true,
          reused: true,
          candidate_job_id: existingJob.id,
          status: existingJob.status,
          version_name: versionName,
          preview_build_number: previewBuildNumber,
          production_build_number: productionBuildNumber,
          commit_sha: commitSha,
          apk_url: existingJob.apk_url,
          aab_url: existingJob.aab_url,
          workflow_run_id: existingJob.workflow_run_id,
        });
      }

      const now = new Date().toISOString();

      const {error: cancelError} = await admin
        .from('build_jobs')
        .update({
          status: 'cancelled',
          error_message:
            'Reemplazado por una Preview más nueva para el mismo build de Producción ' +
            productionBuildNumber +
            '.',
          completed_at: now,
          updated_at: now,
        })
        .eq('platform', 'android')
        .eq('artifact_type', 'candidate-apk+aab')
        .eq('build_number', productionBuildNumber)
        .eq('status', 'queued')
        .neq('commit_sha', commitSha);
      if (cancelError) throw cancelError;

      const {data: inserted, error: insertError} = await admin
        .from('build_jobs')
        .insert({
          platform: 'android',
          artifact_type: 'candidate-apk+aab',
          version_name: versionName,
          build_number: productionBuildNumber,
          status: 'queued',
          changelog:
            'Candidato Producción precompilado automáticamente desde Preview ' +
            previewBuildNumber +
            '.',
          commit_sha: commitSha,
          created_by: createdBy,
          updated_at: now,
        })
        .select('id')
        .single();
      if (insertError) throw insertError;

      await admin
        .from('app_release_gate')
        .update({
          production_candidate_build_id: inserted.id,
          production_candidate_commit_sha: commitSha,
          production_candidate_version_name: versionName,
          production_candidate_build_number: productionBuildNumber,
          production_candidate_ready_at: null,
          production_candidate_promoted_at: null,
          updated_at: now,
        })
        .eq('platform', 'android');

      return json({
        ok: true,
        reused: false,
        candidate_job_id: inserted.id,
        status: 'queued',
        version_name: versionName,
        preview_build_number: previewBuildNumber,
        production_build_number: productionBuildNumber,
        commit_sha: commitSha,
      });
    }

    if (action === 'qa_certify') {
      const previewBuildId = payload.preview_build_id?.toString().trim() ?? '';
      const commitSha = payload.commit_sha?.toString().trim() ?? '';
      const versionName = payload.version_name?.toString().trim() ?? '';
      const buildNumber = Number(payload.build_number);
      const runId = payload.run_id?.toString().trim() ?? '';

      if (
        !previewBuildId ||
        !/^[0-9a-f]{40}$/i.test(commitSha) ||
        !versionName ||
        !Number.isInteger(buildNumber) ||
        buildNumber <= 0 ||
        !runId
      ) {
        return json({error: 'Certificación QA inválida'}, 400);
      }

      const {data: gate, error: gateError} = await admin
        .from('app_release_gate')
        .select(
          'preview_build_id,preview_commit_sha,preview_version_name,preview_build_number',
        )
        .eq('platform', 'android')
        .maybeSingle();
      if (gateError) throw gateError;

      if (
        !gate ||
        gate.preview_build_id !== previewBuildId ||
        gate.preview_commit_sha !== commitSha ||
        gate.preview_version_name !== versionName ||
        Number(gate.preview_build_number) !== buildNumber
      ) {
        return json({
          error:
            'QA no puede certificar: el gate cambió o no coincide con el Preview auditado.',
          expected: gate ?? null,
          received: {
            preview_build_id: previewBuildId,
            commit_sha: commitSha,
            version_name: versionName,
            build_number: buildNumber,
          },
        }, 409);
      }

      const now = new Date().toISOString();
      const {error: updateError} = await admin
        .from('app_release_gate')
        .update({
          qa_preview_build_id: previewBuildId,
          qa_commit_sha: commitSha,
          qa_workflow_run_id: runId,
          qa_passed_at: now,
          approved_preview_build_id: null,
          approved_commit_sha: null,
          approved_by: null,
          approved_at: null,
          updated_at: now,
        })
        .eq('platform', 'android');
      if (updateError) throw updateError;

      return json({
        ok: true,
        preview_build_id: previewBuildId,
        commit_sha: commitSha,
        version_name: versionName,
        build_number: buildNumber,
        qa_workflow_run_id: runId,
        qa_passed_at: now,
      });
    }

    if (action === 'release_gate_status') {
      const {data: gate, error: gateError} = await admin
        .from('app_release_gate')
        .select(
          'platform,preview_build_id,preview_base_commit_sha,preview_commit_sha,preview_version_name,preview_build_number,preview_ready_at,preview_patch_workflow_run_id,preview_patch_at,approved_preview_build_id,approved_commit_sha,approved_at,qa_preview_build_id,qa_commit_sha,qa_workflow_run_id,qa_passed_at,production_store_build_number,next_production_build_number,production_candidate_build_id,production_candidate_commit_sha,production_candidate_version_name,production_candidate_build_number,production_candidate_ready_at,production_candidate_promoted_at,production_build_id,production_commit_sha,production_ready_at,updated_at',
        )
        .eq('platform', 'android')
        .maybeSingle();
      if (gateError) throw gateError;

      return json({
        gate: gate ?? null,
        preview_current: Boolean(
          gate?.preview_build_id &&
          gate?.preview_commit_sha &&
          gate?.preview_version_name &&
          gate?.preview_build_number,
        ),
        preview_qa_certified: Boolean(
          gate?.qa_preview_build_id &&
          gate?.qa_preview_build_id === gate?.preview_build_id &&
          gate?.qa_commit_sha &&
          gate?.qa_commit_sha === gate?.preview_commit_sha &&
          gate?.qa_passed_at,
        ),
        production_candidate_ready: Boolean(
          gate?.production_candidate_build_id &&
          gate?.production_candidate_commit_sha === gate?.preview_commit_sha &&
          gate?.production_candidate_version_name === gate?.preview_version_name &&
          gate?.production_candidate_build_number &&
          gate?.production_candidate_ready_at,
        ),
        preview_approved: Boolean(
          gate?.approved_preview_build_id &&
          gate?.approved_preview_build_id === gate?.preview_build_id &&
          gate?.approved_commit_sha &&
          gate?.approved_commit_sha === gate?.preview_commit_sha,
        ),
      });
    }

    if (action === 'firebase_config') {
      const packageName = payload.package_name?.toString().trim() ?? '';
      const displayName =
        payload.display_name?.toString().trim() ||
        (packageName === 'com.express.usuario1'
          ? 'Express'
          : 'Express Preview');
      const config = await firebaseAndroidConfig(packageName, displayName);
      return json(config);
    }

    if (action === 'signing') {
      const {data: signing, error: signingError} =
        await admin.rpc('android_signing_config_for_worker');
      if (signingError) throw signingError;

      const config = signing as {
        alias: string;
        keystore_path: string;
        store_password: string;
        key_password: string;
      };

      const {data: existing, error: listError} = await admin.storage
        .from('android-signing')
        .list('', {search: config.keystore_path, limit: 20});
      if (listError) throw listError;

      const found = (existing ?? []).some(
        (item) => item.name === config.keystore_path,
      );

      if (found) {
        const {data: signed, error: signedError} = await admin.storage
          .from('android-signing')
          .createSignedUrl(config.keystore_path, 600);
        if (signedError) throw signedError;

        return json({
          mode: 'existing',
          alias: config.alias,
          store_password: config.store_password,
          key_password: config.key_password,
          keystore_path: config.keystore_path,
          download_url: signed.signedUrl,
        });
      }

      const {data: upload, error: uploadError} = await admin.storage
        .from('android-signing')
        .createSignedUploadUrl(config.keystore_path, {upsert: false});
      if (uploadError) throw uploadError;

      return json({
        mode: 'create',
        alias: config.alias,
        store_password: config.store_password,
        key_password: config.key_password,
        keystore_path: config.keystore_path,
        upload_token: upload.token,
        supabase_url: supabaseUrl,
      });
    }

    if (action === 'claim') {
      const requestedJobId = payload.job_id?.toString().trim();
      let query = admin
        .from('build_jobs')
        .select('*')
        .eq('platform', 'android')
        .eq('status', 'queued')
        .order('build_number', {ascending: false})
        .order('created_at', {ascending: false})
        .limit(1);

      if (requestedJobId) query = query.eq('id', requestedJobId);

      const {data: rows, error: readError} = await query;
      if (readError) throw readError;
      const job = rows?.[0];
      if (!job) return json({job: null});

      // Never compile an older queued build while a newer build of the same
      // artifact type is waiting. Explicit job IDs do not bypass this rule.
      const {data: newerRows, error: newerError} = await admin
        .from('build_jobs')
        .select('id,version_name,build_number')
        .eq('platform', 'android')
        .eq('artifact_type', job.artifact_type)
        .eq('status', 'queued')
        .gt('build_number', job.build_number)
        .order('build_number', {ascending: false})
        .limit(1);
      if (newerError) throw newerError;
      if ((newerRows ?? []).length > 0) {
        return json({
          error:
            'Build reemplazado por una versión más nueva en cola: ' +
            newerRows![0].version_name +
            '+' +
            newerRows![0].build_number,
        }, 409);
      }

      // Production candidates can compile before QA approval, but their
      // identity is immutable: current Preview SHA/version + next Google Play build.
      if (job.artifact_type === 'candidate-apk+aab') {
        const {data: gate, error: gateError} = await admin
          .from('app_release_gate')
          .select(
            'preview_build_id,preview_commit_sha,preview_version_name,preview_build_number,production_store_build_number,next_production_build_number,production_candidate_build_id,production_candidate_commit_sha,production_candidate_version_name,production_candidate_build_number',
          )
          .eq('platform', 'android')
          .maybeSingle();
        if (gateError) throw gateError;

        const expectedBuild = Number(gate?.production_store_build_number) + 1;
        const exactCandidate =
          gate?.preview_build_id &&
          Number.isInteger(expectedBuild) &&
          Number(gate?.next_production_build_number) === expectedBuild &&
          gate?.production_candidate_build_id === job.id &&
          gate?.production_candidate_commit_sha === gate.preview_commit_sha &&
          gate?.production_candidate_version_name === gate.preview_version_name &&
          Number(gate?.production_candidate_build_number) === expectedBuild &&
          job.commit_sha === gate.preview_commit_sha &&
          job.version_name === gate.preview_version_name &&
          Number(job.build_number) === expectedBuild;

        if (!exactCandidate) {
          return json({
            error:
              'Candidato Producción bloqueado por trazabilidad: debe ser Preview vigente + Google Play build siguiente.',
            expected: gate
              ? {
                  version_name: gate.preview_version_name,
                  preview_build_number: gate.preview_build_number,
                  production_build_number: expectedBuild,
                  commit_sha: gate.preview_commit_sha,
                }
              : null,
            received: {
              candidate_build_id: job.id,
              version_name: job.version_name,
              build_number: job.build_number,
              commit_sha: job.commit_sha,
            },
          }, 409);
        }
      }

      // Production is immutable: it must be the exact approved current Preview
      // in version, build number and source SHA.
      if (job.artifact_type === 'apk+aab') {
        const {data: gate, error: gateError} = await admin
          .from('app_release_gate')
          .select(
            'preview_build_id,preview_commit_sha,preview_version_name,preview_build_number,approved_preview_build_id,approved_commit_sha,qa_preview_build_id,qa_commit_sha,qa_passed_at,production_candidate_build_id,production_candidate_commit_sha,production_candidate_version_name,production_candidate_build_number,production_candidate_ready_at',
          )
          .eq('platform', 'android')
          .maybeSingle();
        if (gateError) throw gateError;

        const qaCertifiedCurrent =
          gate?.preview_build_id &&
          gate?.qa_preview_build_id === gate.preview_build_id &&
          gate?.preview_commit_sha &&
          gate?.qa_commit_sha === gate.preview_commit_sha &&
          gate?.qa_passed_at;

        if (!qaCertifiedCurrent) {
          return json({
            error:
              'Producción bloqueada: la Preview vigente todavía no pasó QA obligatorio.',
          }, 409);
        }

        const approvedCurrent =
          gate?.preview_build_id &&
          gate?.approved_preview_build_id === gate.preview_build_id &&
          gate?.preview_commit_sha &&
          gate?.approved_commit_sha === gate.preview_commit_sha;

        if (!approvedCurrent) {
          return json({
            error:
              'Producción bloqueada: aprueba la Preview vigente después de QA.',
          }, 409);
        }

        const candidateCurrent =
          gate?.production_candidate_build_id &&
          gate?.production_candidate_commit_sha === gate.preview_commit_sha &&
          gate?.production_candidate_version_name === gate.preview_version_name &&
          Number.isInteger(Number(gate?.production_candidate_build_number)) &&
          gate?.production_candidate_ready_at;

        if (!candidateCurrent) {
          return json({
            error:
              'Producción bloqueada: no existe candidato APK+AAB listo del mismo SHA.',
          }, 409);
        }

        if (
          job.version_name !== gate.production_candidate_version_name ||
          Number(job.build_number) !== Number(gate.production_candidate_build_number) ||
          job.commit_sha !== gate.approved_commit_sha
        ) {
          return json({
            error:
              'Producción bloqueada: debe usar el candidato exacto ya precompilado.',
            expected: {
              version_name: gate.production_candidate_version_name,
              production_build_number: gate.production_candidate_build_number,
              preview_build_number: gate.preview_build_number,
              commit_sha: gate.approved_commit_sha,
            },
            received: {
              version_name: job.version_name,
              build_number: job.build_number,
              commit_sha: job.commit_sha,
            },
          }, 409);
        }
      }

      // Once the newest candidate is selected, cancel stale queued jobs of the
      // same artifact type so future workflow runs cannot compile them later.
      const {error: cancelError} = await admin
        .from('build_jobs')
        .update({
          status: 'cancelled',
          error_message:
            'Reemplazado automáticamente por build ' +
            job.build_number +
            ' (' +
            job.version_name +
            ').',
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('platform', 'android')
        .eq('artifact_type', job.artifact_type)
        .eq('status', 'queued')
        .lt('build_number', job.build_number);
      if (cancelError) throw cancelError;

      const runId = payload.run_id?.toString() ?? '';
      const workflowCommitSha = payload.commit_sha?.toString() || null;
      // Si el panel ya fijó un SHA (por ejemplo el Preview aprobado para
      // Producción), ese SHA es autoritativo. El SHA del workflow solo se usa
      // para builds que todavía no tienen fuente fijada.
      const sourceCommitSha = job.commit_sha || workflowCommitSha;
      const runUrl = runId
        ? 'https://github.com/jorge2610g/Expressdelivery/actions/runs/' + runId
        : null;

      const {data: claimed, error: claimError} = await admin
        .from('build_jobs')
        .update({
          status: 'building',
          workflow_run_id: runId || null,
          commit_sha: sourceCommitSha,
          run_url: runUrl,
          started_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          error_message: null,
        })
        .eq('id', job.id)
        .eq('status', 'queued')
        .select('*')
        .maybeSingle();

      if (claimError) throw claimError;
      return json({job: claimed});
    }

    const jobId = payload.job_id?.toString();
    if (!jobId) return json({error: 'Falta job_id'}, 400);

    const {data: job, error: jobError} = await admin
      .from('build_jobs')
      .select('*')
      .eq('id', jobId)
      .single();
    if (jobError) throw jobError;

    if (action === 'upload_urls') {
      if (job.status !== 'building') {
        return json({error: 'Build no está en ejecución'}, 409);
      }

      const safeVersion = job.version_name
        .toString()
        .replace(/[^0-9A-Za-z._-]/g, '-');
      const base =
        'android/v' + safeVersion + '-build' + job.build_number;
      const apkPath =
        base + '/express-v' + safeVersion + '-build' + job.build_number + '.apk';
      const aabPath =
        base + '/express-v' + safeVersion + '-build' + job.build_number + '.aab';

      const [
        {data: apkSigned, error: apkError},
        {data: aabSigned, error: aabError},
      ] = await Promise.all([
        admin.storage
          .from('app-releases')
          .createSignedUploadUrl(apkPath, {upsert: true}),
        admin.storage
          .from('app-releases')
          .createSignedUploadUrl(aabPath, {upsert: true}),
      ]);

      if (apkError) throw apkError;
      if (aabError) throw aabError;

      return json({
        bucket: 'app-releases',
        apk: {path: apkPath, token: apkSigned.token},
        aab: {path: aabPath, token: aabSigned.token},
        supabase_url: supabaseUrl,
      });
    }

    if (action === 'complete') {
      const payloadSourceSha = payload.source_sha?.toString().trim() ?? '';
      const payloadSourceTreeSha =
        payload.source_tree_sha?.toString().trim() ?? '';
      const identityManifestSha256 =
        payload.identity_manifest_sha256?.toString().trim() ?? '';
      const apkSha256 = payload.apk_sha256?.toString().trim() ?? '';
      const aabSha256 = payload.aab_sha256?.toString().trim() ?? '';

      if (
        payloadSourceSha !== job.commit_sha ||
        !/^[0-9a-f]{40}$/i.test(payloadSourceTreeSha) ||
        !/^[0-9a-f]{64}$/i.test(identityManifestSha256) ||
        !/^[0-9a-f]{64}$/i.test(apkSha256)
      ) {
        return json({
          error:
            'Build descartado: manifiesto/hashes de identidad incompletos o SHA fuente distinto al job.',
        }, 409);
      }

      if (
        ['candidate-apk+aab', 'apk+aab'].includes(job.artifact_type) &&
        !/^[0-9a-f]{64}$/i.test(aabSha256)
      ) {
        return json({error: 'Build descartado: falta SHA-256 válido del AAB.'}, 409);
      }

      if (job.artifact_type === 'candidate-apk+aab') {
        const {data: gate, error: gateError} = await admin
          .from('app_release_gate')
          .select(
            'preview_build_id,preview_commit_sha,preview_version_name,preview_build_number,production_store_build_number,next_production_build_number,production_candidate_build_id,production_candidate_commit_sha,production_candidate_version_name,production_candidate_build_number',
          )
          .eq('platform', 'android')
          .maybeSingle();
        if (gateError) throw gateError;

        const expectedBuild = Number(gate?.production_store_build_number) + 1;
        const exactMatch =
          gate?.preview_build_id &&
          Number(gate?.next_production_build_number) === expectedBuild &&
          gate?.production_candidate_build_id === job.id &&
          gate?.production_candidate_commit_sha === gate.preview_commit_sha &&
          gate?.production_candidate_version_name === gate.preview_version_name &&
          Number(gate?.production_candidate_build_number) === expectedBuild &&
          job.version_name === gate.preview_version_name &&
          Number(job.build_number) === expectedBuild &&
          job.commit_sha === gate.preview_commit_sha;

        if (!exactMatch) {
          return json({
            error:
              'Candidato Producción descartado al finalizar: el gate/Preview cambió durante la compilación.',
          }, 409);
        }
      }

      if (job.artifact_type === 'apk+aab') {
        const {data: gate, error: gateError} = await admin
          .from('app_release_gate')
          .select(
            'preview_build_id,preview_commit_sha,preview_version_name,preview_build_number,approved_preview_build_id,approved_commit_sha,production_candidate_build_id,production_candidate_commit_sha,production_candidate_version_name,production_candidate_build_number,production_candidate_ready_at',
          )
          .eq('platform', 'android')
          .maybeSingle();
        if (gateError) throw gateError;

        const exactMatch =
          gate?.preview_build_id &&
          gate?.approved_preview_build_id === gate.preview_build_id &&
          gate?.preview_commit_sha &&
          gate?.approved_commit_sha === gate.preview_commit_sha &&
          gate?.production_candidate_build_id &&
          gate?.production_candidate_commit_sha === gate.preview_commit_sha &&
          gate?.production_candidate_ready_at &&
          job.version_name === gate.production_candidate_version_name &&
          Number(job.build_number) === Number(gate.production_candidate_build_number) &&
          job.commit_sha === gate.approved_commit_sha;

        if (!exactMatch) {
          return json({
            error:
              'Producción descartada antes de publicar: la Preview vigente/aprobada cambió durante la compilación.',
          }, 409);
        }
      }

      const explicitApkUrl = payload.apk_url?.toString();
      const explicitAabUrl = payload.aab_url?.toString();
      const apkPath = payload.apk_path?.toString();
      const aabPath = payload.aab_path?.toString();

      const apkUrl = explicitApkUrl ||
        (apkPath
          ? supabaseUrl + '/storage/v1/object/public/app-releases/' + apkPath
          : null);
      const aabUrl = explicitAabUrl ||
        (aabPath
          ? supabaseUrl + '/storage/v1/object/public/app-releases/' + aabPath
          : null);

      const productionBuild = job.artifact_type === 'apk+aab';
      const productionCandidate = job.artifact_type === 'candidate-apk+aab';
      const requiresBundle = productionBuild || productionCandidate;
      if (!apkUrl || (requiresBundle && !aabUrl)) {
        return json({
          error: requiresBundle
            ? 'Faltan URLs de APK/AAB Android'
            : 'Falta URL del APK Preview',
        }, 400);
      }

      const {error} = await admin
        .from('build_jobs')
        .update({
          status: 'ready',
          apk_url: apkUrl,
          aab_url: requiresBundle ? aabUrl : null,
          artifact_url: apkUrl,
          apk_sha256: apkSha256 || null,
          aab_sha256: requiresBundle ? (aabSha256 || null) : null,
          source_tree_sha: payloadSourceTreeSha || null,
          identity_manifest_sha256: identityManifestSha256 || null,
          signing_mode: payload.signing_mode?.toString() ?? 'test',
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          error_message: null,
        })
        .eq('id', jobId);
      if (error) throw error;

      return json({ok: true, apk_url: apkUrl, aab_url: requiresBundle ? aabUrl : null});
    }

    if (action === 'fail') {
      const message =
        (payload.error_message?.toString() ?? 'Build falló').slice(0, 4000);

      const {error} = await admin
        .from('build_jobs')
        .update({
          status: 'failed',
          error_message: message,
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', jobId);
      if (error) throw error;

      return json({ok: true});
    }

    return json({error: 'Acción desconocida'}, 400);
  } catch (error) {
    return json(
      {error: error instanceof Error ? error.message : String(error)},
      401,
    );
  }
});
