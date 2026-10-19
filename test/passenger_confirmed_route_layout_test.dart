import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('route chooser remains bounded and preserves map viewport', () {
    final code = File('lib/video_style_home.dart').readAsStringSync();
    expect(code, contains('class _RideServiceChooserPanel'));
    expect(code, contains('Confirmar ruta y continuar'));
    expect(code, contains('No se pudo calcular la tarifa · Reintentar'));
    expect(code, contains('maxHeight: MediaQuery.sizeOf(context).height * .84'));
    expect(code, isNot(contains('BoxConstraints(minHeight: bounds.maxHeight)')));
  });
}
