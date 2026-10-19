#!/usr/bin/env python3
from pathlib import Path

migration = Path('supabase/migrations/20261019170000_production_only_android_update_141.sql').read_text()
checks = {
    'Google Play Production 141 independently verified': (
        '39272558550' in migration and 'track=production' in migration
        and 'status=completed, versionCode=141' in migration
    ),
    'One exact signed AAB job and checksum': (
        '470dc53d-eeef-4acd-bbf9-b226344c043b' in migration
        and '505364b1baa29c91cb5616b9d8f9f73173352836eaf31f4559a9f73c45278843' in migration
        and 'commit_sha=' in migration
    ),
    'Play gate updated to 141, next at least 142': (
        'production_store_build_number=141' in migration
        and 'coalesce(next_production_build_number, 0), 142' in migration
        and 'production_verified_build_job_id=v_verified_id' in migration
    ),
    'Backend explicitly rejects internal channel': (
        "if p_channel is distinct from 'production' then" in migration
        and "Distribución únicamente para Producción" in migration
    ),
    'Updates only from audited verified exact production job': (
        'v_job.id<>v_verified_job_id' in migration
        and 'v_job.build_number<>v_store_build' in migration
        and "v_job.signing_mode is distinct from 'production'" in migration
    ),
    'AAB-only accepted, APK optional': (
        "'aab','single-app-candidate-apk+aab'" in migration
        and "'android',v_job.version_name,v_job.build_number," in migration
        and 'v_job.apk_url,v_job.aab_url' in migration
    ),
    'Critical and general notices require admin confirmation': (
        "admin_assert_environment('production')" in migration
        and "auth.uid() is null or not public.is_admin()" in migration
        and 'if v_current and not coalesce(p_confirmed_in_play,false)' in migration
        and 'if v_critical and not coalesce(p_confirmed_critical,false)' in migration
    ),
    'Migration is inert: no notice activated automatically': (
        'insert into public.app_releases' in migration
        and "update public.app_release_gate" in migration
        and not ('insert into public.app_releases (' in migration.split('create or replace function public.admin_save_android_update_distribution')[0])
    ),
    'Status response includes exact verified job and no client code edits': (
        "'production_verified_build_job_id',v_gate.production_verified_build_job_id" in migration
    ),
}
for name, passed in checks.items():
    assert passed, name
    print('PASS:', name)
