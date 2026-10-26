-- Retire the untouched queued 148 candidate after owner correction.
-- Build 146 is the latest successful Internal upload; the old 147 Preview
-- attempt failed before creating artifacts, so 147 is the next usable code.
DO $$
DECLARE
  v_store integer;
  v_next integer;
  v_count integer;
BEGIN
  SELECT production_store_build_number, next_production_build_number
    INTO v_store, v_next
    FROM public.app_release_gate
   WHERE platform = 'android'
   FOR UPDATE;

  IF NOT FOUND OR v_store IS DISTINCT FROM 141 OR v_next IS DISTINCT FROM 148 THEN
    RAISE EXCEPTION 'Counter changed; expected Production 141 / next 148, found % / %', v_store, v_next;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.build_jobs
     WHERE id = '79d43f2c-b23c-4c07-8a3a-d38886165e27'::uuid
       AND platform = 'android'
       AND artifact_type = 'single-app-candidate-apk+aab'
       AND build_number = 148
       AND status = 'queued'
       AND workflow_run_id IS NULL
       AND commit_sha IS NULL
       AND apk_url IS NULL
       AND aab_url IS NULL
  ) THEN
    RAISE EXCEPTION 'Queued 148 candidate is no longer untouched; refusing to cancel it';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.build_jobs
     WHERE platform='android'
       AND artifact_type='single-app-candidate-apk+aab'
       AND build_number=146
       AND status='ready'
       AND signing_mode='production'
       AND apk_url IS NOT NULL
       AND aab_url IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Successful Internal build 146 was not verified';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.build_jobs
     WHERE platform='android'
       AND artifact_type='single-app-candidate-apk+aab'
       AND build_number=147
       AND status IN ('queued','building','ready')
  ) THEN
    RAISE EXCEPTION 'Build 147 already has an active or ready candidate';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.build_jobs
     WHERE platform='android'
       AND artifact_type='preview-apk+aab'
       AND build_number=147
       AND status='failed'
       AND apk_url IS NULL
       AND aab_url IS NULL
  ) THEN
    RAISE EXCEPTION 'Previous build 147 did not meet artifact-free failure guard';
  END IF;

  UPDATE public.build_jobs
     SET status = 'failed',
         error_message = 'Superseded by owner correction: next versionCode is 147. Build 148 had not started or uploaded artifacts.',
         completed_at = now(),
         updated_at = now()
   WHERE id = '79d43f2c-b23c-4c07-8a3a-d38886165e27'::uuid
     AND status = 'queued';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Could not safely retire queued build 148';
  END IF;

  UPDATE public.app_release_gate
     SET next_production_build_number = 147,
         updated_at = now()
   WHERE platform = 'android'
     AND production_store_build_number = 141
     AND next_production_build_number = 148;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Could not reserve corrected build number 147';
  END IF;
END
$$;
