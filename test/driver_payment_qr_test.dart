import 'dart:convert';
import 'dart:typed_data';

import 'package:expressdelivery/driver_payment_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _uid = '11111111-2222-3333-4444-555555555555';
const String _otherUid = '99999999-2222-3333-4444-555555555555';
const String _pathA = '$_uid/qr/1700000000000.png';
const String _pathB = '$_uid/qr/1700000000999.jpg';

/// PNG 1x1 válido para que Image.memory pueda decodificarlo en las pruebas.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  group('reglas puras del QR', () {
    test('acepta solo PNG, JPG/JPEG y WEBP y normaliza la extensión', () {
      expect(driverPaymentQrExtension('qr.PNG'), 'png');
      expect(driverPaymentQrExtension('qr.jpeg'), 'jpg');
      expect(driverPaymentQrExtension('qr.jpg'), 'jpg');
      expect(driverPaymentQrExtension('qr.webp'), 'webp');
      expect(driverPaymentQrExtension('qr.gif'), isNull);
      expect(driverPaymentQrExtension('qr.pdf'), isNull);
      expect(driverPaymentQrExtension('sinextension'), isNull);
    });

    test('tipo de contenido por extensión', () {
      expect(driverPaymentQrContentType('png'), 'image/png');
      expect(driverPaymentQrContentType('jpg'), 'image/jpeg');
      expect(driverPaymentQrContentType('webp'), 'image/webp');
    });

    test('la ruta debe estar en la carpeta propia y ser una imagen permitida',
        () {
      expect(isOwnDriverPaymentQrPath(_pathA, _uid), isTrue);
      expect(isOwnDriverPaymentQrPath(_pathA, _otherUid), isFalse);
      expect(isOwnDriverPaymentQrPath('$_uid/qr/12.exe', _uid), isFalse);
      expect(isOwnDriverPaymentQrPath('$_uid/profile/1.png', _uid), isFalse);
      expect(isOwnDriverPaymentQrPath('../$_uid/qr/1.png', _uid), isFalse);
    });

    test('el pasajero solo pide el QR en el paso de cobro (completado)', () {
      const requested = '2026-11-02T01:00:00Z';
      Map<String, dynamic> trip(String status, {Object? at, String method = 'driver_qr'}) => {
            'status': status,
            'payment_requested_at': at,
            'ride_requests': {'payment_method': method},
          };
      expect(passengerShouldLoadDriverQr(trip('in_progress', at: requested)), isTrue);
      expect(passengerShouldLoadDriverQr(trip('in_progress')), isFalse);
      expect(passengerShouldLoadDriverQr(trip('completed', at: requested)), isFalse);
      expect(passengerShouldLoadDriverQr(trip('in_progress', at: requested, method: 'cash')), isFalse);
      expect(passengerShouldLoadDriverQr({}), isFalse);
    });
  });

  group('acciones del QR del conductor', () {
    late List<String> calls;
    late List<String?> registered;
    late String? uploadedPath;
    late bool failSetPath;
    late bool failRemove;

    DriverPaymentQrActions build() => DriverPaymentQrActions(
          userId: _uid,
          upload: (bytes, ext, contentType) async {
            calls.add('upload:$ext:$contentType');
            return uploadedPath ?? _pathA;
          },
          setPath: (path) async {
            calls.add('setPath:${path ?? 'null'}');
            if (failSetPath) throw StateError('rpc');
            registered.add(path);
          },
          removeObject: (path) async {
            calls.add('remove:$path');
            if (failRemove) throw StateError('storage');
          },
        );

    setUp(() {
      calls = [];
      registered = [];
      uploadedPath = null;
      failSetPath = false;
      failRemove = false;
    });

    test('subir por primera vez registra la ruta y no borra nada', () async {
      final path = await build().replace(_png, 'png');

      expect(path, _pathA);
      expect(calls, ['upload:png:image/png', 'setPath:$_pathA']);
      expect(registered, [_pathA]);
    });

    test('reemplazar registra el nuevo y después borra el anterior', () async {
      uploadedPath = _pathB;

      final path = await build().replace(
        _png,
        'jpg',
        currentPath: _pathA,
      );

      expect(path, _pathB);
      expect(calls, [
        'upload:jpg:image/jpeg',
        'setPath:$_pathB',
        'remove:$_pathA',
      ]);
    });

    test('si el registro falla, el archivo nuevo se borra y no hay cambio',
        () async {
      failSetPath = true;

      await expectLater(
        build().replace(_png, 'png', currentPath: _pathA),
        throwsA(isA<StateError>()),
      );

      expect(calls, [
        'upload:png:image/png',
        'setPath:$_pathA',
        'remove:$_pathA',
      ]);
      expect(registered, isEmpty);
    });

    test('una ruta devuelta fuera de la carpeta propia se rechaza', () async {
      uploadedPath = '$_otherUid/qr/1.png';

      await expectLater(
        build().replace(_png, 'png'),
        throwsA(isA<StateError>()),
      );
      expect(calls.where((c) => c.startsWith('setPath')), isEmpty);
    });

    test('quitar primero quita la referencia y luego borra el archivo',
        () async {
      await build().remove(_pathA);

      expect(calls, ['setPath:null', 'remove:$_pathA']);
      expect(registered, [null]);
    });

    test('un fallo al borrar el archivo anterior no revierte el cambio',
        () async {
      uploadedPath = _pathB;
      failRemove = true;

      final path = await build().replace(_png, 'jpg', currentPath: _pathA);

      expect(path, _pathB);
      expect(registered, [_pathB]);
    });
  });

  group('vista del conductor', () {
    testWidgets('sin QR muestra subir y no ofrece quitar', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DriverPaymentQrView(
            imageBytes: null,
            busy: false,
            onPick: () {},
            onRemove: () {},
          ),
        ),
      ));

      expect(find.text('Aún no cargaste tu QR de pago.'), findsOneWidget);
      expect(find.text('Subir QR'), findsOneWidget);
      expect(find.text('Quitar QR'), findsNothing);
    });

    testWidgets('con QR permite reemplazar y quitar, y avisa cada acción',
        (tester) async {
      var picked = 0;
      var removed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DriverPaymentQrView(
            imageBytes: _png,
            busy: false,
            onPick: () => picked++,
            onRemove: () => removed++,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Subir QR'), findsNothing);
      await tester.tap(find.text('Reemplazar QR'));
      await tester.tap(find.text('Quitar QR'));
      expect(picked, 1);
      expect(removed, 1);
    });

    testWidgets('ocupado deshabilita las acciones', (tester) async {
      var picked = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DriverPaymentQrView(
            imageBytes: _png,
            busy: true,
            onPick: () => picked++,
            onRemove: () {},
          ),
        ),
      ));

      await tester.tap(find.text('Reemplazar QR'), warnIfMissed: false);
      expect(picked, 0);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });
}
