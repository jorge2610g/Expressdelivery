import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contratos de los dos caminos de invalidación. No reemplazan QA Android
/// con FCM/Realtime real ni prueban latencia de red.
void main() {
  late String home;
  late String receiver;

  setUpAll(() {
    home = File('lib/video_style_home.dart').readAsStringSync();
    receiver = File(
      'android_overlay/kotlin/com/express/usuario1/ExpressMessagingService.kt',
    ).readAsStringSync();
  });

  test('Realtime cancels the open popup before the next full refresh', () {
    expect(home, contains('final invalidated = changedId != null'));
    expect(home, contains('if (isOpen) _closeDriverRequestPopup(showNext: false);'));
    expect(home, contains('_dropUnavailableRide(changedId);'));
    expect(home, contains('_floatingOffers.invalidateOffer(changedId)'));
    expect(home, contains('final removed = payload.newRecord.isEmpty'));
  });

  test('open popup polls only while foreground, preserving offline state', () {
    expect(home, contains('Future<void> _checkDriverPopupValidity() async'));
    expect(home, contains('!_appInForeground || id == null'));
    expect(home, contains('_driverPopupValidityCheckInFlight'));
    expect(home, contains('unawaited(_checkDriverPopupValidity())'));
    expect(home, contains('driverRequestPopupId != id'));
    expect(home, contains('if (!available) {'));
    expect(home, contains('driver_popup_check_failed'));
  });

  test('popup countdown never outruns the server deadline', () {
    expect(home, contains('final serverDeadline = DateTime.tryParse('));
    expect(home, contains('serverDeadline.isBefore(visualDeadline)'));
    expect(home, contains('serverDeadline : visualDeadline'));
    expect(home, contains('!serverDeadline.isAfter(DateTime.now().toUtc())'));
  });

  test('native cancellation events accept the deployed event names', () {
    expect(receiver, contains('eventType == "ride_cancelled"'));
    expect(receiver, contains('eventType == "ride_assigned"'));
    expect(receiver, contains('eventType == "ride_request_expired"'));
    expect(receiver, contains('FloatingOfferService.hideActiveIfOfferId(invalidId)'));
    expect(receiver, contains('manager?.cancel(OFFER_TAG_PREFIX + invalidId, 0)'));
  });

  test('invalid accept/offer responses do not leak PostgreSQL errors', () {
    expect(home, contains('friendlyRideOfferError(e)'));
    expect(home, contains('if (isRideOfferUnavailableError(e))'));
    expect(home, isNot(contains("'No se pudo ofertar: ' + e.toString()")));
    expect(home, isNot(contains("'No se pudo enviar la oferta: ' + e.toString()")));
  });
}
