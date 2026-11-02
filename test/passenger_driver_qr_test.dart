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
  test('el bloque de QR en curso aparece solo mientras el cobro está pedido',
      () {
    Map<String, dynamic> trip(String status, {Object? at}) => {
          'status': status,
          'payment_requested_at': at,
          'ride_requests': {'payment_method': 'driver_qr'},
        };
    const requested = '2026-11-02T01:00:00Z';

    expect(passengerShouldLoadDriverQr(trip('in_progress', at: requested)),
        isTrue);
    expect(passengerShouldLoadDriverQr(trip('in_progress')), isFalse);
    expect(passengerShouldLoadDriverQr(trip('completed', at: requested)),
        isFalse);
  });

  testWidgets('el bloque en curso muestra el QR cuando hay imagen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PassengerDriverPaymentQr(
          tripId: 'trip-1',
          load: (_) async => _png,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('QR de pago del conductor'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
