
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

/// flutter_map sustituye un fallo silenciado por una imagen transparente de
/// 1x1 píxel. Un mosaico real siempre es más ancho (256 o 512 píxeles).
bool isRealTileWidth(int width) => width > 1;

/// Proveedor de teselas que puede congelarse. Una capa saliente deja de pedir
/// mosaicos nuevos (cuota Mapbox y consumo de red), pero conserva los que ya
/// estaban visibles. La capa entrante avisa cuando recibe su primer mosaico real.
class ExpressHandoverTileProvider extends NetworkTileProvider {
  ExpressHandoverTileProvider({
    required http.Client httpClient,
    required MapCachingProvider cachingProvider,
    this.onRealTile,
    this.ownedClient,
  }) : super(
          httpClient: httpClient,
          cachingProvider: cachingProvider,
          silenceExceptions: true,
          // Keep in-flight tiles when a pinch passes through an intermediate
          // zoom. Aborted requests become transparent images and can obscure
          // the parent tile that is already visible below.
          abortObsoleteRequests: false,
        );

  /// Cliente creado solo para esta capa: se cierra al liberarla.
  final http.BaseClient? ownedClient;

  @override
  Future<void> dispose() {
    ownedClient?.close();
    return super.dispose();
  }

  bool frozen = false;

  /// Congela la capa saliente: deja de pedir red cerrando su propio cliente.
  /// Las teselas ya en caché siguen sirviéndose; las que faltan quedan
  /// transparentes sin bloquear el resto del mapa.
  void freeze() {
    if (frozen) return;
    frozen = true;
    ownedClient?.close();
  }

  /// Se llama con el primer mosaico real de la capa entrante.
  void Function()? onRealTile;

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final inner = super.getImageWithCancelLoadingSupport(
      coordinates,
      options,
      cancelLoading,
    );
    return ExpressFirstRealTileImageProvider(inner, () => onRealTile?.call());
  }
}

/// Envuelve la imagen de un mosaico sin añadir peticiones: solo observa el flujo
/// que flutter_map ya resuelve, y avisa una vez cuando llega un mosaico real.
class ExpressFirstRealTileImageProvider extends ImageProvider<Object> {
  ExpressFirstRealTileImageProvider(this.inner, this.onLoaded);

  final ImageProvider inner;
  final VoidCallback onLoaded;

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<Object>(this);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) =>
      throw UnsupportedError('resolve() is overridden');

  // resolve() está marcado como no virtual en Flutter, pero Dart despacha
  // la llamada dinámicamente y las pruebas de widget verifican este camino.
  @override
  // ignore: invalid_override_of_non_virtual_member
  ImageStream resolve(ImageConfiguration configuration) {
    final stream = inner.resolve(configuration);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        stream.removeListener(listener);
        if (isRealTileWidth(info.image.width)) onLoaded();
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return stream;
  }
}

/// Decide cuándo puede retirarse la capa anterior tras cambiar de fuente de
/// teselas. Pura, sin temporizadores.
///
/// - La capa anterior se retira SOLO cuando la capa entrante de la generación
///   actual entrega un mosaico real. Ningún tiempo de espera la retira: si la
///   nueva fuente no responde (sin red o sin caché), el mapa anterior sigue
///   visible hasta que llegue una imagen válida.
/// - Solo cuenta la generación actual: un mosaico de una generación anterior
///   (A→B→A dentro de la ventana) se ignora.
/// - La atribución sigue a la fuente que está en pantalla: la saliente mientras
///   el relevo está pendiente, la activa cuando termina.
class TileHandoverController extends ChangeNotifier {
  int _generation = 0;
  bool? _activeMapbox;
  bool? _outgoingMapbox;

  int get generation => _generation;
  bool? get activeIsMapbox => _activeMapbox;
  bool get handoverPending => _outgoingMapbox != null;

  /// Cambia a [mapbox] sin capa saliente: la fuente anterior nunca llegó a
  /// mostrarse (arranque en frío), así que no hay mapa visible que conservar.
  int beginWithoutOutgoing(bool mapbox) {
    _outgoingMapbox = null;
    _activeMapbox = mapbox;
    _generation++;
    notifyListeners();
    return _generation;
  }

  /// Atribución de la fuente que está en pantalla: mientras el relevo está
  /// pendiente son las teselas salientes; al terminar, la activa.
  bool get attributionIsMapbox => (_outgoingMapbox ?? _activeMapbox) == true;

  /// Empieza un cambio de fuente. Devuelve la nueva generación, o null si la
  /// fuente ya era la activa.
  int? begin(bool mapbox) {
    if (_activeMapbox == mapbox) return null;
    // Si ya hay una capa saliente visible, se conserva: un segundo cambio no la
    // sustituye por la intermedia, que nunca llegó a mostrarse.
    _outgoingMapbox ??= _activeMapbox;
    _activeMapbox = mapbox;
    _generation++;
    notifyListeners();
    return _generation;
  }

  /// Un mosaico real llegó a la capa de la generación [generation].
  void onRealTile(int generation) => finish(generation);

  /// Retira la capa saliente si [generation] es la actual y ya hay un mosaico
  /// real de la nueva fuente. Nunca se llama por tiempo.
  void finish(int generation) {
    if (generation != _generation) return;
    if (_outgoingMapbox == null) return;
    _outgoingMapbox = null;
    notifyListeners();
  }
}

/// Tiempo máximo de espera de teselas de Mapbox en un arranque en frío (sin
/// capa anterior visible). Solo en ese caso se usa OSM como respaldo: con un
/// mapa visible, la capa anterior nunca se retira por tiempo.
const Duration mapboxColdStartFallbackDelay = Duration(seconds: 8);

/// Decide si un arranque en frío debe pasar a OSM. Pura: sin temporizadores.
bool coldStartNeedsOsmFallback({
  required bool mapboxActive,
  required bool outgoingVisible,
  required bool realTileSeen,
}) =>
    mapboxActive && !outgoingVisible && !realTileSeen;
