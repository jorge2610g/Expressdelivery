import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';

class ExpressMapRoute {
  final List<LatLng> points;
  final double? distanceMeters;
  final double? durationSeconds;
  final String provider;

  const ExpressMapRoute({
    required this.points,
    required this.provider,
    this.distanceMeters,
    this.durationSeconds,
  });
}

class ExpressMapQuotaState {
  final String mode;
  final bool useMapbox;
  final bool warning;
  final int directionsUsed;
  final int directionsLimit;
  final int staticTilesUsed;
  final int staticTilesLimit;
  final double warningRatio;
  final double fallbackRatio;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final bool loaded;

  const ExpressMapQuotaState({
    required this.mode,
    required this.useMapbox,
    required this.warning,
    required this.directionsUsed,
    required this.directionsLimit,
    required this.staticTilesUsed,
    required this.staticTilesLimit,
    required this.warningRatio,
    required this.fallbackRatio,
    required this.loaded,
    this.periodStart,
    this.periodEnd,
  });

  const ExpressMapQuotaState.safeFallback()
      : mode = 'auto',
        useMapbox = false,
        warning = false,
        directionsUsed = 0,
        directionsLimit = 100000,
        staticTilesUsed = 0,
        staticTilesLimit = 200000,
        warningRatio = .80,
        fallbackRatio = .90,
        periodStart = null,
        periodEnd = null,
        loaded = false;

  double get directionsRatio =>
      directionsLimit <= 0 ? 1 : directionsUsed / directionsLimit;

  double get staticTilesRatio =>
      staticTilesLimit <= 0 ? 1 : staticTilesUsed / staticTilesLimit;

  double get highestRatio =>
      directionsRatio > staticTilesRatio ? directionsRatio : staticTilesRatio;

  factory ExpressMapQuotaState.fromMap(Map<String, dynamic> row) {
    int asInt(Object? value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    double asDouble(Object? value, double fallback) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? fallback;
    }

    DateTime? asDate(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '');

    return ExpressMapQuotaState(
      mode: row['mode']?.toString() ?? 'auto',
      useMapbox: row['use_mapbox'] == true,
      warning: row['warning'] == true,
      directionsUsed: asInt(row['directions_used'], 0),
      directionsLimit: asInt(row['directions_limit'], 100000),
      staticTilesUsed: asInt(row['static_tiles_used'], 0),
      staticTilesLimit: asInt(row['static_tiles_limit'], 200000),
      warningRatio: asDouble(row['warning_ratio'], .80),
      fallbackRatio: asDouble(row['fallback_ratio'], .90),
      periodStart: asDate(row['period_start']),
      periodEnd: asDate(row['period_end']),
      loaded: true,
    );
  }
}

class ExpressMapProvider {
  ExpressMapProvider._();

  static const String _mapboxToken =
      String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');
  static const String _quotaCacheKey = 'express_mapbox_quota_state_v1';

  // Keep enough of the recently viewed map on-device to survive a temporary
  // loss of connectivity. flutter_map's native cache honours HTTP metadata;
  // the 12h override matches the Mapbox device-cache window used by this app.
  static const int offlineTileCacheMaxBytes = 350000000;
  static const Duration offlineTileFreshAge = Duration(hours: 12);

  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static bool get mapboxConfigured =>
      _mapboxToken.trim().startsWith('pk.');

  static final ValueNotifier<ExpressMapQuotaState> quota =
      ValueNotifier<ExpressMapQuotaState>(
    const ExpressMapQuotaState.safeFallback(),
  );

  static final ValueNotifier<bool> useMapboxTiles =
      ValueNotifier<bool>(false);

  static final Map<String, _CachedRoute> _routeCache =
      <String, _CachedRoute>{};

  static DateTime? _directionsCircuitOpenUntil;
  static DateTime? _tilesCircuitOpenUntil;
  static Timer? _directionsCircuitTimer;
  static Timer? _tilesCircuitTimer;
  static int _consecutiveTileFailures = 0;

  static int _pendingDirectionsUnits = 0;
  static int _pendingStaticTileUnits = 0;
  static bool _usageFlushInFlight = false;
  static Timer? _usageFlushTimer;

  static bool get _directionsCircuitOpen {
    final until = _directionsCircuitOpenUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _directionsCircuitOpenUntil = null;
    return false;
  }

  static bool get _tilesCircuitOpen {
    final until = _tilesCircuitOpenUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _tilesCircuitOpenUntil = null;
    return false;
  }

  static bool get canUseMapboxDirections =>
      mapboxConfigured && quota.value.useMapbox && !_directionsCircuitOpen;

  static bool get canUseMapboxTiles =>
      mapboxConfigured && quota.value.useMapbox && !_tilesCircuitOpen;

  static String get primaryTileUrl =>
      tileUrlForToken(_mapboxToken);

  static String? get fallbackTileUrl =>
      mapboxConfigured ? osmTileUrl : null;

  static String tileUrlForToken(String token) {
    final value = token.trim();
    if (!value.startsWith('pk.')) return osmTileUrl;
    return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}'
        '?access_token=${Uri.encodeQueryComponent(value)}';
  }

  static String? fallbackTileUrlForToken(String token) =>
      token.trim().startsWith('pk.') ? osmTileUrl : null;

  static String offlineTileCacheKey(String url) {
    try {
      final uri = Uri.parse(url);
      final query = Map<String, String>.from(uri.queryParameters)
        ..remove('access_token');
      final sanitized = uri.replace(
        queryParameters: query.isEmpty ? null : query,
      );
      return BuiltInMapCachingProvider.uuidTileKeyGenerator(
        sanitized.toString(),
      );
    } catch (_) {
      return BuiltInMapCachingProvider.uuidTileKeyGenerator(url);
    }
  }

  static final MapCachingProvider offlineTileCache =
      BuiltInMapCachingProvider.getOrCreateInstance(
    maxCacheSize: offlineTileCacheMaxBytes,
    overrideFreshAge: offlineTileFreshAge,
    tileKeyGenerator: offlineTileCacheKey,
  );

  static void _syncEffectiveTileProvider() {
    final next = canUseMapboxTiles;
    if (useMapboxTiles.value != next) {
      useMapboxTiles.value = next;
    }
  }

  static Future<void> _cacheQuotaState(Map<String, dynamic> row) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _quotaCacheKey,
        jsonEncode(<String, dynamic>{
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'state': row,
        }),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _readCachedQuotaState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_quotaCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final savedAt =
          DateTime.tryParse(decoded['saved_at']?.toString() ?? '')?.toUtc();
      final state = decoded['state'];
      if (savedAt == null ||
          state is! Map ||
          DateTime.now().toUtc().difference(savedAt) >
              const Duration(hours: 24)) {
        return null;
      }

      final row = Map<String, dynamic>.from(state);
      final periodEnd =
          DateTime.tryParse(row['period_end']?.toString() ?? '')?.toUtc();
      if (periodEnd != null &&
          DateTime.now().toUtc().isAfter(
                periodEnd.add(const Duration(days: 1)),
              )) {
        return null;
      }
      return row;
    } catch (_) {
      return null;
    }
  }

  static void _applyQuotaState(
    Map<String, dynamic> row, {
    bool persist = true,
  }) {
    quota.value = ExpressMapQuotaState.fromMap(row);
    _syncEffectiveTileProvider();
    if (persist) {
      unawaited(_cacheQuotaState(row));
    }
  }

  static Future<void> initializeQuotaGuard() async {
    await refreshQuotaState();
  }

  static Future<void> refreshQuotaState() async {
    if (!mapboxConfigured || supabase.auth.currentUser == null) {
      quota.value = const ExpressMapQuotaState.safeFallback();
      _syncEffectiveTileProvider();
      return;
    }

    try {
      final raw = await supabase.rpc(
        'mapbox_quota_state',
        params: {'p_channel': ExpressRuntimeChannel.name},
      );
      if (raw is Map) {
        _applyQuotaState(Map<String, dynamic>.from(raw));
        return;
      }
    } catch (_) {
      // Offline/backend unavailable: reuse only a recent quota decision.
    }

    final cached = await _readCachedQuotaState();
    if (cached != null) {
      _applyQuotaState(cached, persist: false);
      return;
    }

    quota.value = const ExpressMapQuotaState.safeFallback();
    _syncEffectiveTileProvider();
  }

  static void _openDirectionsCircuit(Duration duration) {
    _directionsCircuitOpenUntil = DateTime.now().add(duration);
    _directionsCircuitTimer?.cancel();
    _directionsCircuitTimer = Timer(duration, () {
      _directionsCircuitOpenUntil = null;
    });
  }

  static void _openTilesCircuit(Duration duration) {
    _tilesCircuitOpenUntil = DateTime.now().add(duration);
    _tilesCircuitTimer?.cancel();
    _syncEffectiveTileProvider();
    _tilesCircuitTimer = Timer(duration, () {
      _tilesCircuitOpenUntil = null;
      _consecutiveTileFailures = 0;
      _syncEffectiveTileProvider();
    });
  }

  static void noteMapboxTileFailure() {
    _consecutiveTileFailures += 1;
    if (_consecutiveTileFailures >= 3) {
      _openTilesCircuit(const Duration(minutes: 2));
    }
  }

  static void noteMapboxTileSuccess() {
    _consecutiveTileFailures = 0;
  }

  static void noteMapboxDirectionRequest() {
    if (!canUseMapboxDirections) return;
    _pendingDirectionsUnits += 1;
    _scheduleUsageFlush();
  }

  static void noteMapboxStaticTileRequest() {
    if (!canUseMapboxTiles) return;
    _pendingStaticTileUnits += 1;
    _scheduleUsageFlush();
  }

  static void _scheduleUsageFlush() {
    if (_pendingDirectionsUnits >= 5 || _pendingStaticTileUnits >= 32) {
      unawaited(flushPendingUsage());
      return;
    }

    _usageFlushTimer ??= Timer(const Duration(seconds: 15), () {
      _usageFlushTimer = null;
      unawaited(flushPendingUsage());
    });
  }

  static Future<void> flushPendingUsage() async {
    if (_usageFlushInFlight || supabase.auth.currentUser == null) return;
    if (_pendingDirectionsUnits <= 0 && _pendingStaticTileUnits <= 0) return;

    _usageFlushInFlight = true;
    _usageFlushTimer?.cancel();
    _usageFlushTimer = null;

    final directions = _pendingDirectionsUnits.clamp(0, 20).toInt();
    final tiles = _pendingStaticTileUnits.clamp(0, 250).toInt();
    _pendingDirectionsUnits -= directions;
    _pendingStaticTileUnits -= tiles;

    try {
      final raw = await supabase.rpc(
        'record_mapbox_usage',
        params: {
          'p_channel': ExpressRuntimeChannel.name,
          'p_directions_units': directions,
          'p_static_tiles_units': tiles,
        },
      );
      if (raw is Map) {
        _applyQuotaState(Map<String, dynamic>.from(raw));
      }
    } catch (_) {
      // Restoring the batch is conservative. A lost response after a committed
      // RPC can over-count on retry, which only makes fallback happen earlier.
      _pendingDirectionsUnits += directions;
      _pendingStaticTileUnits += tiles;
    } finally {
      _usageFlushInFlight = false;
    }

    if (_pendingDirectionsUnits > 0 || _pendingStaticTileUnits > 0) {
      _scheduleUsageFlush();
    }
  }

  static String _routeCacheKey(LatLng from, LatLng to) {
    String f(double value) => value.toStringAsFixed(5);
    return '${f(from.latitude)},${f(from.longitude)}>'
        '${f(to.latitude)},${f(to.longitude)}';
  }

  static Future<ExpressMapRoute> drivingRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    final key = _routeCacheKey(from, to);
    final cached = _routeCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 3)) {
      return cached.route;
    }

    ExpressMapRoute? route;
    if (canUseMapboxDirections) {
      route = await _mapboxRoute(from: from, to: to);
    }
    route ??= await _osrmRoute(from: from, to: to);
    route ??= ExpressMapRoute(
      points: <LatLng>[from, to],
      provider: 'direct',
    );

    if (_routeCache.length > 96) {
      _routeCache.remove(_routeCache.keys.first);
    }
    _routeCache[key] = _CachedRoute(route, DateTime.now());
    return route;
  }

  static Future<ExpressMapRoute?> _mapboxRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    noteMapboxDirectionRequest();

    try {
      final coordinates =
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
      final uri = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/'
        '$coordinates',
      ).replace(
        queryParameters: <String, String>{
          'overview': 'full',
          'geometries': 'geojson',
          'steps': 'false',
          'access_token': _mapboxToken.trim(),
        },
      );

      final response =
          await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 429) {
        _openDirectionsCircuit(const Duration(minutes: 2));
        return null;
      }
      if (response.statusCode >= 500) {
        _openDirectionsCircuit(const Duration(seconds: 45));
        return null;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        _openDirectionsCircuit(const Duration(minutes: 10));
        return null;
      }
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['routes'] is! List) return null;
      final routes = decoded['routes'] as List;
      if (routes.isEmpty || routes.first is! Map) return null;
      final first = Map<String, dynamic>.from(routes.first as Map);
      final geometry = first['geometry'];
      if (geometry is! Map || geometry['coordinates'] is! List) return null;

      final points = _decodeGeoJsonCoordinates(geometry['coordinates'] as List);
      if (points.length < 2) return null;

      return ExpressMapRoute(
        points: points,
        distanceMeters: (first['distance'] as num?)?.toDouble(),
        durationSeconds: (first['duration'] as num?)?.toDouble(),
        provider: 'mapbox',
      );
    } on TimeoutException {
      _openDirectionsCircuit(const Duration(seconds: 45));
      return null;
    } catch (_) {
      _openDirectionsCircuit(const Duration(seconds: 30));
      return null;
    }
  }

  static Future<ExpressMapRoute?> _osrmRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['routes'] is! List) return null;
      final routes = decoded['routes'] as List;
      if (routes.isEmpty || routes.first is! Map) return null;
      final first = Map<String, dynamic>.from(routes.first as Map);
      final geometry = first['geometry'];
      if (geometry is! Map || geometry['coordinates'] is! List) return null;

      final points = _decodeGeoJsonCoordinates(geometry['coordinates'] as List);
      if (points.length < 2) return null;

      return ExpressMapRoute(
        points: points,
        distanceMeters: (first['distance'] as num?)?.toDouble(),
        durationSeconds: (first['duration'] as num?)?.toDouble(),
        provider: 'osrm',
      );
    } catch (_) {
      return null;
    }
  }

  static List<LatLng> _decodeGeoJsonCoordinates(List rawCoordinates) {
    final points = <LatLng>[];
    for (final raw in rawCoordinates) {
      if (raw is! List || raw.length < 2) continue;
      final lng = (raw[0] as num?)?.toDouble();
      final lat = (raw[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (!lat.isFinite ||
          !lng.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180) {
        continue;
      }
      points.add(LatLng(lat, lng));
    }
    return points;
  }
}

class _MapboxCountingHttpClient extends http.BaseClient {
  final http.Client _inner;

  _MapboxCountingHttpClient(this._inner);

  bool _isMapboxStaticTile(Uri uri) =>
      uri.host == 'api.mapbox.com' &&
      uri.path.contains('/styles/v1/') &&
      uri.path.contains('/tiles/');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final counted = _isMapboxStaticTile(request.url);
    if (counted) {
      ExpressMapProvider.noteMapboxStaticTileRequest();
    }

    try {
      final response = await _inner.send(request);
      if (counted) {
        if (response.statusCode >= 200 && response.statusCode < 400) {
          ExpressMapProvider.noteMapboxTileSuccess();
        } else if (response.statusCode == 401 ||
            response.statusCode == 403 ||
            response.statusCode == 429 ||
            response.statusCode >= 500) {
          ExpressMapProvider.noteMapboxTileFailure();
        }
      }
      return response;
    } catch (_) {
      // A missing network connection is not a Mapbox service failure. Keeping
      // the Mapbox provider selected lets NetworkTileProvider serve the
      // persistent tile cache instead of switching the whole map to OSM.
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
  }
}

class ExpressBaseTileLayer extends StatefulWidget {
  final TileBuilder? tileBuilder;

  const ExpressBaseTileLayer({
    super.key,
    this.tileBuilder,
  });

  @override
  State<ExpressBaseTileLayer> createState() => _ExpressBaseTileLayerState();
}

class _ExpressBaseTileLayerState extends State<ExpressBaseTileLayer> {
  bool? _providerMode;
  NetworkTileProvider? _provider;

  NetworkTileProvider _providerFor(bool mapbox) {
    if (_provider == null || _providerMode != mapbox) {
      _providerMode = mapbox;
      _provider = NetworkTileProvider(
        httpClient: _MapboxCountingHttpClient(http.Client()),
        cachingProvider: ExpressMapProvider.offlineTileCache,
        silenceExceptions: true,
      );
    }
    return _provider!;
  }

  @override
  void dispose() {
    unawaited(ExpressMapProvider.flushPendingUsage());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ExpressMapProvider.useMapboxTiles,
      builder: (context, useMapbox, _) {
        final provider = _providerFor(useMapbox);
        return TileLayer(
          key: ValueKey<String>(useMapbox ? 'mapbox-512' : 'osm-256'),
          urlTemplate: useMapbox
              ? ExpressMapProvider.primaryTileUrl
              : ExpressMapProvider.osmTileUrl,
          tileDimension: useMapbox ? 512 : 256,
          zoomOffset: useMapbox ? -1 : 0,
          maxNativeZoom: useMapbox ? 22 : 19,
          tileProvider: provider,
          tileBuilder: widget.tileBuilder,
          userAgentPackageName: 'com.express.usuario1',
          // HTTP status failures are classified in the counting client.
          // Generic tile errors are usually connectivity loss and must not
          // disable the cached Mapbox layer.
          errorTileCallback: (_, __, ___) {},
        );
      },
    );
  }
}

class _CachedRoute {
  final ExpressMapRoute route;
  final DateTime createdAt;

  const _CachedRoute(this.route, this.createdAt);
}

class ExpressMapAttribution extends StatelessWidget {
  const ExpressMapAttribution({super.key});

  static final Uri _mapboxUri =
      Uri.parse('https://www.mapbox.com/about/maps');
  static final Uri _osmUri =
      Uri.parse('https://www.openstreetmap.org/copyright');
  static final Uri _feedbackUri =
      Uri.parse('https://apps.mapbox.com/feedback/');

  static Future<void> _open(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _osmOnly() => RichAttributionWidget(
        attributions: [
          TextSourceAttribution(
            'OpenStreetMap contributors',
            onTap: () => _open(_osmUri),
          ),
        ],
      );

  Widget _mapbox() => RichAttributionWidget(
        permanentHeight: 34,
        attributions: [
          LogoSourceAttribution(
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Image.network(
                'https://cdn.prod.website-files.com/'
                '6050a76fa6a633d5d54ae714/'
                '657a891ba7274ba4f8b3a168_img-main-logo.png',
                fit: BoxFit.contain,
              ),
            ),
            height: 30,
            tooltip: 'Mapbox',
            onTap: () => _open(_mapboxUri),
          ),
          TextSourceAttribution(
            'Mapbox',
            onTap: () => _open(_mapboxUri),
          ),
          TextSourceAttribution(
            'OpenStreetMap',
            onTap: () => _open(_osmUri),
          ),
          TextSourceAttribution(
            'Improve this map',
            prependCopyright: false,
            onTap: () => _open(_feedbackUri),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ExpressMapProvider.useMapboxTiles,
      builder: (context, useMapbox, _) =>
          useMapbox ? _mapbox() : _osmOnly(),
    );
  }
}
