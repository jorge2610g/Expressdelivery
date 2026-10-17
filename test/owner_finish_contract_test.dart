import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contratos de las correcciones finales de la PR #262 (ítems 2, 3 y 11).
/// El comportamiento en pantalla se valida en emulador/teléfono.
void main() {
  late String home;

  setUpAll(() {
    home = File('lib/video_style_home.dart').readAsStringSync();
  });

  test('search expiry is watched every second, not only on refresh', () {
    expect(home, contains('Timer? searchRenewalWatch;'));
    expect(home, contains('searchRenewalWatch = Timer.periodic(const Duration(seconds: 1)'));
    expect(home, contains('if (data != null) _maybePromptSearchRenewal(data);'));
    expect(home, contains('searchRenewalWatch?.cancel();'));
  });

  test('the three search-expired options exist and cancel before dropping', () {
    expect(home, contains("title: '¿Seguimos buscando?'"));
    expect(home, contains("Navigator.pop(context, 'cancel');"));
    expect(home, contains('widget.service.renewRideRequest(id);'));
  });

  test('driver cannot accept an expired offer and the offer is removed', () {
    final start = home.indexOf('  Future<void> _acceptRideAtPassengerFare(');
    expect(start, isNonNegative);
    final guard = home.substring(start, start + 700);
    expect(guard, contains("isRideOfferExpiredAt(ride['expires_at'], DateTime.now().toUtc())"));
    expect(guard, contains('_dropUnavailableRide('));
    expect(guard, contains('return;'));
  });

  test('accept failure removes the unavailable offer from the driver view', () {
    expect(home, contains('void _dropUnavailableRide(String rideId) {'));
    expect(home, contains('if (isRideOfferUnavailableError(e)) {'));
  });
}
