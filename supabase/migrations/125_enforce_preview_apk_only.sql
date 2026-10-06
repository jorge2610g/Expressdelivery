-- Enforce Android artifact rule:
-- Preview = APK only. Production = APK + AAB.

create or replace function public.normalize_android_build_artifact_type()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  if new.platform = 'android'
     and new.artifact_type = 'preview-apk+aab' then
    new.artifact_type := 'preview-apk';
  end if;
  return new;
end;
$function$;

drop trigger if exists normalize_android_build_artifact_type
  on public.build_jobs;

create trigger normalize_android_build_artifact_type
before insert or update of platform, artifact_type
on public.build_jobs
for each row
execute function public.normalize_android_build_artifact_type();

comment on function public.normalize_android_build_artifact_type() is
  'Permanent rule: Android Preview jobs are APK-only; Android production jobs remain APK+AAB.';
