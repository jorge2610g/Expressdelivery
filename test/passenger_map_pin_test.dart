import 'dart:io';

import 'package:expressdelivery/passenger_map_pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('movimiento del mapa', () {
    const start = LatLng(-14.8333, -64.9000);

    test('un roce o un zoom sin mover no fija el destino', () {
      expect(pinMovedEnough(start, start), isFalse);
      expect(pinMovedEnough(start, const LatLng(-14.83332, -64.90001)), isFalse);
    });

    test('mover el mapa unos 100 m sí cuenta como elegir', () {
      expect(pinMovedEnough(start, const LatLng(-14.8343, -64.9000)), isTrue);
    });

    test('sin punto de partida del gesto no se fija nada', () {
      expect(pinMovedEnough(null, start), isFalse);
    });
  });

  group('origen y destino', () {
    const pin = LatLng(-14.8333, -64.9000);

    test('un destino a menos de 25 m del origen se rechaza', () {
      expect(
        pinTooCloseToPickup(
          pin,
          pickupLatitude: -14.83331,
          pickupLongitude: -64.90001,
        ),
        isTrue,
      );
    });

    test('un destino lejano se acepta', () {
      expect(
        pinTooCloseToPickup(
          pin,
          pickupLatitude: -14.8433,
          pickupLongitude: -64.9000,
        ),
        isFalse,
      );
    });

    test('sin origen todavía no hay conflicto', () {
      expect(
        pinTooCloseToPickup(
          pin,
          pickupLatitude: null,
          pickupLongitude: null,
        ),
        isFalse,
      );
    });
  });

  test('espera 700 ms a que el mapa se quede quieto', () {
    expect(kPinSettleDelay, const Duration(milliseconds: 700));
  });

  testWidgets('el marcador se levanta mientras se mueve el mapa', (
    tester,
  ) async {
    Future<double> pinTop({required bool moving}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: PassengerMapPin(moving: moving))),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getTopLeft(find.byIcon(Icons.location_on_rounded)).dy;
    }

    final still = await pinTop(moving: false);
    final lifted = await pinTop(moving: true);
    expect(lifted, lessThan(still));
  });

  testWidgets('el aviso cambia al mover el mapa', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PassengerMapHint(moving: false))),
    );
    expect(find.text('Mueve el mapa para elegir'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PassengerMapHint(moving: true))),
    );
    expect(find.text('Suelta para fijar el destino'), findsOneWidget);
  });

  test('el inicio solo mueve el mapa en Prueba, sin servicio y sin calificación', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains("import 'passenger_map_pin.dart';"));
    final start = home.indexOf('final mapPick =');
    expect(start, greaterThan(0));
    final block = home.substring(start, start + 420);
    expect(block, contains('ExpressRuntimeChannel.previewMode'));
    expect(block, contains('!rawPassengerFlowActive'));
    expect(block, contains('data.pendingRating == null'));
    // Fuera de ese caso el mapa sigue sin moverse, como antes.
    expect(home, contains(': InteractiveFlag.none,'));
    expect(home, contains('_onPassengerMapMoved(camera, hasGesture);'));
  });

  test('al soltar se reutilizan las reglas del selector y se abre la ruta', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    final start = home.indexOf('Future<void> _commitPinDestination()');
    expect(start, greaterThan(0));
    final body = home.substring(start, start + 3200);
    expect(body, contains('pinMovedEnough('));
    expect(body, contains('pinTooCloseToPickup('));
    expect(body, contains('reverseGeocodeLocationLabelCached'));
    expect(body, contains('destination = PickedLocation('));
    expect(body, contains('routeConfirmed = false;'));
    expect(body, contains('await _fitRoute();'));
  });

  testWidgets('al tocar «¿A dónde vas?» el marcador da un salto y vuelve', (
    tester,
  ) async {
    Widget app(int nudge) => MaterialApp(
      home: Scaffold(
        body: Center(child: PassengerMapPin(moving: false, nudge: nudge)),
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    final rest = tester.getTopLeft(find.byIcon(Icons.location_on_rounded)).dy;

    await tester.pumpWidget(app(1));
    await tester.pump(const Duration(milliseconds: 70));
    final jumping = tester
        .getTopLeft(find.byIcon(Icons.location_on_rounded))
        .dy;
    expect(jumping, lessThan(rest), reason: 'sube durante el salto');

    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.byIcon(Icons.location_on_rounded)).dy;
    expect(after, rest, reason: 'vuelve a su sitio');
  });

  test('«¿A dónde vas?» en Prueba se queda en el mapa y no abre el selector', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains('pickOnMap: mapPickEnabled,'));
    expect(home, contains('onFocusMap: _focusMapPin,'));
    expect(
      home,
      contains('onTap: pickOnMap && onFocusMap != null'),
      reason: 'el campo avisa en vez de navegar',
    );
    // Escribir una dirección sigue abriendo el selector.
    expect(home, contains('onWriteAddress: pickOnMap ? onDestination : null,'));
    // Fuera de Prueba el campo abre el selector como siempre.
    expect(home, contains(': onDestination,'));
  });
}
