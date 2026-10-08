import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_focus_navigation.dart';

void main() {
  bool locked({
    bool incomingOffer = false,
    bool waitingPassenger = false,
    bool hasActiveTrip = false,
    bool hasActiveDelivery = false,
    bool processingTransition = false,
  }) =>
      shouldLockDriverNavigation(
        incomingOffer: incomingOffer,
        waitingPassenger: waitingPassenger,
        hasActiveTrip: hasActiveTrip,
        hasActiveDelivery: hasActiveDelivery,
        processingTransition: processingTransition,
      );

  test('normal idle driver shows tabs', () => expect(locked(), isFalse));
  test('incoming offer hides tabs', () =>
      expect(locked(incomingOffer: true), isTrue));
  test('waiting for passenger approval hides tabs', () =>
      expect(locked(waitingPassenger: true), isTrue));
  test('every stage of assigned/in-progress trip hides tabs', () =>
      expect(locked(hasActiveTrip: true), isTrue));
  test('delivery in progress also hides tabs', () =>
      expect(locked(hasActiveDelivery: true), isTrue));
  test('transition while receiving/ending trip hides tabs', () =>
      expect(locked(processingTransition: true), isTrue));
  test('reject or timeout restores navigation with no active trip', () {
    expect(locked(incomingOffer: true), isTrue);
    expect(locked(), isFalse);
  });
  test('passenger accepts after outgoing offer: no gap in focus', () {
    expect(locked(waitingPassenger: true), isTrue);
    expect(locked(hasActiveTrip: true), isTrue);
  });
  test('finished ride restores navigation unless another offer appears', () {
    expect(locked(hasActiveTrip: true), isTrue);
    expect(locked(), isFalse);
    expect(locked(incomingOffer: true), isTrue);
  });
}
