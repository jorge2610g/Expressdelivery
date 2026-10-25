import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:expressdelivery/map_provider.dart';

void main() {
  late http.Client originalClient;

  setUp(() {
    originalClient = ExpressMapProvider.routeHttpClient;
  });

  tearDown(() {
    ExpressMapProvider.routeHttpClient.close();
    ExpressMapProvider.routeHttpClient = originalClient;
  });

  test('address autocomplete falls back to OpenStreetMap geocoding', () async {
    final hosts = <String>[];
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      hosts.add(request.url.host);
      if (request.url.host == 'api.mapbox.com') {
        return http.Response('{}', 503);
      }
      return http.Response(
        jsonEncode({
          'features': [
            {
              'geometry': {
                'coordinates': [-70.153, -20.214],
              },
              'properties': {
                'countrycode': 'CL',
                'name': 'Avenida Arturo Prat',
                'housenumber': '123',
                'city': 'Iquique',
                'country': 'Chile',
              },
            },
          ],
        }),
        200,
      );
    });

    final results = await ExpressMapProvider.searchAddress(
      query: 'Avenida Prat',
      city: 'Iquique',
      countryCode: 'CL',
      proximity: const LatLng(-20.214, -70.153),
    );

    expect(results, hasLength(1));
    expect(results.single.label, contains('Iquique'));
    expect(results.single.latitude, -20.214);
    expect(hosts, contains('photon.komoot.io'));
  });

  test('map reverse geocoding falls back to OpenStreetMap', () async {
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      if (request.url.host == 'api.mapbox.com') {
        return http.Response('{}', 503);
      }
      return http.Response(
        jsonEncode({
          'features': [
            {
              'properties': {
                'countrycode': 'BO',
                'street': 'Calle Bolívar',
                'city': 'Trinidad',
                'country': 'Bolivia',
              },
            },
          ],
        }),
        200,
      );
    });

    final result = await ExpressMapProvider.reverseGeocode(
      point: const LatLng(-14.8337, -64.9008),
      countryCode: 'BO',
    );

    expect(result, contains('Calle Bolívar'));
    expect(result, contains('Trinidad'));
  });

  test('reverse geocoding can return a place without a selected zone', () async {
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      expect(request.url.host, 'photon.komoot.io');
      return http.Response(
        jsonEncode({
          'features': [
            {
              'properties': {
                'city': 'Cochabamba',
                'country': 'Bolivia',
              },
            },
          ],
        }),
        200,
      );
    });

    final label = await ExpressMapProvider.reverseGeocodeLocationLabel(
      point: const LatLng(-17.4022, -66.1571),
    );

    expect(label, 'Cochabamba, Bolivia');
    expect(label, isNot(contains('-17.4022')));
  });

  test('Mapbox autocomplete path encodes the address only once', () async {
    final source = await File('lib/map_provider.dart').readAsString();

    expect(source, contains("Uri.parse("));
    expect(
      source,
      contains("'https://api.mapbox.com/geocoding/v5/mapbox.places/'"),
    );
    expect(source, contains("Uri.encodeComponent(mapboxQuery)}.json'"));
    expect(
      source,
      contains("'types': 'address,poi,place,locality,neighborhood'"),
    );
    expect(
      source,
      isNot(contains("Uri.encodeComponent(mapboxQuery)}.json',\n      ),")),
    );
  });
  test('reverse geocoding identifies a country without a city', () async {
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      expect(request.url.host, 'photon.komoot.io');
      return http.Response(
        jsonEncode({
          'features': [
            {
              'properties': {'countrycode': 'BO'},
            },
          ],
        }),
        200,
      );
    });

    final country = await ExpressMapProvider.reverseGeocodeCountryCode(
      point: const LatLng(-14.8337, -64.9008),
    );

    expect(country, 'BO');
  });

}
