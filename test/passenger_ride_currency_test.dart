import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/passenger_ride_currency.dart';

void main() {
  final boliviaCached = <String, dynamic>{
    'name': 'Trinidad',
    'country_code': 'BO',
    'currency_code': 'BOB',
  };
  final iquique = <String, dynamic>{
    'name': 'Iquique',
    'country_code': 'CL',
    'currency_code': 'CLP',
  };

  test('first Iquique quote wins over stale Bolivia landing', () {
    expect(
      passengerRideCurrency(
        fareQuote: const {
          'currency': 'CLP',
          'amount': 1500,
          'zone_key': 'iquique',
        },
        activeZone: boliviaCached,
        routeConfirmed: true,
      ),
      'CLP',
    );
  });

  test('Trinidad quote wins over stale Chile landing', () {
    expect(
      passengerRideCurrency(
        fareQuote: const {'currency': 'BOB', 'amount': 5},
        activeZone: iquique,
        routeConfirmed: true,
      ),
      'BOB',
    );
  });

  test('initial map uses coordinate zone while quote not yet available', () {
    expect(
      passengerRideCurrency(
        fareQuote: const {},
        activeZone: iquique,
        routeConfirmed: false,
      ),
      'CLP',
    );
  });

  test('unknown country must not silently default to Bolivia', () {
    expect(
      passengerRideCurrency(
        fareQuote: const {},
        activeZone: null,
        routeConfirmed: true,
      ),
      isEmpty,
    );
  });

  test('rejects invalid quote and falls back to authoritative zone', () {
    expect(
      passengerRideCurrency(
        fareQuote: const {'currency': '---'},
        activeZone: iquique,
        routeConfirmed: true,
      ),
      'CLP',
    );
  });
}
