import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/video_style_home.dart').readAsStringSync();

  test('las solicitudes de precio fijo no se listan, solo llegan como ventana', () {
    expect(src, contains("ride['dispatch_style'] != 'sequential'"));
    expect(src, contains('_listableRides(data.rides)'));
    // La ventana automática sigue saliendo de la lista completa del estado.
    expect(src, contains('final candidates = data.rides.where((ride) {'));
  });

  test('la ventana de precio fijo se cierra sola al terminar el turno', () {
    expect(src, contains('widget.onExpired?.call()'));
    expect(src, contains("driverPopupRide['dispatch_style'] == 'sequential'"));
  });
}
