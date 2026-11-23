import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = File('lib/saved_addresses_page.dart').readAsStringSync();
  final home = File('lib/video_style_home.dart').readAsStringSync();

  test('Mis direcciones permite elegir una dirección como destino', () {
    expect(page, contains('final bool selectable;'));
    expect(page, contains('onTap: widget.selectable ? () => choose(row) : null'));
    expect(page, contains('Navigator.pop(context, row)'));
    // Una dirección sin coordenadas avisa en vez de fallar en silencio.
    expect(page, contains('no tiene ubicación en el mapa'));
  });

  test('Ver todos abre la lista para elegir y cotiza como Casa y Trabajo', () {
    expect(home, contains('SavedAddressesPage(service: widget.service, selectable: true)'));
    expect(home, contains('onSavedPlaces: _openSavedPlaces'));
    expect(home, contains('onSaved: _applySavedPlace'));
    expect(home, contains('void _applySavedPlace(Map<String, dynamic> row)'));
    // La ruta pasa a confirmar (de ahí se cotiza), igual que Casa y Trabajo.
    final start = home.indexOf('void _applySavedPlace');
    final body = home.substring(start, start + 900);
    expect(body, contains('routeConfirmed = false'));
    expect(body, contains('_fitRoute()'));
  });

  test('el menú de lugares guardados sigue siendo solo de gestión', () {
    final connected = File('lib/connected_experience.dart').readAsStringSync();
    expect(connected, contains('SavedAddressesPage(service: widget.service)'));
    expect(connected, isNot(contains('selectable: true')));
  });
}
