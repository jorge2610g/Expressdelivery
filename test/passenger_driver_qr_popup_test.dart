import 'dart:convert';
import 'dart:typed_data';

import 'package:expressdelivery/driver_payment_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PNG 1x1 válido para Image.memory en las pruebas.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

Map<String, dynamic> _trip({
  required String status,
  String? paymentRequestedAt,
  String method = 'driver_qr',
}) =>
    {
      'status': status,
      'payment_requested_at': paymentRequestedAt,
      'ride_requests': {'payment_method': method},
    };

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

  group('cuándo aparece el popup y el botón Cobrar', () {
    const requested = '2026-11-01T23:00:00Z';

    test('el popup aparece solo con cobro pedido, en curso y pago con QR', () {
      expect(
        passengerShouldShowDriverQrPopup(
          _trip(status: 'in_progress', paymentRequestedAt: requested),
        ),
        isTrue,
      );
      expect(
        passengerShouldShowDriverQrPopup(
          _trip(status: 'in_progress', paymentRequestedAt: null),
        ),
        isFalse,
      );
      expect(
        passengerShouldShowDriverQrPopup(
          _trip(status: 'completed', paymentRequestedAt: requested),
        ),
        isFalse,
      );
    });

    test('en efectivo el popup nunca aparece', () {
      expect(
        passengerShouldShowDriverQrPopup(
          _trip(status: 'in_progress', paymentRequestedAt: requested, method: 'cash'),
        ),
        isFalse,
      );
    });

    test('en efectivo no se carga el QR en el paso de cobro', () {
      expect(
        passengerShouldLoadDriverQr(_trip(status: 'completed', method: 'cash')),
        isFalse,
      );
      expect(
        passengerShouldLoadDriverQr(_trip(status: 'completed')),
        isTrue,
      );
    });

    test('Cobrar solo en viajes en curso con pago por QR y que no son paquetes',
        () {
      expect(
        driverCanRequestPayment(_trip(status: 'in_progress'), parcel: false),
        isTrue,
      );
      expect(
        driverCanRequestPayment(_trip(status: 'in_progress'), parcel: true),
        isFalse,
      );
      expect(
        driverCanRequestPayment(
          _trip(status: 'in_progress', method: 'cash'),
          parcel: false,
        ),
        isFalse,
      );
      expect(
        driverCanRequestPayment(_trip(status: 'driver_waiting'), parcel: false),
        isFalse,
      );
    });
  });
}
