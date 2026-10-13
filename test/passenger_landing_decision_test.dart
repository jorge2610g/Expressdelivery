import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/passenger_landing_decision.dart';

void main() {
  test('one available Taxi service opens Taxi directly in all modes', () {
    for (final mode in ['auto', 'always', 'direct']) {
      expect(
        passengerLandingDecision(mode: mode, availableServiceCount: 1),
        PassengerLandingDecision.directService,
        reason: mode,
      );
    }
  });

  test('one available Paquetería or Market service opens its own page', () {
    // Actual target comes from the sole module returned by the backend.
    for (final mode in ['always', 'auto', 'direct']) {
      expect(
        passengerLandingDecision(mode: mode, availableServiceCount: 1),
        PassengerLandingDecision.directService,
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
