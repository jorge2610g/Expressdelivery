import 'dart:io';

import 'package:expressdelivery/location_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// El buscador del pasajero solo muestra lugares dentro de la zona donde está.
void main() {
  // Centro y radio de la zona Trinidad (service_zones).
  const trinidad = LatLng(-14.8258096970690463, -64.8923540859253525);
  const radiusKm = 25.0;

  bool inside(double lat, double lng) => expressInsideZone(
        latitude: lat,
        longitude: lng,
        center: trinidad,
        radiusKm: radiusKm,
      );

  test('una calle dentro de la zona se muestra', () {
    expect(inside(-14.8300, -64.9000), isTrue);
  });

  test('ciudades de otros municipios o departamentos quedan fuera', () {
    // San Ignacio de Moxos (Beni), Quillacollo y Vinto (Cochabamba).
    expect(inside(-14.9667, -65.6333), isFalse);
    expect(inside(-17.4000, -66.2800), isFalse);
    expect(inside(-17.7000, -66.3000), isFalse);
  });

  test('el límite es el radio de la zona', () {
    // ~21 km al este del centro: dentro. ~27 km: fuera.
    expect(inside(-14.8258, -64.6823), isTrue);
    expect(inside(-14.8258, -64.6200), isFalse);
  });

  test('la búsqueda de origen y destino pasa la zona al selector', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains('Future<({LatLng center, double radiusKm})?> _passengerSearchZone() async {'));
    expect(home, contains('persistZone: false,'));
    expect(
      RegExp(r'final searchZone = await _passengerSearchZone\(\);').allMatches(home).length,
      2,
    );
    expect(
      RegExp(r'zoneRadiusKm: searchZone\?\.radiusKm,').allMatches(home).length,
      2,
    );
  });

  test('el selector filtra por zona y pide más resultados cuando hay zona', () {
    final picker = File('lib/location_picker.dart').readAsStringSync();
    expect(picker, contains("'limit': widget.zoneCenter == null ? '10' : '40',"));
    expect(picker, contains('expressInsideZone('));
    expect(picker, contains('final LatLng? zoneCenter;'));
  });
}
