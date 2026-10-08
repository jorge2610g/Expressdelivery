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

  test('Iquique first frame is unpriced until server quote arrives', () {
    expect(passengerRideFareIsReady(const {}), isFalse);
    expect(passengerRideFareIsReady(const {
      'currency': 'CLP',
      'amount': 5,
    }), isTrue); // Server confirmed, not an app-local default.
    expect(passengerRideFareIsReady(const {
      'currency': 'CLP',
      'minimum_allowed_fare': 1500,
    }), isTrue);
  });

  test('quotes without currency or positive amount never enable Confirm', () {
    expect(passengerRideFareIsReady(const {'amount': 1500}), isFalse);
    expect(passengerRideFareIsReady(const {'currency': 'CLP'}), isFalse);
    expect(passengerRideFareIsReady(const {
      'currency': 'BOB',
      'recommended_fare': -5,
    }), isFalse);
    expect(passengerRideFareIsReady(const {
      'currency': 'CLP',
      'amount': 'NaN',
    }), isFalse);
    expect(passengerRideFareIsReady(const {
      'currency': 'CLP',
      'amount': 0,
    }), isFalse);
  });

  test('valid CLP and BOB server fares both become confirmable', () {
    expect(passengerRideFareIsReady(const {
      'currency': 'CLP',
      'minimum_allowed_fare': 1500,
      'amount': 1500,
    }), isTrue);
    expect(passengerRideFareIsReady(const {
      'currency': 'BOB',
      'minimum_allowed_fare': 5,
      'amount': 5,
    }), isTrue);
  });

}
