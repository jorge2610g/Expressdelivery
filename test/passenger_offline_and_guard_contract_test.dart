import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source-contract tests: these guard behaviour that is wired inside widget
// State classes (no seam exists to pump them without Supabase and Mapbox).
void main() {
  test('offline passenger start never invents coverage or a zone', () {
    final shell = File('lib/connected_shell.dart').readAsStringSync();
    // The fabricated landing claimed "inside coverage", zone "Express" and a
    // "last saved location" that may not exist. It must stay removed.
    expect(shell, isNot(contains('Usando tu última ubicación guardada')));
    expect(shell, isNot(contains("'inside_coverage': true")));
    expect(shell, isNot(contains('_offlinePassengerLanding(')));
    expect(shell, contains('return cachedLanding;'));
  });

  test('ride confirmation and creation cannot start twice on a double tap', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains('bool _confirmRouteInFlight = false;'));
    expect(home, contains('if (_confirmRouteInFlight) return;'));
    expect(home, contains('bool _createServiceInFlight = false;'));
    expect(home, contains('if (_createServiceInFlight) return;'));
    expect(home, contains('await _createServiceBody();'));
    expect(home, contains('await _confirmRouteBody();'));
  });

  test('straight-line route fallback is never cached', () {
    final provider = File('lib/map_provider.dart').readAsStringSync();
    final fetch = provider.substring(
      provider.indexOf('static Future<ExpressMapRoute> _fetchDrivingRoute'),
      provider.indexOf('static Future<ExpressMapRoute?> _mapboxRoute'),
    );
    final fallback = fetch.indexOf("provider: 'direct'");
    final cacheWrite = fetch.indexOf('_routeCache[key] = _CachedRoute');
    expect(fallback, greaterThan(-1));
    expect(cacheWrite, greaterThan(fallback),
        reason: 'the cache write must come after the direct-fallback return');
  });
}
