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
  menuYQr();
}

void menuYQr() {
  test('el menú lateral no repite opciones que ya están en Perfil', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    final menu = home.substring(
      home.indexOf('void _showPassengerMenu()'),
      home.indexOf('Cambiar a modo Conductor'),
    );
    for (final repetida in [
      'Lugares guardados',
      'Contactos de confianza',
      'Mi perfil',
      'Mis servicios',
      'Pagos y movimientos',
    ]) {
      expect(menu, isNot(contains("Text('$repetida')")), reason: repetida);
    }
    expect(menu, contains('AvisosMenuTile'));
    // Un solo acceso: avisos, chat y calificaciones viven en el Centro Express.
    expect(menu, isNot(contains("Text('Avisos')")));
    final driver = home.substring(
      home.indexOf('void _showDriverMenu()'),
      home.indexOf('Cambiar a modo Pasajero'),
    );
    expect(driver, contains('AvisosMenuTile'));
  });

  test('Mi QR de pago solo aparece para conductores de Bolivia', () {
    final src = File('lib/express_account_pages.dart').readAsStringSync();
    final i = src.indexOf("title: 'Mi QR de pago'");
    expect(i, greaterThan(0));
    final before = src.substring(i - 500, i);
    expect(before, contains("'BO'"));
    expect(before, contains('country_code'));
  });
}
