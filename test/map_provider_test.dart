import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/map_provider.dart';

void main() {
  test('Mapbox public token selects 512px Mapbox static tiles', () {
    final url = ExpressMapProvider.tileUrlForToken('pk.test-token');
    expect(url, contains('api.mapbox.com/styles/v1/mapbox/streets-v12'));
    expect(url, contains('/tiles/512/'));
    expect(url, contains('access_token=pk.test-token'));
    expect(
      ExpressMapProvider.fallbackTileUrlForToken('pk.test-token'),
      ExpressMapProvider.osmTileUrl,
    );
  });

  test('missing or invalid Mapbox token keeps OpenStreetMap primary', () {
    expect(
      ExpressMapProvider.tileUrlForToken(''),
      ExpressMapProvider.osmTileUrl,
    );
    expect(
      ExpressMapProvider.tileUrlForToken('sk.server-secret'),
      ExpressMapProvider.osmTileUrl,
    );
    expect(ExpressMapProvider.fallbackTileUrlForToken(''), isNull);
  });

  test('quota state parses limits and computes highest usage ratio', () {
    final state = ExpressMapQuotaState.fromMap({
      'mode': 'auto',
      'use_mapbox': true,
      'warning': true,
      'directions_used': 81000,
      'directions_limit': 100000,
      'static_tiles_used': 180000,
      'static_tiles_limit': 200000,
      'warning_ratio': 0.8,
      'fallback_ratio': 0.9,
      'period_start': '2026-10-01',
      'period_end': '2026-10-31',
    });

    expect(state.loaded, isTrue);
    expect(state.useMapbox, isTrue);
    expect(state.directionsRatio, closeTo(.81, .0001));
    expect(state.staticTilesRatio, closeTo(.90, .0001));
    expect(state.highestRatio, closeTo(.90, .0001));
    expect(state.periodStart, isNotNull);
    expect(state.periodEnd, isNotNull);
  });

  test('safe fallback disables Mapbox until quota state is known', () {
    const state = ExpressMapQuotaState.safeFallback();
    expect(state.loaded, isFalse);
    expect(state.useMapbox, isFalse);
    expect(state.directionsLimit, 100000);
    expect(state.staticTilesLimit, 200000);
    expect(state.fallbackRatio, .90);
  });
}
