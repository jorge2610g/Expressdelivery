import 'dart:io';

import 'package:expressdelivery/design/express_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los colores de marca son el azul y el ámbar del rediseño', () {
    expect(ExpressDesign.blue, const Color(0xFF0B57D0));
    expect(ExpressDesign.amber, const Color(0xFFFFB020));
    expect(ExpressDesign.minTouch, greaterThanOrEqualTo(48));
  });

  test('el precio es una cifra grande y en negrita', () {
    final style = ExpressDesign.price();
    expect(style.fontSize, 32);
    expect(style.fontWeight, FontWeight.w800);
  });

  test('applyExpressDesign ajusta botones, diálogos y paneles', () {
    final theme = applyExpressDesign(ThemeData(useMaterial3: true));
    final filled = theme.filledButtonTheme.style!;
    expect(
      filled.minimumSize!.resolve(<WidgetState>{})!.height,
      ExpressDesign.minTouch,
    );
    final dialog = theme.dialogTheme.shape as RoundedRectangleBorder;
    expect(
      dialog.borderRadius,
      BorderRadius.circular(ExpressDesign.radiusSheet),
    );
    expect(theme.navigationBarTheme.height, ExpressDesign.navHeight);
    expect(theme.navigationBarTheme.indicatorColor, ExpressDesign.blueSoft);
  });

  test('el tema oscuro mantiene su esquema y solo cambia las formas', () {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF101114),
    );
    final theme = applyExpressDesign(base);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF101114));
    expect(theme.navigationBarTheme.indicatorColor!.a, lessThan(1));
  });

  testWidgets('el asa del panel mide 40 × 4', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExpressSheetHandle())),
    );
    final box = tester.getSize(find.byType(Container).first);
    expect(box.width, 40);
    expect(box.height, 4);
  });

  test('el inicio del pasajero usa el sistema de diseño', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains("import 'design/express_design.dart';"));
    expect(home, contains("'¿A dónde vas?'"));
    expect(home, contains('ExpressDesign.price('));
    expect(home, contains('accent: true'));
    final main = File('lib/mobile_main.dart').readAsStringSync();
    expect(main, contains('applyExpressDesign('));
    final web = File('lib/web_main.dart').readAsStringSync();
    expect(web, contains('applyExpressDesign('));
  });
}
