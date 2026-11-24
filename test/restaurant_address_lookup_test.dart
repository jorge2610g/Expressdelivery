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

  test('autocompletado: no manda idioma no soportado y completa la calle con el número',
      () async {
    final queries = <String>[];
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      expect(request.url.queryParameters.containsKey('lang'), isFalse);
      final q = request.url.queryParameters['q'] ?? '';
      queries.add(q);
      // Con el número no hay resultado; la calle sola sí.
      final hasNumber = q.contains('2078');
      return http.Response(
        jsonEncode({
          'features': hasNumber
              ? []
              : [
                  {
                    'geometry': {
                      'coordinates': [-70.15, -20.22],
                    },
                    'properties': {
                      'countrycode': 'CL',
                      'street': 'Arturo Pérez Canto',
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
      query: 'arturo perez canto 2078',
      countryCode: 'CL',
      proximity: const LatLng(-20.23, -70.13),
    );

    expect(results, hasLength(1));
    expect(results.single.label, startsWith('Arturo Pérez Canto 2078'));
    expect(results.single.label, contains('Iquique'));
    expect(queries.first, contains('2078'));
    expect(queries.last, isNot(contains('2078')));
  });

  test('autocompletado: agrega el número escrito aunque el mapa devuelva solo la calle',
      () async {
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      Map<String, dynamic> street(double lng) => {
            'geometry': {'coordinates': [lng, -20.22]},
            'properties': {
              'countrycode': 'CL',
              'name': 'Arturo Pérez Canto',
              'osm_key': 'highway',
              'city': 'Iquique',
              'country': 'Chile',
            },
          };
      return http.Response(
          jsonEncode({'features': [street(-70.15), street(-70.16)]}), 200);
    });
    final results = await ExpressMapProvider.searchAddress(
      query: 'arturo perez canto 2078',
      countryCode: 'CL',
      proximity: const LatLng(-20.23, -70.13),
    );
    expect(results, hasLength(1)); // sin repetir la misma calle
    expect(results.single.label, 'Arturo Pérez Canto 2078, Iquique, Chile');
  });

  test('autocompletado: sin número escrito no se inventa uno', () async {
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {'coordinates': [-70.15, -20.22]},
                'properties': {
                  'countrycode': 'CL',
                  'name': 'Arturo Pérez Canto',
                  'osm_key': 'highway',
                  'city': 'Iquique',
                },
              },
            ],
          }),
          200);
    });
    final results = await ExpressMapProvider.searchAddress(
      query: 'arturo perez canto',
      countryCode: 'CL',
      proximity: const LatLng(-20.23, -70.13),
    );
    expect(results.single.label, 'Arturo Pérez Canto, Iquique');
  });

  test('autocompletado: busca primero cerca del local y ordena por cercanía', () async {
    final bboxes = <String?>[];
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      bboxes.add(request.url.queryParameters['bbox']);
      Map<String, dynamic> f(String city, double lng, double lat) => {
            'geometry': {'coordinates': [lng, lat]},
            'properties': {
              'countrycode': 'CL',
              'street': 'Pasaje Fresia',
              'housenumber': '2039',
              'city': city,
              'country': 'Chile',
            },
          };
      return http.Response(
          jsonEncode({
            'features': [
              f('Concepción', -73.05, -36.82),
              f('Iquique', -70.14, -20.24),
              f('Renca', -70.72, -33.4),
            ],
          }),
          200);
    });
    final results = await ExpressMapProvider.searchAddress(
      query: 'fresia 2039',
      countryCode: 'CL',
      proximity: const LatLng(-20.2307, -70.1357),
    );
    expect(bboxes.first, isNotNull); // primera consulta acotada al área del local
    expect(results.first.label, contains('Iquique'));
    expect(results.last.label, contains('Concepción'));
  });

  test('autocompletado: si no hay nada cerca, busca en todo el país', () async {
    final bboxes = <String?>[];
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      final bbox = request.url.queryParameters['bbox'];
      bboxes.add(bbox);
      return http.Response(
          jsonEncode({
            'features': bbox != null
                ? []
                : [
                    {
                      'geometry': {'coordinates': [-73.05, -36.82]},
                      'properties': {
                        'countrycode': 'CL',
                        'street': 'Calle Lejana',
                        'housenumber': '10',
                        'city': 'Concepción',
                      },
                    },
                  ],
          }),
          200);
    });
    final results = await ExpressMapProvider.searchAddress(
      query: 'calle lejana 10',
      countryCode: 'CL',
      proximity: const LatLng(-20.2307, -70.1357),
    );
    expect(results.single.label, contains('Concepción'));
    expect(bboxes.last, isNull);
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
