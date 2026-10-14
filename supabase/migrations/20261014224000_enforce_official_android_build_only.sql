-- Keep exactly one Android package. Accounts use internal preview/production
-- data authorization, never an additional QA APK or artifact family.
-- No legacy build records are deleted; Google Play/single-app release gates
-- and historic SHA/hash evidence remain intact.
create or replace function public.enforce_express_official_android_build()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.platform = 'android'
     and new.artifact_type in ('preview-apk', 'preview-apk+aab') then
    raise exception using
      errcode = '23514',
      message = 'Only official Express Android APK/AAB builds are permitted.';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_express_official_android_build()
  from public, anon, authenticated;

drop trigger if exists enforce_express_official_android_build on public.build_jobs;
create trigger enforce_express_official_android_build
before insert or update of platform, artifact_type
on public.build_jobs
for each row
execute function public.enforce_express_official_android_build();
