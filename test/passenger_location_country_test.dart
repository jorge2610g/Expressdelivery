import 'dart:io';

import 'package:expressdelivery/location_picker.dart';
import 'package:flutter_test/flutter_test.dart';

/// El buscador de direcciones del pasajero no debe mostrar lugares de otros países.
void main() {
  test('sin país indicado no filtra', () {
    expect(expressPhotonInCountry({'countrycode': 'AR'}, null), isTrue);
    expect(expressPhotonInCountry({'countrycode': 'AR'}, ''), isTrue);
  });

  test('solo acepta lugares del país de operación', () {
    expect(expressPhotonInCountry({'countrycode': 'BO'}, 'BO'), isTrue);
    expect(expressPhotonInCountry({'countrycode': 'AR'}, 'BO'), isFalse);
    expect(expressPhotonInCountry({'countrycode': 'CL'}, 'BO'), isFalse);
  });

  test('compara sin distinguir mayúsculas', () {
    expect(expressPhotonInCountry({'countrycode': 'bo'}, 'bo'), isTrue);
    expect(expressPhotonInCountry({'countrycode': 'BO'}, ' Bo '), isTrue);
  });

  test('un resultado sin código de país se descarta cuando hay filtro', () {
    expect(expressPhotonInCountry({'name': 'Trinidad'}, 'BO'), isFalse);
  });

  test('ambos selectores del pasajero envían el país de operación', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains('Future<String?> _passengerCountryCode() async {'));
    expect(home, contains("context['country_code']"));
    expect(
      RegExp(r'final countryCode = await _passengerCountryCode\(\);').allMatches(home).length,
      2,
    );
    expect(
      RegExp(r'LocationPickerPage\(\n\s+countryCode: countryCode,').allMatches(home).length,
      2,
    );
  });
}
