import 'dart:convert';
import 'dart:typed_data';

import 'package:expressdelivery/driver_payment_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PNG 1x1 válido para Image.memory en las pruebas.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  test('el popup de cobro se reclama una sola vez por viaje', () {
    expect(claimPassengerDriverQrPopup('popup-trip-1'), isTrue);
    expect(claimPassengerDriverQrPopup('popup-trip-1'), isFalse);
    expect(claimPassengerDriverQrPopup('popup-trip-2'), isTrue);
  });

  testWidgets('el popup muestra la imagen del QR y se cierra con Listo',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showPassengerDriverPaymentQrPopup(context, _png),
            child: const Text('Cobrar'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Cobrar'));
    await tester.pumpAndSettle();

    expect(find.text('Paga con QR'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();
    expect(find.text('Paga con QR'), findsNothing);
  });
}
