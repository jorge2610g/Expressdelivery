import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

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

class ExpressMapProvider {
  ExpressMapProvider._();

  static const String _mapboxToken =
      String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');

  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static bool get mapboxConfigured =>
      _mapboxToken.trim().startsWith('pk.');

  static String get primaryTileUrl =>
      tileUrlForToken(_mapboxToken);

  static String? get fallbackTileUrl =>
      mapboxConfigured ? osmTileUrl : null;

  static String tileUrlForToken(String token) {
    final value = token.trim();
    if (!value.startsWith('pk.')) return osmTileUrl;
    return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}'
        '?access_token=${Uri.encodeQueryComponent(value)}';
  }

  static String? fallbackTileUrlForToken(String token) =>
      token.trim().startsWith('pk.') ? osmTileUrl : null;

  static final Map<String, _CachedRoute> _routeCache = <String, _CachedRoute>{};
  static DateTime? _mapboxCircuitOpenUntil;

  static bool get _mapboxAvailableNow {
    if (!mapboxConfigured) return false;
    final until = _mapboxCircuitOpenUntil;
    if (until == null) return true;
    if (DateTime.now().isAfter(until)) {
      _mapboxCircuitOpenUntil = null;
      return true;
    }
    return false;
  }

  static void _openMapboxCircuit(Duration duration) {
    _mapboxCircuitOpenUntil = DateTime.now().add(duration);
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
    if (_mapboxAvailableNow) {
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
        _openMapboxCircuit(const Duration(minutes: 2));
        return null;
      }
      if (response.statusCode >= 500) {
        _openMapboxCircuit(const Duration(seconds: 45));
        return null;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        _openMapboxCircuit(const Duration(minutes: 10));
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
      _openMapboxCircuit(const Duration(seconds: 45));
      return null;
    } catch (_) {
      _openMapboxCircuit(const Duration(seconds: 30));
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

class _CachedRoute {
  final ExpressMapRoute route;
  final DateTime createdAt;

  const _CachedRoute(this.route, this.createdAt);
}


class ExpressMapAttribution extends StatelessWidget {
  const ExpressMapAttribution({super.key});

  static final Uri _mapboxUri = Uri.parse('https://www.mapbox.com/about/maps');
  static final Uri _osmUri =
      Uri.parse('https://www.openstreetmap.org/copyright');
  static final Uri _feedbackUri =
      Uri.parse('https://apps.mapbox.com/feedback/');

  static Future<void> _open(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!ExpressMapProvider.mapboxConfigured) {
      return RichAttributionWidget(
        attributions: [
          TextSourceAttribution(
            'OpenStreetMap contributors',
            onTap: () => _open(_osmUri),
          ),
        ],
      );
    }

    return RichAttributionWidget(
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
  }
}
