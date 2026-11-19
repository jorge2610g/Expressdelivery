import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

/// Abre la caché de mosaicos de flutter_map.
typedef TileCacheOpener = Future<MapCachingProvider> Function();

/// Caché de mosaicos que nunca deja el mapa en blanco.
///
/// flutter_map prepara su caché en segundo plano. Si esa preparación falla
/// (almacenamiento lleno, carpeta no escribible), sus lecturas se quedan
/// esperando para siempre y cada mosaico se pinta transparente sin ningún
/// aviso. Este envoltorio limita el tiempo de cada operación y, si la caché no
/// responde, pide los mosaicos directamente a la red.
class ExpressSafeTileCache implements MapCachingProvider {
  ExpressSafeTileCache({
    required TileCacheOpener open,
    this.openTimeout = const Duration(seconds: 6),
    this.operationTimeout = const Duration(seconds: 5),
  }) : _open = open;

  final TileCacheOpener _open;
  final Duration openTimeout;
  final Duration operationTimeout;

  Future<MapCachingProvider?>? _opening;
  bool _disabled = false;

  /// Siempre `true`: si la caché no responde, la lectura devuelve `null` y
  /// flutter_map descarga el mosaico desde la red.
  @override
  bool get isSupported => true;

  Future<MapCachingProvider?> _ready() {
    if (_disabled) return Future<MapCachingProvider?>.value(null);
    return _opening ??= _openSafely();
  }

  Future<MapCachingProvider?> _openSafely() async {
    try {
      return await _open().timeout(openTimeout);
    } on TimeoutException {
      _disabled = true;
      debugPrint('[Express] La caché de mosaicos no respondió; se usa la red.');
      return null;
    } catch (error) {
      _disabled = true;
      debugPrint('[Express] La caché de mosaicos no está disponible: ${error.runtimeType}.');
      return null;
    }
  }

  @override
  Future<CachedMapTile?> getTile(String url) async {
    final cache = await _ready();
    if (cache == null) return null;
    try {
      return await cache.getTile(url).timeout(operationTimeout);
    } on TimeoutException {
      _disabled = true;
      return null;
    } catch (_) {
      // Un mosaico dañado solo se descarga de nuevo desde la red.
      return null;
    }
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    final cache = await _ready();
    if (cache == null) return;
    try {
      await cache
          .putTile(url: url, metadata: metadata, bytes: bytes)
          .timeout(operationTimeout);
    } on TimeoutException {
      _disabled = true;
    } catch (_) {
      // Guardar en caché es una mejora; el mosaico ya se mostró.
    }
  }
}
