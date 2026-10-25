-- A candidate's versionCode may now be ahead of the Production baseline
-- because Play Internal consumed it. Allow that exact certified candidate to
-- be promoted without requiring production_store_build_number + 1.
CREATE OR REPLACE FUNCTION public.enforce_android_store_build_sequence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_gate public.app_release_gate%rowtype;
  v_expected integer;
  v_is_approved_internal_promotion boolean := false;
BEGIN
  IF NEW.platform <> 'android'
     OR NEW.artifact_type NOT IN ('candidate-apk+aab', 'single-app-candidate-apk+aab', 'apk+aab')
     OR NEW.status NOT IN ('queued', 'building', 'ready') THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_gate FROM public.app_release_gate WHERE platform = 'android';
  IF NOT FOUND OR v_gate.production_store_build_number IS NULL THEN
    RAISE EXCEPTION 'Build Producción bloqueado: falta baseline Google Play';
  END IF;

  IF NEW.artifact_type = 'single-app-candidate-apk+aab' THEN
    v_expected := v_gate.next_production_build_number;
    IF v_expected IS NULL OR v_expected < v_gate.production_store_build_number + 1 THEN
      RAISE EXCEPTION 'Build Producción bloqueado: reserva inferior al siguiente versionCode permitido';
    END IF;
  ELSIF NEW.artifact_type = 'apk+aab' THEN
    SELECT EXISTS (
      SELECT 1
        FROM public.android_single_app_candidates v
        JOIN public.build_jobs c ON c.id = v.candidate_build_id
       WHERE c.platform = 'android'
         AND c.artifact_type = 'single-app-candidate-apk+aab'
         AND c.status = 'ready'
         AND c.signing_mode = 'production'
         AND v.qa_verified_at IS NOT NULL
         AND v.approved_at IS NOT NULL
         AND v.promoted_build_id IS NULL
         AND c.version_name = NEW.version_name
         AND c.build_number = NEW.build_number
         AND c.commit_sha = NEW.commit_sha
         AND c.apk_url = NEW.apk_url
         AND c.aab_url = NEW.aab_url
         AND c.apk_sha256 = NEW.apk_sha256
         AND c.aab_sha256 = NEW.aab_sha256
         AND c.source_tree_sha = NEW.source_tree_sha
         AND c.identity_manifest_sha256 = NEW.identity_manifest_sha256
    ) INTO v_is_approved_internal_promotion;

    IF v_is_approved_internal_promotion THEN
      v_expected := NEW.build_number;
      IF v_gate.next_production_build_number IS NULL
         OR v_gate.next_production_build_number <= NEW.build_number THEN
        RAISE EXCEPTION 'Promoción bloqueada: el código reservado no avanzó tras la carga a Internal';
      END IF;
    ELSE
      v_expected := v_gate.production_store_build_number + 1;
      IF v_gate.next_production_build_number IS DISTINCT FROM v_expected THEN
        RAISE EXCEPTION 'Build Producción bloqueado: contador inconsistente; esperado %, recibido %',
          v_expected, v_gate.next_production_build_number;
      END IF;
    END IF;
  ELSE
    v_expected := v_gate.production_store_build_number + 1;
    IF v_gate.next_production_build_number IS DISTINCT FROM v_expected THEN
      RAISE EXCEPTION 'Build Producción bloqueado: contador inconsistente; esperado %, recibido %',
        v_expected, v_gate.next_production_build_number;
    END IF;
  END IF;

  IF NEW.build_number IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'Build Producción bloqueado: siguiente versionCode reservado es %', v_expected;
  END IF;

  IF NEW.artifact_type = 'candidate-apk+aab'
     AND (v_gate.preview_commit_sha IS NULL
       OR NEW.commit_sha IS DISTINCT FROM v_gate.preview_commit_sha
       OR NEW.version_name IS DISTINCT FROM v_gate.preview_version_name) THEN
    RAISE EXCEPTION 'Candidato heredado bloqueado: versión/SHA no coincide con Preview';
  END IF;

  IF NEW.artifact_type IN ('single-app-candidate-apk+aab', 'apk+aab')
     AND NEW.commit_sha IS NOT NULL
     AND NEW.commit_sha !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'SHA Android unificado inválido';
  END IF;
  RETURN NEW;
END;
$function$;
