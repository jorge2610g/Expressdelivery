-- Allow an explicitly reserved Play versionCode to skip codes already
-- uploaded to Internal while keeping the verified Production baseline truthful.
-- For this release, Production remains 141 and the next candidate is 143 because
-- the signed 1.6.3+142 candidate is already in Google Play Internal.
CREATE OR REPLACE FUNCTION public.normalize_android_production_counter()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $body$
BEGIN
  IF NEW.platform = 'android'
     AND NEW.production_store_build_number IS NOT NULL THEN
    NEW.next_production_build_number := GREATEST(
      COALESCE(NEW.next_production_build_number, NEW.production_store_build_number + 1),
      NEW.production_store_build_number + 1
    );
  END IF;
  RETURN NEW;
END; $body$;

CREATE OR REPLACE FUNCTION public.enforce_android_store_build_sequence()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $body$
DECLARE v_gate public.app_release_gate%rowtype; v_expected integer;
BEGIN
  IF NEW.platform <> 'android'
     OR NEW.artifact_type NOT IN ('candidate-apk+aab','single-app-candidate-apk+aab','apk+aab')
     OR NEW.status NOT IN ('queued','building','ready') THEN RETURN NEW; END IF;
  SELECT * INTO v_gate FROM public.app_release_gate WHERE platform='android';
  IF NOT FOUND OR v_gate.production_store_build_number IS NULL THEN
    RAISE EXCEPTION 'Build Producción bloqueado: falta baseline Google Play';
  END IF;
  IF NEW.artifact_type = 'single-app-candidate-apk+aab' THEN
    v_expected := v_gate.next_production_build_number;
    IF v_expected IS NULL OR v_expected < v_gate.production_store_build_number + 1 THEN
      RAISE EXCEPTION 'Build Producción bloqueado: reserva inferior al siguiente versionCode permitido';
    END IF;
  ELSE
    v_expected := v_gate.production_store_build_number + 1;
    IF v_gate.next_production_build_number IS DISTINCT FROM v_expected THEN
      RAISE EXCEPTION 'Build Producción bloqueado: contador inconsistente; esperado %, recibido %',
        v_expected, v_gate.next_production_build_number;
    END IF;
  END IF;
  IF NEW.build_number IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'Build Producción bloqueado: siguiente versionCode reservado es %',
      v_expected;
  END IF;
  IF NEW.artifact_type='candidate-apk+aab'
     AND (v_gate.preview_commit_sha IS NULL
      OR NEW.commit_sha IS DISTINCT FROM v_gate.preview_commit_sha
      OR NEW.version_name IS DISTINCT FROM v_gate.preview_version_name) THEN
    RAISE EXCEPTION 'Candidato heredado bloqueado: versión/SHA no coincide con Preview';
  END IF;
  IF NEW.artifact_type='single-app-candidate-apk+aab'
     AND NEW.commit_sha IS NOT NULL
     AND NEW.commit_sha !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'SHA Android unificado inválido';
  END IF;
  RETURN NEW;
END; $body$;

CREATE OR REPLACE FUNCTION public.admin_queue_single_app_candidate(
  p_version_name text, p_changelog text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $body$
DECLARE v_gate public.app_release_gate%rowtype; v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  IF trim(coalesce(p_version_name,'')) !~ '^[0-9]+[.][0-9]+[.][0-9]+$' THEN
    RAISE EXCEPTION 'Versión semántica inválida';
  END IF;
  SELECT * INTO v_gate FROM public.app_release_gate WHERE platform='android' FOR UPDATE;
  IF NOT FOUND OR v_gate.production_store_build_number IS NULL
      OR v_gate.next_production_build_number < v_gate.production_store_build_number + 1 THEN
    RAISE EXCEPTION 'Falta baseline de Google Play o el contador no coincide';
  END IF;
  IF EXISTS (SELECT 1 FROM public.build_jobs WHERE platform='android'
     AND artifact_type='single-app-candidate-apk+aab' AND status IN ('queued','building')) THEN
    RAISE EXCEPTION 'Ya existe un candidato unificado en cola o compilándose';
  END IF;
  INSERT INTO public.build_jobs(
    platform,artifact_type,version_name,build_number,created_by,commit_sha,changelog,status
  ) VALUES ('android','single-app-candidate-apk+aab',trim(p_version_name),
    v_gate.next_production_build_number,auth.uid(),NULL,
    coalesce(p_changelog,'Express Android · una sola app, QA sobre el APK real.'),
    'queued')
  RETURNING id INTO v_id;
  INSERT INTO public.android_single_app_candidates(candidate_build_id) VALUES(v_id);
  PERFORM public.admin_log_action('create','single_app_candidate',v_id::text,
    jsonb_build_object('version_name',trim(p_version_name),
      'build_number',v_gate.next_production_build_number));
  RETURN v_id;
END; $body$;

CREATE OR REPLACE FUNCTION public.admin_approve_single_app_candidate(
  p_candidate_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $body$
DECLARE v_job public.build_jobs%rowtype;
        v_qa public.android_single_app_candidates%rowtype;
        v_gate public.app_release_gate%rowtype;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_job FROM public.build_jobs WHERE id=p_candidate_id FOR UPDATE;
  SELECT * INTO v_qa FROM public.android_single_app_candidates WHERE candidate_build_id=p_candidate_id FOR UPDATE;
  SELECT * INTO v_gate FROM public.app_release_gate WHERE platform='android' FOR UPDATE;
  IF v_job.id IS NULL OR v_qa.candidate_build_id IS NULL OR v_gate.platform IS NULL
     OR v_job.status<>'ready' OR v_job.artifact_type<>'single-app-candidate-apk+aab'
     OR v_job.signing_mode<>'production' OR v_qa.qa_verified_at IS NULL
     OR v_qa.promoted_build_id IS NOT NULL
     OR v_qa.qa_source_sha IS DISTINCT FROM v_job.commit_sha
     OR v_qa.qa_tree_sha IS DISTINCT FROM v_job.source_tree_sha
     OR v_qa.qa_apk_sha256 IS DISTINCT FROM v_job.apk_sha256
     OR v_qa.qa_aab_sha256 IS DISTINCT FROM v_job.aab_sha256
     OR v_qa.qa_manifest_sha256 IS DISTINCT FROM v_job.identity_manifest_sha256
     OR v_job.build_number IS DISTINCT FROM v_gate.next_production_build_number
     OR v_gate.next_production_build_number < v_gate.production_store_build_number+1 THEN
    RAISE EXCEPTION 'Aprobación bloqueada: QA, hashes, firma o contador no coinciden';
  END IF;
  IF EXISTS(SELECT 1 FROM public.build_jobs j WHERE j.artifact_type='single-app-candidate-apk+aab'
     AND j.created_at>v_job.created_at) THEN
    RAISE EXCEPTION 'Un candidato más nuevo reemplazó esta compilación';
  END IF;
  UPDATE public.android_single_app_candidates
    SET approved_by=auth.uid(),approved_at=now()
    WHERE candidate_build_id=p_candidate_id;
  PERFORM public.admin_log_action('approve','single_app_candidate',p_candidate_id::text,
    jsonb_build_object('sha',v_job.commit_sha,'build',v_job.build_number,
      'apk_sha256',v_job.apk_sha256,'aab_sha256',v_job.aab_sha256));
  RETURN public.admin_single_app_release_status();
END; $body$;

CREATE OR REPLACE FUNCTION public.admin_promote_single_app_candidate(
  p_candidate_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $body$
DECLARE v_job public.build_jobs%rowtype;
        v_qa public.android_single_app_candidates%rowtype;
        v_gate public.app_release_gate%rowtype;
        v_new_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_job FROM public.build_jobs WHERE id=p_candidate_id FOR UPDATE;
  SELECT * INTO v_qa FROM public.android_single_app_candidates
    WHERE candidate_build_id=p_candidate_id FOR UPDATE;
  SELECT * INTO v_gate FROM public.app_release_gate WHERE platform='android' FOR UPDATE;
  IF v_job.id IS NULL OR v_qa.candidate_build_id IS NULL OR v_gate.platform IS NULL
     OR v_job.artifact_type<>'single-app-candidate-apk+aab'
     OR v_job.platform<>'android' OR v_job.status<>'ready'
     OR v_job.signing_mode<>'production'
     OR v_job.apk_url IS NULL OR v_job.aab_url IS NULL
     OR v_qa.qa_verified_at IS NULL OR v_qa.approved_at IS NULL
     OR v_qa.promoted_build_id IS NOT NULL
     OR v_qa.qa_source_sha IS DISTINCT FROM v_job.commit_sha
     OR v_qa.qa_tree_sha IS DISTINCT FROM v_job.source_tree_sha
     OR v_qa.qa_apk_sha256 IS DISTINCT FROM v_job.apk_sha256
     OR v_qa.qa_aab_sha256 IS DISTINCT FROM v_job.aab_sha256
     OR v_qa.qa_manifest_sha256 IS DISTINCT FROM v_job.identity_manifest_sha256
     OR v_job.build_number IS DISTINCT FROM v_gate.next_production_build_number
     OR v_gate.next_production_build_number < v_gate.production_store_build_number+1 THEN
    RAISE EXCEPTION 'Promoción bloqueada: candidato no certificado/aprobado o hashes incompatibles';
  END IF;
  IF EXISTS(SELECT 1 FROM public.build_jobs j WHERE j.artifact_type='single-app-candidate-apk+aab'
     AND j.created_at>v_job.created_at) THEN
    RAISE EXCEPTION 'Promoción bloqueada: el candidato ya fue reemplazado';
  END IF;
  IF EXISTS(SELECT 1 FROM public.build_jobs j WHERE j.platform='android'
     AND j.artifact_type='apk+aab' AND j.build_number=v_job.build_number
     AND j.status='ready') THEN
    RAISE EXCEPTION 'Ya se promovió el versionCode %',v_job.build_number;
  END IF;
  INSERT INTO public.build_jobs(
    platform,artifact_type,version_name,build_number,status,changelog,
    commit_sha,workflow_run_id,artifact_url,created_by,completed_at,
    apk_url,aab_url,run_url,signing_mode,started_at,apk_sha256,aab_sha256,
    source_tree_sha,identity_manifest_sha256
  ) VALUES (
    'android','apk+aab',v_job.version_name,v_job.build_number,'ready',
    'Promoción sin recompilar del APK/AAB Producción QA certificado: ' ||
      coalesce(v_qa.qa_notes,''),
    v_job.commit_sha,v_job.workflow_run_id,v_job.artifact_url,auth.uid(),now(),
    v_job.apk_url,v_job.aab_url,v_job.run_url,'production',v_job.started_at,
    v_job.apk_sha256,v_job.aab_sha256,v_job.source_tree_sha,
    v_job.identity_manifest_sha256
  ) RETURNING id INTO v_new_id;
  UPDATE public.android_single_app_candidates
     SET promoted_build_id=v_new_id,promoted_at=now()
    WHERE candidate_build_id=p_candidate_id;
  UPDATE public.app_release_gate
     SET production_store_build_number=v_job.build_number,
         production_candidate_build_id=v_job.id,
         production_candidate_commit_sha=v_job.commit_sha,
         production_candidate_version_name=v_job.version_name,
         production_candidate_build_number=v_job.build_number,
         production_candidate_ready_at=v_job.completed_at,
         production_candidate_promoted_at=now(),
         updated_at=now()
   WHERE platform='android';
  PERFORM public.admin_log_action('promote','single_app_candidate',p_candidate_id::text,
    jsonb_build_object('production_build_id',v_new_id,'sha',v_job.commit_sha,
      'version_name',v_job.version_name,'build_number',v_job.build_number,
      'apk_sha256',v_job.apk_sha256,'aab_sha256',v_job.aab_sha256));
  RETURN public.admin_single_app_release_status();
END; $body$;

-- The reservation is guarded by both the unchanged Production baseline and
-- the ready, signed 142 Internal candidate. This does not promote a release.
DO $$
DECLARE
  v_store_build integer;
  v_next_build integer;
BEGIN
  SELECT production_store_build_number, next_production_build_number
    INTO v_store_build, v_next_build
    FROM public.app_release_gate
    WHERE platform = 'android'
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Android release gate is missing';
  END IF;

  IF v_store_build IS DISTINCT FROM 141 THEN
    RAISE EXCEPTION 'Expected verified Production baseline 141, found %', v_store_build;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.build_jobs
    WHERE platform = 'android'
      AND artifact_type = 'single-app-candidate-apk+aab'
      AND version_name = '1.6.3'
      AND build_number = 142
      AND status = 'ready'
  ) THEN
    RAISE EXCEPTION 'Cannot reserve build 143: signed internal candidate 142 is not ready';
  END IF;

  IF v_next_build = 142 THEN
    UPDATE public.app_release_gate
       SET next_production_build_number = 143,
           updated_at = now()
     WHERE platform = 'android'
       AND production_store_build_number = 141
       AND next_production_build_number = 142;
  ELSIF v_next_build IS DISTINCT FROM 143 THEN
    RAISE EXCEPTION 'Expected next build 142 or already-reserved 143, found %', v_next_build;
  END IF;
END
$$;