import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:expressdelivery/map_tile_cache.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// Caché de prueba que responde lo que se le indique.
class _FakeCache implements MapCachingProvider {
  final Map<String, CachedMapTile> stored = <String, CachedMapTile>{};
  Future<CachedMapTile?> Function(String url)? onGet;

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    final handler = onGet;
    if (handler != null) return handler(url);
    return stored[url];
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    stored[url] = (
      bytes: bytes ?? Uint8List(0),
      metadata: metadata,
    );
  }
}

CachedMapTileMetadata _metadata() => CachedMapTileMetadata(
      staleAt: DateTime.now().toUtc().add(const Duration(days: 1)),
      lastModified: null,
      etag: null,
    );

ExpressSafeTileCache _cache(
  TileCacheOpener open, {
  Duration openTimeout = const Duration(milliseconds: 300),
  Duration operationTimeout = const Duration(milliseconds: 300),
}) {
  return ExpressSafeTileCache(
    open: open,
    openTimeout: openTimeout,
    operationTimeout: operationTimeout,
  );
}

void main() {
  const url = 'https://tile.openstreetmap.org/12/1329/2254.png';

  test('si la caché no se puede abrir, el mosaico se pide a la red', () async {
    final cache = _cache(() async => throw const FileSystemException('sin espacio'));
    expect(await cache.getTile(url), isNull);
    await cache.putTile(url: url, metadata: _metadata(), bytes: Uint8List(2));
  });

  test('si la caché nunca responde, no bloquea el mapa', () async {
    final never = Completer<MapCachingProvider>();
    final cache = _cache(() => never.future);
    final stopwatch = Stopwatch()..start();
    expect(await cache.getTile(url), isNull);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('si una lectura se queda colgada, las siguientes ya no esperan', () async {
    final hung = _FakeCache()..onGet = (_) => Completer<CachedMapTile?>().future;
    final cache = _cache(() async => hung);
    expect(await cache.getTile(url), isNull);

    final stopwatch = Stopwatch()..start();
    expect(await cache.getTile('https://tile.openstreetmap.org/12/1/1.png'), isNull);
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 100)));
  });

  test('un mosaico dañado se descarta sin desactivar la caché', () async {
    var calls = 0;
    final fake = _FakeCache()
      ..onGet = (_) async {
        calls++;
        throw StateError('mosaico dañado');
      };
    final cache = _cache(() async => fake);
    expect(await cache.getTile(url), isNull);
    expect(await cache.getTile(url), isNull);
    expect(calls, 2);
  });

  test('con caché sana devuelve el mosaico guardado', () async {
    final fake = _FakeCache();
    final cache = _cache(() async => fake);
    await cache.putTile(url: url, metadata: _metadata(), bytes: Uint8List.fromList(<int>[1, 2, 3]));
    final tile = await cache.getTile(url);
    expect(tile, isNotNull);
    expect(tile!.bytes, Uint8List.fromList(<int>[1, 2, 3]));
  });

  test('el mapa usa el envoltorio seguro para la caché de mosaicos', () {
    final provider = File('lib/map_provider.dart').readAsStringSync();
    expect(provider, contains("import 'map_tile_cache.dart';"));
    expect(provider, contains('ExpressSafeTileCache('));
    expect(provider, contains('cachingProvider: ExpressMapProvider.offlineTileCache,'));
  });
}
