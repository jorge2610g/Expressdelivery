-- The unified 1.6.3+142 candidate was signed and successfully uploaded to
-- Google Play Internal. Keep the Production baseline at 141, but reserve the
-- next candidate as 143 so the same Play versionCode is not reused.
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