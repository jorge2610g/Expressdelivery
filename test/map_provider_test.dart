import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/map_provider.dart';

void main() {
  test('Mapbox public token selects Mapbox static tiles', () {
    final url = ExpressMapProvider.tileUrlForToken('pk.test-token');
    expect(url, contains('api.mapbox.com/styles/v1/mapbox/streets-v12'));
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
}
