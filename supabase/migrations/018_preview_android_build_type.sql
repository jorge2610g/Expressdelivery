alter table public.build_jobs
  drop constraint if exists build_jobs_artifact_type_check;

alter table public.build_jobs
  add constraint build_jobs_artifact_type_check
  check (
    artifact_type = any (
      array[
        'apk'::text,
        'aab'::text,
        'apk+aab'::text,
        'preview-apk+aab'::text,
        'ipa'::text,
        'web'::text
      ]
    )
  );
