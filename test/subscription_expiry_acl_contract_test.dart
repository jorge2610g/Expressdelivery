import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subscription expiry remains scheduled and is not a public RPC', () {
    final migration = File(
      'supabase/migrations/20261024120500_restrict_subscription_payment_expiry.sql',
    ).readAsStringSync();

    expect(migration, contains("where status = 'pending'"));
    expect(migration, contains('and expires_at <= now()'));
    expect(
      migration,
      contains(
        'revoke all on function public.service_expire_pending_driver_subscription_payments()',
      ),
    );
    expect(
      migration,
      contains('from public, anon, authenticated, service_role'),
    );
    expect(
      migration,
      contains(
        'grant execute on function public.service_expire_pending_driver_subscription_payments()\nto service_role',
      ),
    );
  });
}
