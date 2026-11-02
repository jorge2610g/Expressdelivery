import 'dart:async';
import 'dart:typed_data';

import 'package:expressdelivery/driver_payment_qr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _trip(
  String status, {
  Object? requestedAt,
  String method = 'driver_qr',
}) =>
    {
      'id': 'trip-1',
      'status': status,
      'payment_requested_at': requestedAt,
      'ride_requests': {'payment_method': method},
    };

const _requested = '2026-11-02T01:00:00Z';
final Uint8List _bytes = Uint8List.fromList([1, 2, 3]);

class _Fakes {
  int loads = 0;
  int shows = 0;
  int closes = 0;
  bool hasQr = true;
  final Set<String> claimed = {};
  Future<void>? lastShow;

  late final PassengerDriverQrPopupController controller =
      PassengerDriverQrPopupController(
    load: (tripId) async {
      loads++;
      return hasQr ? _bytes : null;
    },
    claim: (tripId) => claimed.add(tripId),
    show: (bytes) {
      shows++;
      final completer = Completer<void>();
      lastShow = completer.future;
      return completer.future;
    },
    close: () => closes++,
  );
}

void main() {
  group('popup del QR en el pasajero', () {
    test('no se abre antes de que el conductor pida el cobro', () async {
      final f = _Fakes();
      await f.controller.onTrip(_trip('in_progress'));
      expect(f.loads, 0);
      expect(f.shows, 0);
      expect(f.controller.isOpen, isFalse);
    });

    test('se abre al pedirse el cobro y no se repite', () async {
      final f = _Fakes();
      await f.controller.onTrip(_trip('in_progress', requestedAt: _requested));
      await f.controller.onTrip(_trip('in_progress', requestedAt: _requested));
      expect(f.shows, 1);
      expect(f.controller.isOpen, isTrue);
    });

    test('sin QR cargado no pasa nada', () async {
      final f = _Fakes()..hasQr = false;
      await f.controller.onTrip(_trip('in_progress', requestedAt: _requested));
      expect(f.loads, 1);
      expect(f.shows, 0);
      expect(f.controller.isOpen, isFalse);
    });

    test('en efectivo no se carga ni se abre', () async {
      final f = _Fakes();
      await f.controller.onTrip(
        _trip('in_progress', requestedAt: _requested, method: 'cash'),
      );
      expect(f.loads, 0);
      expect(f.shows, 0);
    });

    test('se cierra solo cuando el viaje se completa', () async {
      final f = _Fakes();
      await f.controller.onTrip(_trip('in_progress', requestedAt: _requested));
      expect(f.controller.isOpen, isTrue);

      await f.controller.onTrip(_trip('completed', requestedAt: _requested));
      expect(f.closes, 1);
      expect(f.controller.isOpen, isFalse);
    });

    test('completar sin popup abierto no cierra nada', () async {
      final f = _Fakes();
      await f.controller.onTrip(_trip('completed', requestedAt: _requested));
      expect(f.closes, 0);
    });
  });

  group('"Completar viaje" con pago por QR', () {
    test('sin pago por QR no pide cobro y sigue el flujo de hoy', () async {
      var requested = 0;
      final ok = await requestQrChargeBeforeCompletion(
        isDriverQr: false,
        qrPath: () async => 'uid/qr/1.png',
        request: () async => requested++,
        onError: (_) => fail('no debe avisar error'),
      );
      expect(ok, isTrue);
      expect(requested, 0);
    });

    test('sin QR cargado no pide cobro y sigue el flujo de hoy', () async {
      var requested = 0;
      final ok = await requestQrChargeBeforeCompletion(
        isDriverQr: true,
        qrPath: () async => null,
        request: () async => requested++,
        onError: (_) => fail('no debe avisar error'),
      );
      expect(ok, isTrue);
      expect(requested, 0);
    });

    test('con QR cargado pide el cobro antes de confirmar', () async {
      var requested = 0;
      final ok = await requestQrChargeBeforeCompletion(
        isDriverQr: true,
        qrPath: () async => 'uid/qr/1.png',
        request: () async => requested++,
        onError: (_) => fail('no debe avisar error'),
      );
      expect(ok, isTrue);
      expect(requested, 1);
    });

    test('si falla el cobro muestra el error y no abre el diálogo', () async {
      String? message;
      final ok = await requestQrChargeBeforeCompletion(
        isDriverQr: true,
        qrPath: () async => 'uid/qr/1.png',
        request: () async => throw const PostgrestException(
          message: 'Este viaje no se cobra con QR o no tienes un QR de pago cargado.',
        ),
        onError: (m) => message = m,
      );
      expect(ok, isFalse);
      expect(
        message,
        'Este viaje no se cobra con QR o no tienes un QR de pago cargado.',
      );
    });

    test('un error sin mensaje usa un texto genérico', () async {
      String? message;
      final ok = await requestQrChargeBeforeCompletion(
        isDriverQr: true,
        qrPath: () async => 'uid/qr/1.png',
        request: () async => throw StateError('red'),
        onError: (m) => message = m,
      );
      expect(ok, isFalse);
      expect(message, 'No se pudo avisar el cobro al pasajero. Inténtalo de nuevo.');
    });
  });
}
