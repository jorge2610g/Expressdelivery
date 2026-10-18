import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contratos de la regla de ajuste del pasajero (comentario P0 de PR #262).
/// La migración no está aplicada: estas pruebas fijan el texto propuesto y el
/// respaldo de la app. La verificación real se hace en los emuladores.
void main() {
  late String sql;
  late String service;
  late String home;

  setUpAll(() {
    sql = File(
      'docs/pending_migrations/20261018_passenger_search_fare_step_PROPOSAL.sql',
    ).readAsStringSync();
    service = File('lib/services/express_service.dart').readAsStringSync();
    home = File('lib/video_style_home.dart').readAsStringSync();
  });

  String section(String start, String end) {
    final from = sql.indexOf(start);
    final to = sql.indexOf(end, from + start.length);
    expect(from, isNonNegative, reason: 'missing $start');
    expect(to, greaterThan(from), reason: 'missing $end');
    return sql.substring(from, to);
  }

  test('the passenger rule is read-only, owner-only and exposes no tables', () {
    final fn = section(
      'create or replace function public.passenger_search_fare_rule',
      '-- 2) Renovación',
    );
    expect(fn, contains('v_uid uuid := auth.uid();'));
    expect(fn, contains('and passenger_id = v_uid'));
    expect(fn, contains("status in ('searching','offers_received')"));
    expect(
      fn,
      contains('revoke all on function public.passenger_search_fare_rule(uuid) from public;'),
    );
    expect(
      fn,
      contains('grant execute on function public.passenger_search_fare_rule(uuid) to authenticated;'),
    );
    expect(fn, isNot(contains('driver_quick_offer_rules')));
    expect(fn, isNot(contains('fare_rounding_currency_policies')));
  });

  test('renewal validates floor, one step and rounding on the server, never the currency', () {
    final fn = sql.substring(
      sql.indexOf('create or replace function public.renew_ride_request'),
    );
    expect(fn, contains('p_proposed_fare < coalesce(v_row.proposed_fare, 0)'));
    expect(fn, contains('mod(v_diff, v_step) <> 0'));
    expect(
      fn,
      contains('public.fare_round_value(p_proposed_fare, v_increment) <> p_proposed_fare'),
    );
    expect(fn, isNot(contains('p_currency')));
    expect(fn, contains('search_started_at = now(),'));
  });

  test('the step is the smallest effective one, not the rounding increment', () {
    expect(sql, contains('select min(s.value::numeric)'));
    expect(sql, isNot(contains('v_step := v_increment')));
  });

  test('the app asks the server rule and falls back to the local step when it is missing', () {
    expect(service, contains("'passenger_search_fare_rule'"));
    expect(service, contains('return null;'));
    expect(
      home,
      contains(r"final rule = await widget.service.passengerSearchFareRule(rideId);"),
    );
    expect(
      home,
      contains(r"asDouble(rule?['step']) ?? expressSearchFareStep(ruleCurrency)"),
    );
    expect(home, contains('late final num step = widget.step;'));
  });
}
