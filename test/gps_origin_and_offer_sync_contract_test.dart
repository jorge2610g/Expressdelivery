import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato de dos reparaciones:
/// 1. El origen «Mi ubicación actual» sigue al GPS fresco. La caché de inicio
///    puede ser de otro lugar y no debe fijar el origen para siempre.
/// 2. Las sincronizaciones de la tarjeta flotante van en serie; close() es el
///    único que invalida una presentación nativa en curso.
void main() {
  final home = File('lib/video_style_home.dart').readAsStringSync();
  final controller = File('lib/driver_floating_offers.dart').readAsStringSync();

  test('GPS origin is tracked and replaced by the fresh fix', () {
    expect(home, contains('bool _pickupFromGps = false;'));
    expect(
      home,
      contains('resetPickupToGps || pickup == null || _pickupFromGps'),
    );
    expect(home, contains('final pickupMoved = shouldResetPickup &&'));
    expect(home, contains('if ((resetPickupToGps || pickupMoved) && destination != null)'));
  });

  test('a manually chosen origin is never overwritten by GPS', () {
    final pickPickup = home.indexOf('Future<void> _pickPickup()');
    expect(pickPickup, greaterThan(-1));
    final body = home.substring(pickPickup, home.indexOf('Future<void> _pickDestination()'));
    expect(body, contains('_pickupFromGps = false;'));
  });

  test('offer syncs are serialized and only close() bumps the epoch', () {
    expect(controller, contains('Future<void> _queue = Future<void>.value();'));
    expect(controller, contains('final run = _queue.then((_) => _syncOnce('));
    expect(controller, contains('_queue = run.catchError((Object _) {});'));
    expect(controller, isNot(contains('++_revision')));
    final closeBody = controller.substring(controller.indexOf('Future<void> close() async {'));
    expect(closeBody, contains('++_closeEpoch;'));
  });

  test('a superseded native show can no longer hide a card confirmed by another sync', () {
    expect(controller, isNot(contains('Lifecycle change superseded')));
    expect(controller, contains('// close() ran while the native show was in flight.'));
  });
}
