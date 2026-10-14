import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/passenger_landing_decision.dart';

void main() {
  test('zero visible services never launches an unavailable default', () {
    for (final mode in ['auto', 'always', 'direct']) {
      expect(
        passengerLandingDecision(mode: mode, availableServiceCount: 0),
        PassengerLandingDecision.unavailable,
        reason: mode,
      );
    }
  });

  test('exactly one visible service always opens directly, regardless of type',
      () {
    // Which module is opened comes from the sole zone-context module key.
    for (final mode in ['auto', 'always', 'direct']) {
      expect(
        passengerLandingDecision(mode: mode, availableServiceCount: 1),
        PassengerLandingDecision.directService,
        reason: mode,
      );
    }
  });

  test('two or three visible modules always open the landing selector', () {
    for (final mode in ['auto', 'always', 'direct']) {
      for (final count in [2, 3]) {
        expect(
          passengerLandingDecision(mode: mode, availableServiceCount: count),
          PassengerLandingDecision.selector,
          reason: '$mode with $count modules',
        );
      }
    }
  });
}
