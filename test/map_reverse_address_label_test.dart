import 'package:expressdelivery/map_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reverse geocoding prefers a street and combines locality', () {
    final label = expressAddressLabelFromPhotonFeatures([
      {
        'properties': {
          'name': 'Calle Luis Aguilera Ferrier',
          'street': 'Calle Luis Aguilera Ferrier',
          'city': 'Trinidad',
          'state': 'El Beni',
          'country': 'Bolivia',
          'countrycode': 'BO',
        },
      },
    ], countryCode: 'BO');

    expect(label, 'Calle Luis Aguilera Ferrier, Trinidad, El Beni, Bolivia');
  });

  test('reverse geocoding can show city and country without a street', () {
    final label = expressAddressLabelFromPhotonFeatures([
      {
        'properties': {
          'city': 'Trinidad',
          'country': 'Bolivia',
          'countrycode': 'BO',
        },
      },
    ], countryCode: 'BO');

    expect(label, 'Trinidad, Bolivia');
  });

  test('reverse geocoding skips generic labels and other countries', () {
    final label = expressAddressLabelFromPhotonFeatures([
      {
        'properties': {
          'name': 'Ubicación seleccionada',
          'city': 'Trinidad',
          'country': 'Bolivia',
          'countrycode': 'BO',
        },
      },
      {
        'properties': {
          'name': 'Calle extranjera',
          'city': 'Otra ciudad',
          'country': 'Chile',
          'countrycode': 'CL',
        },
      },
    ], countryCode: 'BO');

    expect(label, 'Trinidad, Bolivia');
  });

  test('Nominatim fallback returns the selected street and locality', () {
    final label = expressAddressLabelFromNominatimPayload({
      'display_name': 'Calle Los Cusis, Trinidad, Bolivia',
      'address': {
        'house_number': '42',
        'road': 'Calle Los Cusis',
        'suburb': 'San Vicente',
        'city': 'Trinidad',
        'state': 'El Beni',
        'country': 'Bolivia',
        'country_code': 'bo',
      },
    }, countryCode: 'BO');

    expect(label, '42 Calle Los Cusis, San Vicente, Trinidad, El Beni, Bolivia');
  });

  test('Nominatim fallback ignores a result from a different country', () {
    final label = expressAddressLabelFromNominatimPayload({
      'display_name': 'Calle extranjera, Chile',
      'address': {
        'road': 'Calle extranjera',
        'city': 'Otra ciudad',
        'country': 'Chile',
        'country_code': 'cl',
      },
    }, countryCode: 'BO');

    expect(label, isNull);
  });
}
