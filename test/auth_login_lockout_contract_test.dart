import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login no longer blocks an account using a caller supplied email', () {
    final auth = File('lib/auth_entry.dart').readAsStringSync();
    final migration = File(
      'supabase/migrations/20261024120000_disable_unsafe_anonymous_login_lockout.sql',
    ).readAsStringSync();

    expect(auth, contains('signInWithPassword('));
    expect(auth, isNot(contains("'auth_login_guard_state'")));
    expect(auth, isNot(contains("'auth_login_guard_record_failure'")));
    expect(auth, isNot(contains('accountLocked')));

    expect(migration, contains('security invoker'));
    expect(migration, contains("'locked', false"));
    expect(
      migration,
      contains(
        'revoke all on function public.auth_login_guard_record_failure(text)',
      ),
    );
  });
}
