-- Reserve a fresh versionCode as soon as a signed APK+AAB pair has been
-- uploaded to Google Play Internal and marked ready. Keep the Production
-- baseline unchanged until the owner explicitly promotes that same pair.

CREATE OR REPLACE FUNCTION public.advance_android_store_build_after_promotion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NEW.platform = 'android'
     AND NEW.artifact_type = 'single-app-candidate-apk+aab'
     AND NEW.status = 'ready'
     AND NEW.signing_mode = 'production'
     AND NEW.apk_url IS NOT NULL
     AND NEW.aab_url IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    -- The build worker marks a candidate ready only after the paired AAB was
    -- accepted by the Play Internal upload step. Only advance the code that
    -- this job reserved; repeated updates cannot skip a later reservation.
    UPDATE public.app_release_gate
       SET next_production_build_number = GREATEST(
             COALESCE(next_production_build_number, production_store_build_number + 1),
             NEW.build_number + 1
           ),
           updated_at = now()
     WHERE platform = 'android'
       AND production_store_build_number IS NOT NULL
       AND next_production_build_number = NEW.build_number;
  ELSIF NEW.platform = 'android'
     AND NEW.artifact_type = 'apk+aab'
     AND NEW.status = 'ready'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    -- Promotion updates the verified Production baseline, and leaves the
    -- counter at least one higher than both the baseline and reserved codes.
    UPDATE public.app_release_gate
       SET production_store_build_number = NEW.build_number,
           next_production_build_number = GREATEST(
             COALESCE(next_production_build_number, NEW.build_number + 1),
             NEW.build_number + 1
           ),
           updated_at = now()
     WHERE platform = 'android'
       AND production_candidate_build_number = NEW.build_number
       AND production_candidate_commit_sha = NEW.commit_sha;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_approve_single_app_candidate(
  p_candidate_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_job public.build_jobs%rowtype;
  v_qa public.android_single_app_candidates%rowtype;
  v_gate public.app_release_gate%rowtype;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_job FROM public.build_jobs WHERE id = p_candidate_id FOR UPDATE;
  SELECT * INTO v_qa FROM public.android_single_app_candidates
   WHERE candidate_build_id = p_candidate_id FOR UPDATE;
  SELECT * INTO v_gate FROM public.app_release_gate
   WHERE platform = 'android' FOR UPDATE;

  IF v_job.id IS NULL OR v_qa.candidate_build_id IS NULL OR v_gate.platform IS NULL
     OR v_job.status <> 'ready'
     OR v_job.artifact_type <> 'single-app-candidate-apk+aab'
     OR v_job.signing_mode <> 'production'
     OR v_qa.qa_verified_at IS NULL
     OR v_qa.promoted_build_id IS NOT NULL
     OR v_qa.qa_source_sha IS DISTINCT FROM v_job.commit_sha
     OR v_qa.qa_tree_sha IS DISTINCT FROM v_job.source_tree_sha
     OR v_qa.qa_apk_sha256 IS DISTINCT FROM v_job.apk_sha256
     OR v_qa.qa_aab_sha256 IS DISTINCT FROM v_job.aab_sha256
     OR v_qa.qa_manifest_sha256 IS DISTINCT FROM v_job.identity_manifest_sha256
     OR v_gate.next_production_build_number IS NULL
     OR v_job.build_number >= v_gate.next_production_build_number
     OR v_gate.next_production_build_number < v_gate.production_store_build_number + 1 THEN
    RAISE EXCEPTION 'Aprobación bloqueada: QA, hashes, firma o contador no coinciden';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.build_jobs j
     WHERE j.platform = 'android'
       AND j.artifact_type = 'single-app-candidate-apk+aab'
       AND j.created_at > v_job.created_at
  ) THEN
    RAISE EXCEPTION 'Un candidato más nuevo reemplazó esta compilación';
  END IF;

  UPDATE public.android_single_app_candidates
     SET approved_by = auth.uid(), approved_at = now()
   WHERE candidate_build_id = p_candidate_id;
  PERFORM public.admin_log_action(
    'approve', 'single_app_candidate', p_candidate_id::text,
    jsonb_build_object('sha', v_job.commit_sha, 'build', v_job.build_number,
      'apk_sha256', v_job.apk_sha256, 'aab_sha256', v_job.aab_sha256)
  );
  RETURN public.admin_single_app_release_status();
END;
$body$;

CREATE OR REPLACE FUNCTION public.admin_promote_single_app_candidate(
  p_candidate_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_job public.build_jobs%rowtype;
  v_qa public.android_single_app_candidates%rowtype;
  v_gate public.app_release_gate%rowtype;
  v_new_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_job FROM public.build_jobs WHERE id = p_candidate_id FOR UPDATE;
  SELECT * INTO v_qa FROM public.android_single_app_candidates
   WHERE candidate_build_id = p_candidate_id FOR UPDATE;
  SELECT * INTO v_gate FROM public.app_release_gate
   WHERE platform = 'android' FOR UPDATE;

  IF v_job.id IS NULL OR v_qa.candidate_build_id IS NULL OR v_gate.platform IS NULL
     OR v_job.artifact_type <> 'single-app-candidate-apk+aab'
     OR v_job.platform <> 'android' OR v_job.status <> 'ready'
     OR v_job.signing_mode <> 'production'
     OR v_job.apk_url IS NULL OR v_job.aab_url IS NULL
     OR v_qa.qa_verified_at IS NULL OR v_qa.approved_at IS NULL
     OR v_qa.promoted_build_id IS NOT NULL
     OR v_qa.qa_source_sha IS DISTINCT FROM v_job.commit_sha
     OR v_qa.qa_tree_sha IS DISTINCT FROM v_job.source_tree_sha
     OR v_qa.qa_apk_sha256 IS DISTINCT FROM v_job.apk_sha256
     OR v_qa.qa_aab_sha256 IS DISTINCT FROM v_job.aab_sha256
     OR v_qa.qa_manifest_sha256 IS DISTINCT FROM v_job.identity_manifest_sha256
     OR v_gate.next_production_build_number IS NULL
     OR v_job.build_number >= v_gate.next_production_build_number
     OR v_gate.next_production_build_number < v_gate.production_store_build_number + 1 THEN
    RAISE EXCEPTION 'Promoción bloqueada: candidato no certificado/aprobado o hashes incompatibles';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.build_jobs j
     WHERE j.platform = 'android'
       AND j.artifact_type = 'single-app-candidate-apk+aab'
       AND j.created_at > v_job.created_at
  ) THEN
    RAISE EXCEPTION 'Promoción bloqueada: el candidato ya fue reemplazado';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.build_jobs j
     WHERE j.platform = 'android'
       AND j.artifact_type = 'apk+aab'
       AND j.build_number = v_job.build_number
       AND j.status = 'ready'
  ) THEN
    RAISE EXCEPTION 'Ya se promovió el versionCode %', v_job.build_number;
  END IF;

  INSERT INTO public.build_jobs(
    platform, artifact_type, version_name, build_number, status, changelog,
    commit_sha, workflow_run_id, artifact_url, created_by, completed_at,
    apk_url, aab_url, run_url, signing_mode, started_at, apk_sha256,
    aab_sha256, source_tree_sha, identity_manifest_sha256
  ) VALUES (
    'android', 'apk+aab', v_job.version_name, v_job.build_number, 'ready',
    'Promoción sin recompilar del APK/AAB Producción QA certificado: ' ||
      coalesce(v_qa.qa_notes, ''),
    v_job.commit_sha, v_job.workflow_run_id, v_job.artifact_url, auth.uid(), now(),
    v_job.apk_url, v_job.aab_url, v_job.run_url, 'production', v_job.started_at,
    v_job.apk_sha256, v_job.aab_sha256, v_job.source_tree_sha,
    v_job.identity_manifest_sha256
  ) RETURNING id INTO v_new_id;

  UPDATE public.android_single_app_candidates
     SET promoted_build_id = v_new_id, promoted_at = now()
   WHERE candidate_build_id = p_candidate_id;
  UPDATE public.app_release_gate
     SET production_store_build_number = v_job.build_number,
         production_candidate_build_id = v_job.id,
         production_candidate_commit_sha = v_job.commit_sha,
         production_candidate_version_name = v_job.version_name,
         production_candidate_build_number = v_job.build_number,
         production_candidate_ready_at = v_job.completed_at,
         production_candidate_promoted_at = now(),
         updated_at = now()
   WHERE platform = 'android';

  PERFORM public.admin_log_action(
    'promote', 'single_app_candidate', p_candidate_id::text,
    jsonb_build_object('production_build_id', v_new_id, 'sha', v_job.commit_sha,
      'version_name', v_job.version_name, 'build_number', v_job.build_number,
      'apk_sha256', v_job.apk_sha256, 'aab_sha256', v_job.aab_sha256)
  );
  RETURN public.admin_single_app_release_status();
END;
$body$;
