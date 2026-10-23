import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The debt guard must resolve the pickup zone itself because its trigger sorts
/// before the trigger that writes NEW.zone_id.
void main() {
  late String migration;
  late String guard;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20261023170000_fix_passenger_cancellation_debt_guard_zone.sql',
    ).readAsStringSync();
    final start = migration.indexOf(
      'create or replace function public.guard_ride_request_cancellation_debt()',
    );
    final end = migration.indexOf('create trigger ride_requests_guard_cancellation_debt', start);
    guard = migration.substring(start, end);
  });

  test('resolves zone from pickup coordinates before querying outstanding debt', () {
    final zoneLookup = guard.indexOf('v_zone:=coalesce(');
    final debtLookup = guard.indexOf('from public.cancellation_fee_debts d');
    expect(zoneLookup, greaterThanOrEqualTo(0));
    expect(guard, contains('new.zone_id,'));
    expect(guard, contains(
      'public.service_zone_id_for_point(new.pickup_latitude,new.pickup_longitude)',
    ));
    expect(debtLookup, greaterThan(zoneLookup));
    expect(guard, contains('from public.service_zones where id=v_zone'));
  });

  test('keeps debt checks scoped to account, country, runtime channel and unpaid rows', () {
    expect(guard, contains('d.user_id=v_uid'));
    expect(guard, contains('d.country_code=v_country'));
    expect(guard, contains('d.channel=new.channel'));
    expect(guard, contains('d.paid_at is null'));
    expect(guard, contains("coalesce(new.service_mode,'taxi')<>'taxi'"));
  });

  test('fails closed when a pickup zone cannot be resolved for a debtor', () {
    final missingZoneBranch = guard.substring(
      guard.indexOf('else\n    -- A missing/unresolvable zone'),
    );
    expect(missingZoneBranch, contains('select exists('));
    expect(missingZoneBranch, contains('d.user_id=v_uid'));
    expect(missingZoneBranch, contains('d.channel=new.channel'));
    expect(missingZoneBranch, contains('d.paid_at is null'));
    expect(missingZoneBranch, contains('if v_has_debt then'));
  });

  test('database error directs the passenger to the wallet without naming a provider', () {
    expect(guard, contains('Pagos y billetera'));
    expect(guard.toLowerCase(), isNot(contains('veripagos')));
    expect(guard.toLowerCase(), isNot(contains('mercado pago')));
  });

  test('keeps the guard attached before INSERT', () {
    expect(migration, contains(
      'create trigger ride_requests_guard_cancellation_debt\nbefore insert on public.ride_requests',
    ));
    expect(migration, contains(
      'for each row execute function public.guard_ride_request_cancellation_debt()',
    ));
  });
}
