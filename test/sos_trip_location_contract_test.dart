import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato: el botón SOS del viaje envía la ubicación del GPS igual que la
/// Seguridad de la app. Es una comprobación de fuente; la prueba real del GPS
/// se hace en teléfono.
void main() {
  late String home;
  late String sosFunction;

  setUpAll(() {
    home = File('lib/video_style_home.dart').readAsStringSync();
    final start = home.indexOf('Future<void> raiseExpressTripEmergency(');
    final end = home.indexOf('Future<String?> askExpressCancellationReason(');
    expect(start, isNonNegative, reason: 'falta raiseExpressTripEmergency');
    expect(end, greaterThan(start));
    sosFunction = home.substring(start, end);
  });

  test('SOS del viaje obtiene la posición con el mismo servicio de la app', () {
    expect(home, contains('ExpressLocationService'));
    expect(
      sosFunction,
      contains('const ExpressLocationService().currentPosition()'),
    );
  });

  test('SOS del viaje pasa latitude y longitude a createEmergency', () {
    expect(sosFunction, contains('service.createEmergency('));
    expect(sosFunction, contains('tripId: tripId,'));
    expect(sosFunction, contains('latitude: latitude,'));
    expect(sosFunction, contains('longitude: longitude,'));
  });

  test('la falta de GPS no impide enviar la alerta', () {
    final gpsStart = sosFunction.indexOf('currentPosition()');
    final gpsEnd = sosFunction.indexOf('await service.createEmergency(');
    expect(gpsStart, isNonNegative);
    expect(gpsEnd, greaterThan(gpsStart));
    final gpsBlock = sosFunction.substring(gpsStart, gpsEnd);
    expect(gpsBlock, contains('} catch (_) {'));
  });
}
