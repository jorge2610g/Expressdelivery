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
  if (!workflowRef.includes('/.github/workflows/build-android.yml@refs/heads/main')) {
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
      const commitSha = payload.commit_sha?.toString() || null;
      const runUrl = runId
        ? 'https://github.com/jorge2610g/Expressdelivery/actions/runs/' + runId
        : null;

      const {data: claimed, error: claimError} = await admin
        .from('build_jobs')
        .update({
          status: 'building',
          workflow_run_id: runId || null,
          commit_sha: commitSha ?? job.commit_sha,
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
      const apkPath = payload.apk_path?.toString();
      const aabPath = payload.aab_path?.toString();
      if (!apkPath || !aabPath) {
        return json({error: 'Faltan rutas de artefactos'}, 400);
      }

      const apkUrl =
        supabaseUrl + '/storage/v1/object/public/app-releases/' + apkPath;
      const aabUrl =
        supabaseUrl + '/storage/v1/object/public/app-releases/' + aabPath;

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
