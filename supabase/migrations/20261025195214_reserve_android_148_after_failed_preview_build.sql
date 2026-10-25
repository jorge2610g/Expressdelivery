-- Reserve the next unused Internal versionCode after the prior signed
-- candidate 146 was uploaded and the legacy Preview build 148 failed before
-- producing APK/AAB artifacts. Keep the verified Production baseline at 141.
DO $$
DECLARE
  v_store integer;
  v_next integer;
  v_updated integer;
BEGIN
  SELECT production_store_build_number, next_production_build_number
    INTO v_store, v_next
    FROM public.app_release_gate
   WHERE platform = 'android'
   FOR UPDATE;

  IF NOT FOUND OR v_store IS DISTINCT FROM 141 OR v_next IS DISTINCT FROM 146 THEN
    RAISE EXCEPTION 'Android counter changed; expected Store 141 / next 146, found Store %, next %', v_store, v_next;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.build_jobs
     WHERE platform = 'android'
       AND artifact_type = 'single-app-candidate-apk+aab'
       AND build_number = 146
       AND version_name = '1.6.3'
       AND status = 'ready'
       AND signing_mode = 'production'
       AND commit_sha = '2d578c42df44640c2d3388d472bc7de0b55b81e7'
  ) THEN
    RAISE EXCEPTION 'Verified signed internal candidate 146 is missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.build_jobs
     WHERE platform = 'android'
       AND artifact_type = 'single-app-candidate-apk+aab'
       AND status IN ('queued','building')
  ) THEN
    RAISE EXCEPTION 'Another Android internal candidate is already queued or building';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.build_jobs
     WHERE platform = 'android'
       AND artifact_type = 'single-app-candidate-apk+aab'
       AND build_number = 148
  ) THEN
    RAISE EXCEPTION 'Android candidate build 148 already exists';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.build_jobs
     WHERE platform = 'android'
       AND build_number = 148
       AND artifact_type = 'preview-apk'
       AND status = 'failed'
       AND apk_url IS NULL
       AND aab_url IS NULL
  ) THEN
    RAISE EXCEPTION 'Prior build 148 is not confirmed as a failed artifact-free Preview build';
  END IF;

  UPDATE public.app_release_gate
     SET next_production_build_number = 148,
         updated_at = now()
   WHERE platform = 'android'
     AND production_store_build_number = 141
     AND next_production_build_number = 146;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN
    RAISE EXCEPTION 'Android release counter was not advanced';
  END IF;
END
$$;
