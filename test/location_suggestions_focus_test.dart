import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La lista de sugerencias no debe depender del foco del campo: al tocar una
/// sugerencia el teclado se cierra y el foco se pierde antes de que termine el toque.
void main() {
  test('la lista se muestra mientras haya sugerencias, con o sin foco', () {
    final picker = File('lib/location_picker.dart').readAsStringSync();
    expect(picker, contains('if (suggestions.isNotEmpty || searching)'));
    expect(picker, isNot(contains('if (searchFocus.hasFocus &&\n                      (suggestions.isNotEmpty || searching))')));
    expect(picker, contains('suggestions.isNotEmpty ||\n            searching;'));
  });
}
