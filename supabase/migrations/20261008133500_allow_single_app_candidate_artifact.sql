-- Additive: preserve every existing build artifact type while allowing
-- the signed single-app Production candidate. No rows are modified.
ALTER TABLE public.build_jobs
  DROP CONSTRAINT build_jobs_artifact_type_check;
ALTER TABLE public.build_jobs
  ADD CONSTRAINT build_jobs_artifact_type_check
  CHECK (artifact_type IN (
    'apk','aab','apk+aab','preview-apk','preview-apk+aab',
    'candidate-apk+aab','single-app-candidate-apk+aab','ipa','web'
  ));
