import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la tarjeta de tarifa no muestra la barra − / + mientras calcula', () {
    final src = File('lib/video_style_home.dart').readAsStringSync();
    expect(
      src,
      contains('priceChoice == null && (fixedPrice || quoting || !fareReady)'),
    );
  });
}
