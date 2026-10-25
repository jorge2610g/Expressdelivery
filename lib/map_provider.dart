import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'map_tile_handover.dart';

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

  // Temporary owner-requested OSM-only trial. This gates all Mapbox requests,
  // including tiles, directions and geocoding, until the owner asks to restore it.
  static const bool mapboxEnabled = false;

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
      mapboxEnabled && _mapboxToken.trim().startsWith('pk.');

  static Future<List<({String label, double latitude, double longitude})>>
  searchAddress({
    required String query,
    required String countryCode,
    required LatLng proximity,
    String city = '',
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 3 || countryCode.trim().length != 2) {
      return const [];
    }
    if (mapboxConfigured) {
      final mapboxQuery = [
        cleanQuery,
        city.trim(),
      ].where((part) => part.isNotEmpty).join(', ');
      final uri =
          Uri.parse(
            'https://api.mapbox.com/geocoding/v5/mapbox.places/'
            '${Uri.encodeComponent(mapboxQuery)}.json',
          ).replace(
        queryParameters: {
          'access_token': _mapboxToken.trim(),
          'autocomplete': 'true',
          'country': countryCode.toLowerCase(),
          'language': 'es',
          'limit': '5',
          'proximity': '${proximity.longitude},${proximity.latitude}',
          'types': 'address,poi,place,locality,neighborhood',
        },
      );
      try {
        final response = await routeHttpClient
            .get(uri)
            .timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final features = decoded is Map ? decoded['features'] : null;
          if (features is List) {
            final results = features
                .whereType<Map>()
                .map((feature) {
                  final center = feature['center'];
                  final coordinates = center is List && center.length >= 2
                      ? center
                      : null;
                  final label = feature['place_name']?.toString().trim() ?? '';
                  final longitude = coordinates == null
                      ? null
                      : double.tryParse(coordinates[0].toString());
                  final latitude = coordinates == null
                      ? null
                      : double.tryParse(coordinates[1].toString());
                  if (label.isEmpty || latitude == null || longitude == null) {
                    return null;
                  }
                  return (
                    label: label,
                    latitude: latitude,
                    longitude: longitude,
                  );
                })
                .whereType<
                  ({String label, double latitude, double longitude})
                >()
                .toList();
            if (results.isNotEmpty) return results;
          }
        }
      } catch (_) {
        // Fall back to OpenStreetMap geocoding below.
      }
    }
    return _searchAddressWithPhoton(
      query: cleanQuery,
      city: city,
      countryCode: countryCode,
      proximity: proximity,
    );
  }

  static Future<List<({String label, double latitude, double longitude})>>
  _searchAddressWithPhoton({
    required String query,
    required String city,
    required String countryCode,
    required LatLng proximity,
  }) async {
    final countryName = switch (countryCode.toUpperCase()) {
      'CL' => 'Chile',
      'BO' => 'Bolivia',
      _ => countryCode.toUpperCase(),
    };
    final queries = <String>{
      if (city.trim().isNotEmpty) '${query.trim()}, ${city.trim()}',
      query.trim(),
    };
    for (final candidate in queries) {
      final uri = Uri.https('photon.komoot.io', '/api/', {
        'q': '$candidate, $countryName',
        'lang': 'es',
        'limit': '5',
        'lat': proximity.latitude.toString(),
        'lon': proximity.longitude.toString(),
      });
      try {
        final response = await routeHttpClient
            .get(uri, headers: const {'Accept-Language': 'es'})
            .timeout(const Duration(seconds: 7));
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        final features = decoded is Map ? decoded['features'] : null;
        if (features is! List) continue;
        final results = features
            .whereType<Map>()
            .map((feature) {
              final properties = feature['properties'];
              final geometry = feature['geometry'];
              final coordinates = geometry is Map
                  ? geometry['coordinates']
                  : null;
              if (properties is! Map ||
                  coordinates is! List ||
                  coordinates.length < 2) {
                return null;
              }
              final resultCountry = properties['countrycode']
                  ?.toString()
                  .toUpperCase();
              if (resultCountry != null &&
                  resultCountry != countryCode.toUpperCase()) {
                return null;
              }
              final parts = <String>{
                for (final key in [
                  'name',
                  'housenumber',
                  'street',
                  'city',
                  'state',
                  'country',
                ])
                  if ((properties[key]?.toString().trim() ?? '').isNotEmpty)
                    properties[key].toString().trim(),
              };
              final longitude = double.tryParse(coordinates[0].toString());
              final latitude = double.tryParse(coordinates[1].toString());
              if (parts.isEmpty || latitude == null || longitude == null) {
                return null;
              }
              return (
                label: parts.join(', '),
                latitude: latitude,
                longitude: longitude,
              );
            })
            .whereType<({String label, double latitude, double longitude})>()
            .toList();
        if (results.isNotEmpty) return results;
      } catch (_) {
        // Try the less specific query before reporting no matches.
      }
    }
    return const [];
  }

  static Future<String?> reverseGeocodeCountryCode({
    required LatLng point,
  }) async {
    final uri = Uri.https('photon.komoot.io', '/reverse', {
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
      'lang': 'es',
    });
    try {
      final response = await routeHttpClient
          .get(uri, headers: const {'Accept-Language': 'es'})
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      final features = decoded is Map ? decoded['features'] : null;
      if (features is! List || features.isEmpty || features.first is! Map) {
        return null;
      }
      final properties = (features.first as Map)['properties'];
      if (properties is! Map) return null;
      final code = properties['countrycode']?.toString().trim().toUpperCase();
      return code != null && code.length == 2 ? code : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> reverseGeocode({
    required LatLng point,
    required String countryCode,
  }) async {
    final normalizedCountry = countryCode.trim();
    if (normalizedCountry.length != 2) return null;
    return reverseGeocodeLocationLabel(
      point: point,
      countryCode: normalizedCountry,
    );
  }

  /// Resuelve una etiqueta legible del punto, aunque todavía no pertenezca a
  /// una zona. El código de país permite limitar la búsqueda cuando existe.
  static Future<String?> reverseGeocodeLocationLabel({
    required LatLng point,
    String? countryCode,
  }) async {
    final normalizedCountry = countryCode?.trim().toUpperCase();
    if (normalizedCountry != null && normalizedCountry.length != 2) {
      return null;
    }
    if (mapboxConfigured) {
      final coordinate = '${point.longitude},${point.latitude}';
      final query = <String, String>{
        'access_token': _mapboxToken.trim(),
        'language': 'es',
        'limit': '1',
        'types': 'address,poi,place,locality,neighborhood,region,country',
      };
      if (normalizedCountry != null) {
        query['country'] = normalizedCountry.toLowerCase();
      }
      final uri = Uri.https(
        'api.mapbox.com',
        '/geocoding/v5/mapbox.places/$coordinate.json',
        query,
      );
      try {
        final response = await routeHttpClient
            .get(uri)
            .timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final features = decoded is Map ? decoded['features'] : null;
          if (features is List &&
              features.isNotEmpty &&
              features.first is Map) {
            final label = (features.first as Map)['place_name']
                ?.toString()
                .trim();
            if (label != null && label.isNotEmpty) return label;
          }
        }
      } catch (_) {
        // Fall back to OpenStreetMap reverse geocoding below.
      }
    }
    final uri = Uri.https('photon.komoot.io', '/reverse', {
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
      'lang': 'es',
    });
    try {
      final response = await routeHttpClient
          .get(uri, headers: const {'Accept-Language': 'es'})
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      final features = decoded is Map ? decoded['features'] : null;
      if (features is! List || features.isEmpty || features.first is! Map) {
        return null;
      }
      final properties = (features.first as Map)['properties'];
      if (properties is! Map) return null;
      final resultCountry = properties['countrycode']?.toString().toUpperCase();
      if (normalizedCountry != null &&
          resultCountry != null &&
          resultCountry != normalizedCountry) {
        return null;
      }
      final street = [
        properties['housenumber']?.toString().trim(),
        properties['street']?.toString().trim(),
      ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
      final parts = <String>{
        if ((properties['name']?.toString().trim() ?? '').isNotEmpty)
          properties['name'].toString().trim(),
        if (street.isNotEmpty) street,
        for (final key in [
          'city',
          'town',
          'village',
          'locality',
          'district',
          'state',
          'country',
        ])
          if ((properties[key]?.toString().trim() ?? '').isNotEmpty)
            properties[key].toString().trim(),
      };
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  }

  static final ValueNotifier<ExpressMapQuotaState> quota =
      ValueNotifier<ExpressMapQuotaState>(
    const ExpressMapQuotaState.safeFallback(),
  );

  static final ValueNotifier<bool> useMapboxTiles =
      ValueNotifier<bool>(false);

  /// Atribución que sigue a las teselas en pantalla, no al valor objetivo.
  static final ValueNotifier<bool> attributionUsesMapbox =
      ValueNotifier<bool>(false);

  static final Map<String, _CachedRoute> _routeCache =
      <String, _CachedRoute>{};

  /// Borra rutas en memoria al cambiar de cuenta. La caché de teselas no
  /// contiene datos personales y se conserva.
  static void clearRouteMemory() {
    _routeCache.clear();
    _routeInFlight.clear();
  }

  // Peticiones de ruta en vuelo por clave: un doble toque o dos pantallas que
  // piden la misma ruta comparten una sola solicitud de red.
  static final Map<String, Future<ExpressMapRoute>> _routeInFlight =
      <String, Future<ExpressMapRoute>>{};

  /// Cliente HTTP de rutas. Solo las pruebas lo sustituyen.
  @visibleForTesting
  static http.Client routeHttpClient = http.Client();

  static DateTime? _directionsCircuitOpenUntil;
  static DateTime? _tilesCircuitOpenUntil;
  static Timer? _directionsCircuitTimer;
  static Timer? _tilesCircuitTimer;
  static int _consecutiveTileFailures = 0;
  static DateTime? _tileFailureWindowStart;

  // Parallel tile requests can fail in a single short network hiccup.
  // Three failures used to replace the ENTIRE map layer immediately.
  static const int mapboxTileFailureThreshold = 8;
  static const Duration mapboxTileFailureWindow =
      Duration(seconds: 30);


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
    return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}{r}'
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
        query: query.isEmpty ? '' : Uri(queryParameters: query).query,
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

    // Restore a recent decision before waiting for a backend round-trip.
    // Otherwise every app open starts on OSM, then destroys those tiles
    // and paints a blank Mapbox layer when the quota RPC finishes.
    final cached = await _readCachedQuotaState();
    if (cached != null && !quota.value.loaded) {
      _applyQuotaState(cached, persist: false);
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

    // On a temporary network failure keep the already valid map provider.
    // Switching to OSM just because a quota refresh failed caused flicker.
    if (quota.value.loaded) return;
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
      _tileFailureWindowStart = null;
      _syncEffectiveTileProvider();
    });
  }

  static void noteMapboxTileFailure() {
    final now = DateTime.now();
    if (_tileFailureWindowStart == null ||
        now.difference(_tileFailureWindowStart!) > mapboxTileFailureWindow) {
      _tileFailureWindowStart = now;
      _consecutiveTileFailures = 0;
    }
    ++_consecutiveTileFailures;
    if (_consecutiveTileFailures >= mapboxTileFailureThreshold) {
      _consecutiveTileFailures = 0;
      _tileFailureWindowStart = null;
      _openTilesCircuit(const Duration(minutes: 2));
    }
  }

  static void noteMapboxTileSuccess() {
    _consecutiveTileFailures = 0;
    _tileFailureWindowStart = null;
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
  }) {
    final key = _routeCacheKey(from, to);
    final cached = _routeCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 3)) {
      return Future<ExpressMapRoute>.value(cached.route);
    }

    final pending = _routeInFlight[key];
    if (pending != null) return pending;

    final request = _fetchDrivingRoute(key: key, from: from, to: to);
    _routeInFlight[key] = request;
    request.whenComplete(() {
      _routeInFlight.remove(key);
    }).ignore();
    return request;
  }

  static Future<ExpressMapRoute> _fetchDrivingRoute({
    required String key,
    required LatLng from,
    required LatLng to,
  }) async {
    ExpressMapRoute? route;
    if (canUseMapboxDirections) {
      route = await _mapboxRoute(from: from, to: to);
    }
    route ??= await _osrmRoute(from: from, to: to);
    if (route == null) {
      // Línea recta solo para dibujar un trazo de respaldo. No se cachea: si se
      // guardara, ocultaría una ruta real que el servidor devuelva después.
      return ExpressMapRoute(
        points: <LatLng>[from, to],
        provider: 'direct',
      );
    }

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
          await routeHttpClient.get(uri).timeout(const Duration(seconds: 4));
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
          await routeHttpClient.get(uri).timeout(const Duration(seconds: 4));
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
  // EXPRESS_DIAG temporal: contador de peticiones de tesela, sin URL.
  static int _diagSends = 0;
  final http.Client _inner;

  _MapboxCountingHttpClient(this._inner);

  bool _isMapboxStaticTile(Uri uri) =>
      uri.host == 'api.mapbox.com' &&
      uri.path.contains('/styles/v1/') &&
      uri.path.contains('/tiles/');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _diagSends++;
    if (_diagSends <= 3 || _diagSends % 25 == 0) {
      debugPrint('[EXPRESS_DIAG] tile_http_send n=$_diagSends');
    }
    final counted = _isMapboxStaticTile(request.url);
    if (counted) {
      ExpressMapProvider.noteMapboxStaticTileRequest();
    }

    try {
      final response = await _inner.send(request);
      // EXPRESS_DIAG temporal: solo códigos de error, sin URL.
      if (response.statusCode >= 400) {
        debugPrint('[EXPRESS_DIAG] tile_http status=${response.statusCode} counted=$counted');
      }
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
    } catch (error) {
      // EXPRESS_DIAG temporal: NetworkTileProvider silencia la excepción y
      // deja una tesela transparente; aquí queda constancia del tipo.
      debugPrint('[EXPRESS_DIAG] tile_http_error ${error.runtimeType}');
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

class _TileLayerSpec {
  const _TileLayerSpec({
    required this.mapbox,
    required this.generation,
    required this.provider,
  });

  final bool mapbox;
  final int generation;
  final ExpressHandoverTileProvider provider;
}

class _ExpressBaseTileLayerState extends State<ExpressBaseTileLayer> {
  // Mantiene visible el mapa anterior hasta que la nueva fuente entrega su
  // primer mosaico real. No hay temporizador ni retirada a ciegas: el mapa
  // nunca se queda en blanco por un cambio de cuota o de fuente.
  final TileHandoverController _handover = TileHandoverController();
  _TileLayerSpec? _active;
  _TileLayerSpec? _outgoing;
  bool _built = false;

  @override
  void initState() {
    super.initState();
    _handover.addListener(_onHandoverChanged);
    ExpressMapProvider.useMapboxTiles.addListener(_onModeChanged);
    _onModeChanged();
  }

  @override
  void dispose() {
    _coldStartTimer?.cancel();
    ExpressMapProvider.useMapboxTiles.removeListener(_onModeChanged);
    _handover.removeListener(_onHandoverChanged);
    _handover.dispose();
    unawaited(ExpressMapProvider.flushPendingUsage());
    super.dispose();
  }

  // Respaldo local a OSM cuando Mapbox no entrega ninguna tesela en un
  // arranque en frío. Se limpia cuando cambia la decisión de cuota.
  bool _osmFallback = false;
  Timer? _coldStartTimer;
  int _lastRealGeneration = -1;

  void _onModeChanged() {
    _osmFallback = false;
    _applyMode(ExpressMapProvider.useMapboxTiles.value);
  }

  void _applyMode(bool requestedMapbox) {
    final mapbox = requestedMapbox && !_osmFallback;
    final previous = _active;
    final generation = _handover.begin(mapbox);
    // EXPRESS_DIAG temporal: sin URL, token ni coordenadas.
    debugPrint('[EXPRESS_DIAG] tile_layer_apply mapbox=$mapbox generation=$generation previous=${previous != null} pending=${_handover.handoverPending}');
    if (generation == null) return;
    _coldStartTimer?.cancel();
    _coldStartTimer = null;

    // La capa saliente deja de pedir teselas, pero conserva las ya visibles.
    if (previous != null) previous.provider.freeze();
    _outgoing ??= previous;
    _active = _TileLayerSpec(
      mapbox: mapbox,
      generation: generation,
      provider: _newTileProvider(mapbox: mapbox, generation: generation),
    );
    if (_built) setState(() {});
    if (mapbox && _outgoing == null) {
      _coldStartTimer = Timer(mapboxColdStartFallbackDelay, () {
        if (!mounted) return;
        if (!coldStartNeedsOsmFallback(
          mapboxActive: true,
          outgoingVisible: _outgoing != null,
          realTileSeen: _lastRealGeneration == generation,
        )) {
          return;
        }
        _osmFallback = true;
        // La capa de Mapbox nunca se mostró: se descarta sin relevo.
        final fallbackGeneration = _handover.beginWithoutOutgoing(false);
        _active = _TileLayerSpec(
          mapbox: false,
          generation: fallbackGeneration,
          provider: _newTileProvider(
            mapbox: false,
            generation: fallbackGeneration,
          ),
        );
        _outgoing = null;
        setState(() {});
      });
    }
  }

  ExpressHandoverTileProvider _newTileProvider({
    required bool mapbox,
    required int generation,
  }) {
    final countedClient = _MapboxCountingHttpClient(http.Client());
    // A brief 5xx from either tile host should not become a transparent tile.
    // 429 is deliberately excluded so we respect provider rate limits.
    final ownedClient = RetryClient(
      countedClient,
      retries: 2,
      when: (response) => const {500, 502, 503, 504}.contains(
        response.statusCode,
      ),
      whenError: (error, _) => error is http.ClientException,
      delay: (retryCount) => Duration(milliseconds: 400 * (retryCount + 1)),
    );
    return ExpressHandoverTileProvider(
      httpClient: ownedClient,
      ownedClient: ownedClient,
      cachingProvider: ExpressMapProvider.offlineTileCache,
      onRealTile: () => _onRealTile(generation),
    );
  }

  void _onRealTile(int generation) {
    _lastRealGeneration = generation;
    debugPrint('[EXPRESS_DIAG] tile_real generation=$generation');
    // La imagen puede resolverse de forma síncrona durante el build: se
    // difiere para no notificar cambios de estado dentro de la construcción.
    scheduleMicrotask(() {
      if (mounted) _handover.onRealTile(generation);
    });
  }

  void _onHandoverChanged() {
    final mapbox = _handover.attributionIsMapbox;
    scheduleMicrotask(() {
      ExpressMapProvider.attributionUsesMapbox.value = mapbox;
    });
    if (!_handover.handoverPending) _outgoing = null;
    if (_built && mounted) setState(() {});
  }

  Widget _tileLayer(BuildContext context, _TileLayerSpec spec) {
    final mapbox = spec.mapbox;
    return TileLayer(
      key: ValueKey<String>('tiles-${spec.generation}'),
      urlTemplate: mapbox
          ? ExpressMapProvider.primaryTileUrl
          : ExpressMapProvider.osmTileUrl,
      // Mapbox can return a failed tile (shown by flutter_map as a large
      // grey tile with a diagonal cross) before its quota circuit switches
      // providers. Retry that same tile against OSM immediately so every
      // Express map, including checkout and order tracking, stays readable.
      fallbackUrl: mapbox ? ExpressMapProvider.fallbackTileUrl : null,
      tileDimension: mapbox ? 512 : 256,
      zoomOffset: mapbox ? -1 : 0,
      // Use Mapbox's native @2x images only on high density displays.
      // Never simulate Retina on OSM: that quadruples tile requests.
      retinaMode: mapbox && MediaQuery.devicePixelRatioOf(context) >= 1.5,
      maxNativeZoom: mapbox ? 22 : 19,
      keepBuffer: 5,
      panBuffer: 1,
      // Fade replacement tiles in while the previous zoom remains underneath.
      tileDisplay: const TileDisplay.fadeIn(
        duration: Duration(milliseconds: 140),
      ),
      tileProvider: spec.provider,
      tileBuilder: widget.tileBuilder,
      userAgentPackageName: 'com.express.usuario1',
      // HTTP status failures are classified in the counting client.
      // Generic tile errors are usually connectivity loss and must not
      // disable the cached Mapbox layer.
      errorTileCallback: (_, __, ___) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    _built = true;
    final outgoing = _outgoing;
    final active = _active!;
    return Stack(
      children: <Widget>[
        if (outgoing != null) _tileLayer(context, outgoing),
        _tileLayer(context, active),
      ],
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
      valueListenable: ExpressMapProvider.attributionUsesMapbox,
      builder: (context, useMapbox, _) =>
          useMapbox ? _mapbox() : _osmOnly(),
    );
  }
}
