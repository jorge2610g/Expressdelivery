import 'dart:convert';

import 'package:expressdelivery/map_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

http.Response _osrmRoute() {
  return http.Response(
    jsonEncode(<String, dynamic>{
      'routes': <Map<String, dynamic>>[
        <String, dynamic>{
          'distance': 1200.0,
          'duration': 300.0,
          'geometry': <String, dynamic>{
            'coordinates': <List<double>>[
              <double>[-68.1, -16.5],
              <double>[-68.11, -16.51],
              <double>[-68.12, -16.52],
            ],
          },
        },
      ],
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

void main() {
  late http.Client originalClient;
  late int networkCalls;

  void useClient(Future<http.Response> Function(http.Request) respond) {
    ExpressMapProvider.routeHttpClient = MockClient((request) async {
      networkCalls++;
      return respond(request);
    });
  }

  setUp(() {
    originalClient = ExpressMapProvider.routeHttpClient;
    networkCalls = 0;
  });

  tearDown(() {
    ExpressMapProvider.routeHttpClient = originalClient;
  });

  test('identical concurrent route requests share one network call', () async {
    useClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return _osrmRoute();
    });
    final from = const LatLng(-16.5001, -68.1001);
    final to = const LatLng(-16.5201, -68.1201);

    final results = await Future.wait(<Future<ExpressMapRoute>>[
      ExpressMapProvider.drivingRoute(from: from, to: to),
      ExpressMapProvider.drivingRoute(from: from, to: to),
    ]);

    expect(networkCalls, 1);
    expect(results[0].provider, 'osrm');
    expect(results[1].points.length, results[0].points.length);
  });

  test('a failed route falls back to a straight line that is not cached',
      () async {
    var fail = true;
    useClient((_) async {
      return fail
          ? http.Response('server error', 500)
          : _osrmRoute();
    });
    final from = const LatLng(-16.6001, -68.2001);
    final to = const LatLng(-16.6201, -68.2201);

    final straight = await ExpressMapProvider.drivingRoute(from: from, to: to);
    expect(straight.provider, 'direct');
    expect(networkCalls, 1);

    // Once the service recovers, the next request must reach the network
    // again and return the real route instead of the cached straight line.
    fail = false;
    final real = await ExpressMapProvider.drivingRoute(from: from, to: to);
    expect(real.provider, 'osrm');
    expect(networkCalls, 2);
  });

  test('a successful route is cached for repeated requests', () async {
    useClient((_) async => _osrmRoute());
    final from = const LatLng(-16.7001, -68.3001);
    final to = const LatLng(-16.7201, -68.3201);

    final first = await ExpressMapProvider.drivingRoute(from: from, to: to);
    final second = await ExpressMapProvider.drivingRoute(from: from, to: to);

    expect(first.provider, 'osrm');
    expect(second.provider, 'osrm');
    expect(networkCalls, 1);
  });
}
