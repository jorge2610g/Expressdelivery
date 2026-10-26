-- Google Play Production is the source of truth for the verified Android
-- version. Polling this table never turns on an in-app notice by itself.
CREATE TABLE IF NOT EXISTS public.android_play_production_sync (
  build_number integer PRIMARY KEY CHECK (build_number > 0),
  package_name text NOT NULL CHECK (package_name = 'com.express.usuario1'),
  version_name text NOT NULL,
  release_status text NOT NULL CHECK (release_status IN ('completed','inProgress','halted','draft')),
  user_fraction numeric CHECK (user_fraction IS NULL OR (user_fraction >= 0 AND user_fraction <= 1)),
  release_name text,
  matched_build_job_id uuid REFERENCES public.build_jobs(id),
  available_to_all boolean NOT NULL DEFAULT false,
  observed_at timestamptz NOT NULL DEFAULT now()
);

REVOKE ALL ON TABLE public.android_play_production_sync FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.android_play_production_sync TO service_role;

CREATE OR REPLACE FUNCTION public.sync_google_play_production_releases(p_releases jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_release jsonb;
  v_code jsonb;
  v_build integer;
  v_version text;
  v_version_name text;
  v_release_status text;
  v_fraction numeric;
  v_release_name text;
  v_package text;
  v_job public.build_jobs%rowtype;
  v_qa public.android_single_app_candidates%rowtype;
  v_gate public.app_release_gate%rowtype;
  v_synced integer := 0;
  v_advanced integer := 0;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Solo el sincronizador autorizado de Play puede registrar versiones';
  END IF;
  IF jsonb_typeof(p_releases) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_releases) > 20 THEN
    RAISE EXCEPTION 'Respuesta de Google Play inválida';
  END IF;

  SELECT * INTO v_gate FROM public.app_release_gate
   WHERE platform='android' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No existe el control Android'; END IF;

  FOR v_release IN SELECT value FROM jsonb_array_elements(p_releases)
  LOOP
    v_package := v_release->>'package_name';
    v_version_name := trim(coalesce(v_release->>'version_name',''));
    v_release_status := v_release->>'status';
    v_release_name := left(coalesce(v_release->>'name',''),250);
    v_fraction := nullif(v_release->>'user_fraction','')::numeric;
    IF v_package IS DISTINCT FROM 'com.express.usuario1'
       OR v_release_status IS NULL
       OR v_version_name !~ '^\d+\.\d+\.\d+$'
       OR v_release_status NOT IN ('completed','inProgress','halted','draft')
       OR jsonb_typeof(v_release->'version_codes') IS DISTINCT FROM 'array'
       OR jsonb_array_length(v_release->'version_codes') < 1 THEN
      RAISE EXCEPTION 'Release de Google Play no coincide con Express Android';
    END IF;

    FOR v_code IN SELECT value FROM jsonb_array_elements(v_release->'version_codes')
    LOOP
      v_build := (v_code #>> '{}')::integer;
      IF v_build <= 0 THEN RAISE EXCEPTION 'versionCode inválido'; END IF;

      v_job := NULL;
      v_qa := NULL;
      IF v_release_status = 'completed' THEN
        SELECT * INTO v_job FROM public.build_jobs b
         WHERE b.platform='android' AND b.build_number=v_build
           AND b.version_name=v_version_name AND b.status='ready'
           AND b.signing_mode='production'
           AND b.artifact_type='single-app-candidate-apk+aab'
           AND b.apk_url IS NOT NULL AND b.aab_url IS NOT NULL
         ORDER BY b.created_at DESC LIMIT 1;
        IF v_job.id IS NOT NULL THEN
          SELECT * INTO v_qa FROM public.android_single_app_candidates q
           WHERE q.candidate_build_id=v_job.id;
          IF v_qa.qa_verified_at IS NULL
             OR v_qa.qa_source_sha IS DISTINCT FROM v_job.commit_sha
             OR v_qa.qa_tree_sha IS DISTINCT FROM v_job.source_tree_sha
             OR v_qa.qa_apk_sha256 IS DISTINCT FROM v_job.apk_sha256
             OR v_qa.qa_aab_sha256 IS DISTINCT FROM v_job.aab_sha256
             OR v_qa.qa_manifest_sha256 IS DISTINCT FROM v_job.identity_manifest_sha256 THEN
            v_job := NULL;
          END IF;
        END IF;
      END IF;

      INSERT INTO public.android_play_production_sync(
        build_number,package_name,version_name,release_status,user_fraction,
        release_name,matched_build_job_id,available_to_all,observed_at
      ) VALUES (
        v_build,v_package,v_version_name,v_release_status,v_fraction,
        v_release_name,v_job.id,
        v_release_status='completed' AND v_job.id IS NOT NULL,now()
      ) ON CONFLICT(build_number) DO UPDATE SET
        package_name=excluded.package_name,
        version_name=excluded.version_name,
        release_status=excluded.release_status,
        user_fraction=excluded.user_fraction,
        release_name=excluded.release_name,
        matched_build_job_id=excluded.matched_build_job_id,
        available_to_all=excluded.available_to_all,
        observed_at=excluded.observed_at;
      v_synced := v_synced + 1;

      -- Only a completed, fully available Play release with matching signed
      -- artifacts and QA hashes advances the production baseline. It does not
      -- enable an update notice, force an update, or send a push.
      IF v_release_status='completed' AND v_job.id IS NOT NULL
         AND v_build >= coalesce(v_gate.production_store_build_number,0) THEN
        UPDATE public.app_release_gate SET
          production_store_build_number=v_build,
          next_production_build_number=greatest(
            coalesce(next_production_build_number, v_build+1),v_build+1
          ),
          production_verified_build_job_id=v_job.id,
          updated_at=now()
        WHERE platform='android';
        v_gate.production_store_build_number := v_build;
        v_gate.production_verified_build_job_id := v_job.id;
        v_gate.next_production_build_number := greatest(
          coalesce(v_gate.next_production_build_number,v_build+1),v_build+1
        );
        v_advanced := v_advanced + 1;
      END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'synced_releases',v_synced,'production_build_advanced',v_advanced,
    'production_store_build',v_gate.production_store_build_number,
    'next_production_build',v_gate.next_production_build_number
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.sync_google_play_production_releases(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_google_play_production_releases(jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_single_app_release_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_gate public.app_release_gate%rowtype;
  v_job public.build_jobs%rowtype;
  v_cert public.android_single_app_candidates%rowtype;
  v_play jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_gate FROM public.app_release_gate WHERE platform='android';
  SELECT * INTO v_job FROM public.build_jobs
   WHERE platform='android' AND artifact_type='single-app-candidate-apk+aab'
   ORDER BY created_at DESC LIMIT 1;
  IF v_job.id IS NOT NULL THEN
    SELECT * INTO v_cert FROM public.android_single_app_candidates
     WHERE candidate_build_id=v_job.id;
  END IF;
  SELECT jsonb_build_object(
    'build_number',s.build_number,'version_name',s.version_name,
    'status',s.release_status,'user_fraction',s.user_fraction,
    'available_to_all',s.available_to_all,
    'matched_build_job_id',s.matched_build_job_id,
    'release_name',s.release_name,'observed_at',s.observed_at
  ) INTO v_play FROM public.android_play_production_sync s
   ORDER BY s.build_number DESC LIMIT 1;
  RETURN jsonb_build_object(
    'release_mode','single_app','preview_apk_required',false,
    'next_google_play_build',v_gate.next_production_build_number,
    'production_store_build',v_gate.production_store_build_number,
    'production_verified_build_job_id',v_gate.production_verified_build_job_id,
    'candidate',CASE WHEN v_job.id IS NULL THEN NULL ELSE to_jsonb(v_job) END,
    'verification',CASE WHEN v_cert.candidate_build_id IS NULL THEN NULL ELSE to_jsonb(v_cert) END,
    'qa_certified',v_cert.qa_verified_at IS NOT NULL,
    'approved',v_cert.approved_at IS NOT NULL,
    'promoted',v_cert.promoted_build_id IS NOT NULL,
    'play_sync',v_play
  );
END;
$function$;
