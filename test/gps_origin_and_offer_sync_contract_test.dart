import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato de dos reparaciones:
/// 1. El origen «Mi ubicación actual» sigue al GPS fresco. La caché de inicio
///    puede ser de otro lugar y no debe fijar el origen para siempre.
/// 2. Las sincronizaciones de la tarjeta flotante van en serie; close() es el
///    único que invalida una presentación nativa en curso.
void main() {
  final home = File('lib/video_style_home.dart').readAsStringSync();
  final shell = File('lib/connected_experience.dart').readAsStringSync();
  final controller = File('lib/driver_floating_offers.dart').readAsStringSync();

  test('GPS origin is tracked and replaced by the fresh fix', () {
    expect(home, contains('bool _pickupFromGps = false;'));
    expect(
      home,
      contains('resetPickupToGps || pickup == null || _pickupFromGps'),
    );
    expect(home, contains('final pickupMoved = shouldResetPickup &&'));
    expect(
      home,
      contains('if ((resetPickupToGps || pickupMoved) && destination != null)'),
    );
  });

  test('a manually chosen origin is never overwritten by GPS', () {
    final pickPickup = home.indexOf('Future<void> _pickPickup()');
    expect(pickPickup, greaterThan(-1));
    final body = home.substring(
      pickPickup,
      home.indexOf('Future<void> _pickDestination()'),
    );
    expect(body, contains('_pickupFromGps = false;'));
  });

  test('manual landing location is carried into Taxi and Envíos', () {
    expect(shell, contains('bool passengerLandingIsManual = false;'));
    expect(shell, contains('passengerLandingIsManual = true;'));
    expect(shell, contains('initialPickupLatitude: passengerLandingLatitude'));
    expect(
      shell,
      contains('initialPickupLongitude: passengerLandingLongitude'),
    );
    expect(shell, contains('initialPickupIsManual: passengerLandingIsManual'));
    expect(home, contains('this.initialPickupIsManual = false'));
    expect(home, contains('_pickupFromGps = false;'));
  });

  test('GPS updates the live dot but keeps a manual pickup and map camera', () {
    final locate = home.indexOf(
      'Future<void> _locate({bool resetPickupToGps = false})',
    );
    final follow = home.indexOf('void _startPassengerMapFollow()');
    expect(locate, greaterThan(-1));
    expect(follow, greaterThan(-1));
    final locateBody = home.substring(
      locate,
      home.indexOf('Future<void> _pickPickup()', locate),
    );
    final followBody = home.substring(
      follow,
      home.indexOf('Future<void> _locate(', follow),
    );
    expect(
      locateBody,
      contains(
        'final shouldResetPickup =\n          resetPickupToGps || pickup == null || _pickupFromGps;',
      ),
    );
    expect(
      locateBody,
      contains(
        'if (shouldResetPickup) {\n        passengerMapZoom = 14.6;\n        _centerPassengerMap(point, passengerMapZoom);',
      ),
    );
    expect(
      locateBody,
      contains('latitude: servicePoint?.latitude ?? position.latitude'),
    );
    expect(followBody, contains('_pickupFromGps &&'));
  });

  test('offer syncs are serialized and only close() bumps the epoch', () {
    expect(controller, contains('Future<void> _queue = Future<void>.value();'));
    expect(controller, contains('final run = _queue.then((_) => _syncOnce('));
    expect(controller, contains('_queue = run.catchError((Object _) {});'));
    expect(controller, isNot(contains('++_revision')));
    final closeBody = controller.substring(
      controller.indexOf('Future<void> close() async {'),
    );
    expect(closeBody, contains('++_closeEpoch;'));
  });

  test(
    'a superseded native show can no longer hide a card confirmed by another sync',
    () {
      expect(controller, isNot(contains('Lifecycle change superseded')));
      expect(
        controller,
        contains('// close() ran while the native show was in flight.'),
      );
    },
  );
}
