-- 2026-10-08: one Express Android package; certify the signed Production candidate.
-- Additive and reversible: existing Preview gate/history are untouched.
-- All new RPCs require admin. Preview data isolation is unchanged.
CREATE TABLE IF NOT EXISTS public.android_single_app_candidates (
  candidate_build_id uuid PRIMARY KEY REFERENCES public.build_jobs(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  qa_verified_by uuid,
  qa_verified_at timestamptz,
  qa_notes text,
  qa_source_sha text,
  qa_tree_sha text,
  qa_apk_sha256 text,
  qa_aab_sha256 text,
  qa_manifest_sha256 text,
  approved_by uuid,
  approved_at timestamptz,
  promoted_build_id uuid UNIQUE REFERENCES public.build_jobs(id) ON DELETE RESTRICT,
  promoted_at timestamptz
);
ALTER TABLE public.android_single_app_candidates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.android_single_app_candidates FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.android_single_app_candidates IS
  'One-app signed Android production candidates and manual QA approval; never a separate Preview APK.';

-- Prevent a bad production build number regardless of candidate mechanism.
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
  v_expected := v_gate.production_store_build_number + 1;
  IF v_gate.next_production_build_number IS DISTINCT FROM v_expected OR
     NEW.build_number IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'Build Producción bloqueado: el siguiente versionCode es %', v_expected;
  END IF;
  -- Historical legacy candidates keep their strict Preview SHA gate.
  IF NEW.artifact_type='candidate-apk+aab'
     AND (v_gate.preview_commit_sha IS NULL
      OR NEW.commit_sha IS DISTINCT FROM v_gate.preview_commit_sha
      OR NEW.version_name IS DISTINCT FROM v_gate.preview_version_name) THEN
    RAISE EXCEPTION 'Candidato heredado bloqueado: versión/SHA no coincide con Preview';
  END IF;
  -- Single-app candidate never depends on a separately built Preview binary.
  IF NEW.artifact_type='single-app-candidate-apk+aab'
     AND NEW.commit_sha IS NOT NULL
     AND NEW.commit_sha !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'SHA Android unificado inválido';
  END IF;
  RETURN NEW;
END; $body$;

-- Keep the old Preview route intact; also allow promotion of an approved,
-- SHA- and hash-locked signed *same* Production candidate.
CREATE OR REPLACE FUNCTION public.enforce_android_production_build_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $body$
DECLARE v_gate public.app_release_gate%rowtype;
BEGIN
  IF NEW.platform <> 'android' OR NEW.artifact_type <> 'apk+aab' THEN RETURN NEW; END IF;
  IF NEW.signing_mode='production' AND EXISTS (
    SELECT 1 FROM public.android_single_app_candidates v
    JOIN public.build_jobs c ON c.id=v.candidate_build_id
    WHERE c.platform='android'
      AND c.artifact_type='single-app-candidate-apk+aab'
      AND c.status='ready' AND c.signing_mode='production'
      AND v.qa_verified_at IS NOT NULL AND v.approved_at IS NOT NULL
      AND v.promoted_build_id IS NULL
      AND c.commit_sha=NEW.commit_sha
      AND c.version_name=NEW.version_name
      AND c.build_number=NEW.build_number
      AND c.apk_url=NEW.apk_url AND c.aab_url=NEW.aab_url
      AND c.apk_sha256=NEW.apk_sha256 AND c.aab_sha256=NEW.aab_sha256
      AND c.source_tree_sha=NEW.source_tree_sha
      AND c.identity_manifest_sha256=NEW.identity_manifest_sha256
      AND v.qa_source_sha=c.commit_sha
      AND v.qa_tree_sha=c.source_tree_sha
      AND v.qa_apk_sha256=c.apk_sha256
      AND v.qa_aab_sha256=c.aab_sha256
      AND v.qa_manifest_sha256=c.identity_manifest_sha256
  ) THEN RETURN NEW; END IF;
  SELECT * INTO v_gate FROM public.app_release_gate WHERE platform='android';
  IF NOT FOUND OR v_gate.qa_preview_build_id IS NULL
     OR v_gate.qa_preview_build_id IS DISTINCT FROM v_gate.preview_build_id
     OR v_gate.qa_commit_sha IS DISTINCT FROM v_gate.preview_commit_sha
     OR v_gate.qa_passed_at IS NULL THEN
    RAISE EXCEPTION 'Producción bloqueada: falta QA de candidato unificado o Preview heredada';
  END IF;
  IF v_gate.approved_preview_build_id IS DISTINCT FROM v_gate.preview_build_id
     OR v_gate.approved_commit_sha IS DISTINCT FROM v_gate.preview_commit_sha
     OR v_gate.approved_commit_sha IS NULL THEN
    RAISE EXCEPTION 'Producción bloqueada: la Preview heredada no está aprobada';
  END IF;
  IF v_gate.production_candidate_build_id IS NULL
     OR v_gate.production_candidate_commit_sha IS DISTINCT FROM v_gate.preview_commit_sha
     OR v_gate.production_candidate_version_name IS DISTINCT FROM v_gate.preview_version_name
     OR v_gate.production_candidate_build_number IS NULL THEN
    RAISE EXCEPTION 'Producción bloqueada: no existe candidato APK+AAB del mismo SHA';
  END IF;
  IF NEW.version_name IS DISTINCT FROM v_gate.production_candidate_version_name
     OR NEW.build_number IS DISTINCT FROM v_gate.production_candidate_build_number
     OR NEW.commit_sha IS DISTINCT FROM v_gate.approved_commit_sha THEN
    RAISE EXCEPTION 'Producción bloqueada: el candidato no coincide con el SHA aprobado';
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
      OR v_gate.next_production_build_number IS DISTINCT FROM v_gate.production_store_build_number + 1 THEN
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

CREATE OR REPLACE FUNCTION public.admin_single_app_release_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $body$
DECLARE v_gate public.app_release_gate%rowtype;
        v_job public.build_jobs%rowtype;
        v_cert public.android_single_app_candidates%rowtype;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_gate FROM public.app_release_gate WHERE platform='android';
  SELECT * INTO v_job FROM public.build_jobs
   WHERE platform='android' AND artifact_type='single-app-candidate-apk+aab'
   ORDER BY created_at DESC LIMIT 1;
  IF FOUND THEN SELECT * INTO v_cert FROM public.android_single_app_candidates
    WHERE candidate_build_id=v_job.id; END IF;
  RETURN jsonb_build_object(
    'release_mode','single_app','preview_apk_required',false,
    'next_google_play_build',v_gate.next_production_build_number,
    'production_store_build',v_gate.production_store_build_number,
    'candidate',CASE WHEN v_job.id IS NULL THEN NULL ELSE to_jsonb(v_job) END,
    'verification',CASE WHEN v_cert.candidate_build_id IS NULL THEN NULL ELSE to_jsonb(v_cert) END,
    'qa_certified',v_cert.qa_verified_at IS NOT NULL,
    'approved',v_cert.approved_at IS NOT NULL,
    'promoted',v_cert.promoted_build_id IS NOT NULL
  );
END; $body$;

CREATE OR REPLACE FUNCTION public.admin_certify_single_app_candidate(
  p_candidate_id uuid, p_qa_notes text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $body$
DECLARE v_job public.build_jobs%rowtype;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'No autorizado'; END IF;
  IF length(trim(coalesce(p_qa_notes,''))) < 30 THEN
    RAISE EXCEPTION 'Indica qué verificaste en Android: al menos 30 caracteres';
  END IF;
  SELECT * INTO v_job FROM public.build_jobs WHERE id=p_candidate_id FOR UPDATE;
  IF v_job.id IS NULL OR v_job.artifact_type <> 'single-app-candidate-apk+aab'
     OR v_job.platform<>'android' OR v_job.status<>'ready'
     OR v_job.signing_mode<>'production'
     OR v_job.apk_url IS NULL OR v_job.aab_url IS NULL
     OR v_job.commit_sha !~ '^[0-9a-f]{40}$'
     OR v_job.apk_sha256 !~ '^[0-9a-f]{64}$'
     OR v_job.aab_sha256 !~ '^[0-9a-f]{64}$'
     OR v_job.source_tree_sha !~ '^[0-9a-f]{40}$'
     OR v_job.identity_manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Candidato unificado incompleto, sin hashes, o sin firma de Producción';
  END IF;
  IF EXISTS(SELECT 1 FROM public.build_jobs j
     WHERE j.artifact_type='single-app-candidate-apk+aab'
       AND j.created_at>v_job.created_at) THEN
    RAISE EXCEPTION 'Existe un candidato más nuevo; no certifiques uno obsoleto';
  END IF;
  UPDATE public.android_single_app_candidates SET
    qa_verified_by=auth.uid(),qa_verified_at=now(),qa_notes=trim(p_qa_notes),
    qa_source_sha=v_job.commit_sha,qa_tree_sha=v_job.source_tree_sha,
    qa_apk_sha256=v_job.apk_sha256,qa_aab_sha256=v_job.aab_sha256,
    qa_manifest_sha256=v_job.identity_manifest_sha256,
    approved_by=NULL,approved_at=NULL
  WHERE candidate_build_id=p_candidate_id AND promoted_build_id IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Candidato no disponible para certificar'; END IF;
  PERFORM public.admin_log_action('qa_certify','single_app_candidate',p_candidate_id::text,
    jsonb_build_object('sha',v_job.commit_sha,'version',v_job.version_name,
      'build',v_job.build_number,'qa_notes',trim(p_qa_notes)));
  RETURN public.admin_single_app_release_status();
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
     OR v_job.build_number IS DISTINCT FROM v_gate.production_store_build_number+1 THEN
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
     OR v_job.build_number IS DISTINCT FROM v_gate.production_store_build_number+1 THEN
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

-- Revocation is essential for SECURITY DEFINER RPCs; authenticated admins
-- are checked again inside every function.
REVOKE ALL ON FUNCTION public.admin_queue_single_app_candidate(text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.admin_single_app_release_status() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.admin_certify_single_app_candidate(uuid,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.admin_approve_single_app_candidate(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.admin_promote_single_app_candidate(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_queue_single_app_candidate(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_single_app_release_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_certify_single_app_candidate(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_approve_single_app_candidate(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_promote_single_app_candidate(uuid) TO authenticated;
