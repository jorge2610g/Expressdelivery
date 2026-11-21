import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La oferta que el pasajero escribe no debe perderse al confirmar el origen:
/// _fitRoute() reinicia la tarifa al mínimo y la app mandaba Bs 6 en vez de la
/// oferta mostrada (por ejemplo Bs 50).
void main() {
  test('la oferta manual se conserva al confirmar el origen', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    final keep = home.indexOf('final keptFare = fareManuallyEdited ? fare : null;');
    final fit = home.indexOf('await _fitRoute();', keep);
    final restore = home.indexOf('fare = keptFare;', fit);
    final create = home.indexOf('widget.service.createRideRequest(', restore);
    expect(keep, isNonNegative);
    expect(fit, greaterThan(keep));
    expect(restore, greaterThan(fit));
    expect(create, greaterThan(restore));
    final guard = home.substring(fit, restore);
    expect(guard, contains('keptFare.toDouble() >= quoteFloor'),
        reason: 'nunca restaurar una oferta por debajo del mínimo');
  });

  test('si el mínimo cambia al publicar, se vuelve a cotizar con aviso claro', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains("e.toString().contains('tarifa mínima recomendada')"));
    expect(home, contains('La tarifa mínima cambió'));
  });
}
