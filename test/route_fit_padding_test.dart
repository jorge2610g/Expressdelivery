import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/video_style_home.dart';

void main() {
  test('el margen inferior sigue el alto real de la tarjeta', () {
    final small = expressRouteFitPadding(
        screenHeight: 900, topSafe: 24, panelFraction: .56);
    final big = expressRouteFitPadding(
        screenHeight: 900, topSafe: 24, panelFraction: .72);
    expect(big.bottom, greaterThan(small.bottom));
    expect(big.bottom, closeTo(900 * .72 + 48, 0.01));
  });

  test('siempre queda mapa visible para la ruta, incluso en pantallas bajas', () {
    for (final h in [640.0, 700.0, 790.0, 900.0, 1000.0]) {
      final p = expressRouteFitPadding(
          screenHeight: h, topSafe: 0, panelFraction: .72);
      final visible = h - p.top - p.bottom;
      expect(visible, greaterThanOrEqualTo(60.0),
          reason: 'alto $h: visible $visible');
      expect(p.top, greaterThanOrEqualTo(56.0));
    }
  });

  test('en una pantalla alta se conserva el margen superior completo', () {
    final p = expressRouteFitPadding(
        screenHeight: 1000, topSafe: 24, panelFraction: .6);
    expect(p.top, closeTo(116.0, 0.01));
  });
  alturaRealDeLaTarjeta();
}

void alturaRealDeLaTarjeta() {
  test('si se conoce el alto real de la tarjeta manda sobre la fracción', () {
    final estimated = expressRouteFitPadding(
        screenHeight: 790, topSafe: 0, panelFraction: .72);
    final real = expressRouteFitPadding(
        screenHeight: 790, topSafe: 0, panelFraction: .72, panelHeight: 621);
    expect(real.bottom, closeTo(621 + 48, 0.01));
    expect(real.bottom, greaterThan(estimated.bottom));
    // Aun con la tarjeta más alta, la ruta tiene mapa visible.
    expect(790 - real.top - real.bottom, greaterThanOrEqualTo(60));
  });
  test('la cobertura de la tarjeta sale de dónde empieza en pantalla', () {
    expect(expressPanelCoverage(mapHeight: 790, panelTopInMap: 169), 621);
    expect(expressPanelCoverage(mapHeight: 790, panelTopInMap: -5), isNull);
    expect(expressPanelCoverage(mapHeight: 790, panelTopInMap: 800), isNull);
    expect(expressPanelCoverage(mapHeight: 0, panelTopInMap: 10), isNull);
  });
}
