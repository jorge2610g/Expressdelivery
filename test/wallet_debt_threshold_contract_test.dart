import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261023221938_enforce_wallet_debt_thresholds.sql',
  ).readAsStringSync();
  final messages = File('lib/cancellation_debt_messages.dart')
      .readAsStringSync();

  test(
    'only debt above the configured cap blocks; the cap itself is allowed',
    () {
      expect(migration, contains('select s.debt_total>s.debt_limit'));
      expect(migration, contains('passenger_limit'));
      expect(migration, contains('driver_limit'));
    },
  );

  test(
    'limits aggregate unpaid cancellation and administrative debt by role',
    () {
      expect(migration, contains('sum(d.remaining_amount)'));
      expect(migration, contains('sum(d.amount)'));
      expect(migration, contains('d.role=p_role'));
    expect(migration, contains('d.zone_id=p_zone_id'));
      expect(migration, contains('d.channel=v_channel'));
      expect(migration, contains('d.remaining_amount>0'));
      expect(migration, contains('d.paid_at is null'));
    },
  );

  test(
    'server gates passenger Taxi and driver online, Taxi and Delivery work',
    () {
      expect(migration, contains('guard_ride_request_cancellation_debt()'));
      expect(migration, contains('guard_driver_cancellation_debt()'));
      expect(migration, contains('guard_driver_online_adjustment_debt()'));
      expect(migration, contains('guard_delivery_admin_adjustment_debt()'));
      expect(migration, contains('force_driver_offline_for_wallet_debt()'));
      expect(migration, contains("coalesce(new.service_mode,'taxi')<>'taxi'"));
    },
  );

  test('mobile debt alert shows the threshold and routes to the wallet', () {
    expect(messages, contains(r'Tope permitido: $limitCurrency $limitAmount'));
    expect(messages, contains('Ir a Pagos y billetera'));
    expect(messages, contains('Deuda de billetera'));
    expect(messages, contains('supera el tope permitido'));
  });
}
