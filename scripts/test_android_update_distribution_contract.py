#!/usr/bin/env python3
"""Read-only regression tests for Admin Express Android update distribution."""
from pathlib import Path

sql = Path(
    'supabase/migrations/20261019150000_android_play_update_distribution.sql'
).read_text()
gate = Path('lib/mobile_update_gate.dart').read_text()

checks = {
    'new RPC requires production admin session': (
        "admin_assert_environment('production')" in sql
        and 'auth.uid() is null or not public.is_admin()' in sql
    ),
    'only verified production version may become an update alert': (
        'v_job.build_number <> v_production_store_build' in sql
        and 'if not v_confirmed_in_play' in sql
        and 'and r.build_number > v_job.build_number' in sql
    ),
    'internal QA releases cannot create app notices': (
        "if p_channel = 'production' then" in sql
        and "if p_channel = 'internal' then" in sql
        and "p_channel='internal'" in sql
    ),
    'existing mobile gate consumes only published Production releases': (
        "supabase.rpc(" in gate and "'latest_app_release'" in gate
        and "if (remote > build) next = map;" in gate
        and 'from public.app_releases' not in gate
    ),
    'critical update needs explicit second confirmation': (
        'v_critical and not v_confirmed_critical' in sql
    ),
    'no active notices seeded during migration': (
        'insert into public.app_releases' in sql
        and 'insert into public.app_update_distributions' in sql
        and 'create table if not exists' in sql
    ),
    'no direct anonymous mutations to distribution table': (
        'enable row level security' in sql
        and 'revoke all on public.app_update_distributions from anon, authenticated, public' in sql
        and 'grant execute on function public.admin_save_android_update_distribution' in sql
    ),
    'Play Store link restricted to original Express package': (
        'https://play.google.com/store/apps/details?id=com.express.usuario1' in sql
        and 'v_url !~' in sql
    ),
}
for label, ok in checks.items():
    if not ok:
        raise AssertionError(label)
    print('OK:', label)
