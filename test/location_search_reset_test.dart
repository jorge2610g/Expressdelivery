import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Al elegir una sugerencia, el campo de búsqueda debe quedar vacío para que la
/// siguiente búsqueda no se mezcle con la dirección anterior.
void main() {
  test('elegir una sugerencia limpia el campo de búsqueda', () {
    final picker = File('lib/location_picker.dart').readAsStringSync();
    final start = picker.indexOf('void _selectSuggestion(_PlaceSuggestion place) {');
    expect(start, greaterThan(0));
    final end = picker.indexOf('mapController.move(point, 17);', start);
    expect(end, greaterThan(start));

    final body = picker.substring(start, end);
    expect(body, contains('searchController.clear();'));
    expect(body, isNot(contains('searchController.text = place.label')));
    expect(body, contains('labelController.text = place.label;'));
  });
}
