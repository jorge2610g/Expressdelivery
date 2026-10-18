import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contratos de geometría de la PR #262 (menú del conductor y cuadro de espera).
/// La verificación visual se hace en los emuladores con capturas.
void main() {
  late String home;

  setUpAll(() {
    home = File('lib/video_style_home.dart').readAsStringSync();
  });

  String section(String start, int length) {
    final index = home.indexOf(start);
    expect(index, isNonNegative, reason: 'missing $start');
    return home.substring(index, index + length);
  }

  test('driver menu sheet is allowed to grow with its content', () {
    final menu = section('void _showDriverMenu() {', 2600);
    expect(menu, contains('isScrollControlled: true,'));
    // Un único desplazamiento: el de la hoja. No se añade un segundo contenedor con altura fija.
    expect(menu, isNot(contains('SizedBox(height:')));
    expect(menu, isNot(contains('ListView(shrinkWrap')));
  });

  test('waiting card has symmetric horizontal margins', () {
    final card = section('class _DriverOfferWaitingOverlay', 4000);
    expect(card, contains('EdgeInsets.symmetric(horizontal: 16)'));
    expect(card, isNot(contains('EdgeInsets.only(left: 16, right: 72)')));
  });
}
