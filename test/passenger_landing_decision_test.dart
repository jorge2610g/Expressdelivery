import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/passenger_landing_decision.dart';

void main() {
  test('Iquique Production always displays landing with Taxi only', () {
    expect(
      passengerLandingDecision(mode: 'always', availableServiceCount: 1),
      PassengerLandingDecision.selector,
    );
  });

  test('always displays one allowed Envíos or Market card too', () {
    // Which service is visible comes only from the zone-context RPC.
    expect(
      passengerLandingDecision(mode: 'always', availableServiceCount: 1),
      PassengerLandingDecision.selector,
    );
  });

  test('auto and direct keep single-service fast path', () {
    for (final mode in ['auto', 'direct']) {
      expect(
        passengerLandingDecision(mode: mode, availableServiceCount: 1),
        PassengerLandingDecision.directService,
        reason: mode,
      );
    }
  });

  test('two or three services use the chooser in auto/always modes', () {
    for (final mode in ['auto', 'always']) {
      for (final count in [2, 3]) {
        expect(
          passengerLandingDecision(mode: mode, availableServiceCount: count),
          PassengerLandingDecision.selector,
        );
      }
    }
  });

  test('direct mode keeps Adminexpress default selection when several exist', () {
    expect(
      passengerLandingDecision(mode: 'direct', availableServiceCount: 3),
      PassengerLandingDecision.directService,
    );
  });

  test('zero services never launch Taxi as an unsafe default', () {
    for (final mode in ['auto', 'always', 'direct']) {
      expect(
        passengerLandingDecision(mode: mode, availableServiceCount: 0),
        PassengerLandingDecision.unavailable,
      );
    }
  });
}
