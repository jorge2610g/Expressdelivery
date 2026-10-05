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
        .order('created_at', {ascending: true})
        .limit(1);

      if (requestedJobId) query = query.eq('id', requestedJobId);

      const {data: rows, error: readError} = await query;
      if (readError) throw readError;
      const job = rows?.[0];
      if (!job) return json({job: null});

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

      if (!apkUrl || !aabUrl) {
        return json({error: 'Faltan URLs de artefactos'}, 400);
      }

      const {error} = await admin
        .from('build_jobs')
        .update({
          status: 'ready',
          apk_url: apkUrl,
          aab_url: aabUrl,
          artifact_url: apkUrl,
          signing_mode: payload.signing_mode?.toString() ?? 'test',
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          error_message: null,
        })
        .eq('id', jobId);
      if (error) throw error;

      return json({ok: true, apk_url: apkUrl, aab_url: aabUrl});
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
