import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Location bootstrap is intentionally patch-safe: the last valid fix can
/// keep Home usable while live GPS/network recovery happens behind the UI.
class ExpressLocationService {
  const ExpressLocationService();

  static const recentCacheMaxAge = Duration(seconds: 45);
  static const recentCacheMaxAccuracyMeters = 100.0;
  static const passiveCacheMaxAge = Duration(minutes: 15);
  static const passiveFreshTimeout = Duration(seconds: 4);
  static const persistentFallbackMaxAge = Duration(days: 30);
  static const _lastLocationKey = 'express_last_valid_location_v1';

  static double get _fallbackAccuracyLimitMeters => kIsWeb ? 15000.0 : 500.0;
  static double get _recentAccuracyLimitMeters => kIsWeb ? 5000.0 : 100.0;
  static double get _cachedAccuracyLimitMeters => kIsWeb ? 10000.0 : 250.0;
  static double get _freshAccuracyLimitMeters => kIsWeb ? 10000.0 : 300.0;
  static Position? _startupPosition;
  static DateTime? _lastPersistedAt;

  /// Keeps the startup fix in memory and also persists the last valid location
  /// locally. The persistent copy is only a device fallback for startup/map
  /// continuity when GPS or connectivity are temporarily unavailable.
  static void primeStartupPosition(Position position) {
    _startupPosition = position;

    final now = DateTime.now().toUtc();
    final lastPersistedAt = _lastPersistedAt;
    if (lastPersistedAt == null ||
        now.difference(lastPersistedAt) >= const Duration(seconds: 30)) {
      _lastPersistedAt = now;
      unawaited(_persistPosition(position));
    }
  }

  static Future<void> _persistPosition(Position position) async {
    if (!const ExpressLocationService().isUsablePosition(
      position,
      maxAccuracyMeters: _fallbackAccuracyLimitMeters,
    )) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_lastLocationKey, <String>[
        position.latitude.toStringAsFixed(8),
        position.longitude.toStringAsFixed(8),
        position.accuracy.toStringAsFixed(2),
        position.timestamp.toUtc().toIso8601String(),
      ]);
    } catch (_) {
      // The location cache is a resilience layer and must never block startup.
    }
  }

  static Future<Position?> _readPersistedPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_lastLocationKey);
      if (raw == null || raw.length < 4) return null;

      final latitude = double.tryParse(raw[0]);
      final longitude = double.tryParse(raw[1]);
      final accuracy = double.tryParse(raw[2]);
      final timestamp = DateTime.tryParse(raw[3])?.toUtc();
      if (latitude == null ||
          longitude == null ||
          accuracy == null ||
          timestamp == null) {
        return null;
      }

      final position = Position(
        longitude: longitude,
        latitude: latitude,
        timestamp: timestamp,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
        isMocked: false,
        hasAccuracy: true,
      );

      final now = DateTime.now().toUtc();
      if (now.difference(timestamp) > persistentFallbackMaxAge ||
          !const ExpressLocationService().isUsablePosition(
            position,
            maxAccuracyMeters: _fallbackAccuracyLimitMeters,
          )) {
        return null;
      }
      return position;
    } catch (_) {
      return null;
    }
  }

  Future<Position?> fallbackPosition() async {
    final primed = _startupPosition;
    if (primed != null &&
        isUsablePosition(primed, maxAccuracyMeters: _fallbackAccuracyLimitMeters)) {
      return primed;
    }

    try {
      final osCached = await Geolocator.getLastKnownPosition();
      if (osCached != null &&
          isRecentUsablePosition(
            osCached,
            maxAge: persistentFallbackMaxAge,
            maxAccuracyMeters: _fallbackAccuracyLimitMeters,
          )) {
        primeStartupPosition(osCached);
        return osCached;
      }
    } catch (_) {}

    final persisted = await _readPersistedPosition();
    if (persisted != null) {
      _startupPosition = persisted;
    }
    return persisted;
  }

  LocationSettings _passiveFixSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        timeLimit: passiveFreshTimeout,
        forceLocationManager: false,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 0,
      timeLimit: passiveFreshTimeout,
    );
  }

  LocationSettings _singleFixSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: Duration(seconds: 1),
        timeLimit: Duration(seconds: 7),
        forceLocationManager: false,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      timeLimit: Duration(seconds: 7),
    );
  }

  LocationSettings _trackingSettings({required bool highFrequency}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: highFrequency
            ? LocationAccuracy.bestForNavigation
            : LocationAccuracy.high,
        distanceFilter: highFrequency ? 0 : 15,
        intervalDuration:
            highFrequency ? const Duration(seconds: 3) : const Duration(seconds: 8),
        forceLocationManager: false,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Express · ubicación activa',
          notificationText:
              'Express mantiene tu ubicación actualizada mientras estás en línea o realizando un viaje.',
          notificationChannelName: 'Ubicación de Express',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    return LocationSettings(
      accuracy:
          highFrequency ? LocationAccuracy.bestForNavigation : LocationAccuracy.high,
      distanceFilter: highFrequency ? 0 : 20,
    );
  }

  /// Returns a local fix only. It never requests a new GPS position and never
  /// touches the backend. This is the preferred source for non-map startup UI.
  Future<Position?> cachedPosition({
    Duration maxAge = passiveCacheMaxAge,
  }) async {
    final primed = _startupPosition;
    if (primed != null &&
        isRecentUsablePosition(
          primed,
          maxAge: maxAge,
          maxAccuracyMeters: _fallbackAccuracyLimitMeters,
        )) {
      return primed;
    }

    try {
      final osCached = await Geolocator.getLastKnownPosition();
      if (osCached != null &&
          isRecentUsablePosition(
            osCached,
            maxAge: maxAge,
            maxAccuracyMeters: _fallbackAccuracyLimitMeters,
          )) {
        primeStartupPosition(osCached);
        return osCached;
      }
    } catch (_) {}

    final persisted = await _readPersistedPosition();
    if (persisted != null &&
        isRecentUsablePosition(
          persisted,
          maxAge: maxAge,
          maxAccuracyMeters: _fallbackAccuracyLimitMeters,
        )) {
      _startupPosition = persisted;
      return persisted;
    }
    return null;
  }

  /// Low-cost location for non-tracking flows. A recent local fix wins; only
  /// when it is stale do we ask the OS for one balanced-power position.
  Future<Position?> passivePosition({
    Duration cacheMaxAge = passiveCacheMaxAge,
  }) async {
    final cached = await cachedPosition(maxAge: cacheMaxAge);
    if (cached != null) return cached;

    try {
      await _ensureLocationAccess();
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: _passiveFixSettings(),
      ).timeout(passiveFreshTimeout + const Duration(seconds: 1));
      if (isUsablePosition(
        fresh,
        maxAccuracyMeters: kIsWeb ? 10000 : 1000,
      )) {
        primeStartupPosition(fresh);
        return fresh;
      }
    } catch (_) {
      // Passive mode must never become a startup blocker.
    }

    return fallbackPosition();
  }

  Future<Position> currentPosition({
    bool preferRecent = false,
    bool allowCachedFallback = true,
  }) async {
    if (preferRecent) {
      final primed = _startupPosition;
      if (primed != null &&
          isRecentUsablePosition(
            primed,
            maxAge: recentCacheMaxAge,
            maxAccuracyMeters:
                kIsWeb ? _recentAccuracyLimitMeters : recentCacheMaxAccuracyMeters,
          )) {
        return primed;
      }
    }

    Position? cached;
    try {
      cached = await _lastKnownPosition(
        maxAge: preferRecent
            ? recentCacheMaxAge
            : const Duration(minutes: 10),
        maxAccuracyMeters: preferRecent
            ? (kIsWeb
                ? _recentAccuracyLimitMeters
                : recentCacheMaxAccuracyMeters)
            : _cachedAccuracyLimitMeters,
      );
    } catch (_) {
      cached = null;
    }

    final persistentFallback =
        allowCachedFallback ? await fallbackPosition() : null;

    if (preferRecent && cached != null) {
      primeStartupPosition(cached);
      return cached;
    }

    try {
      await _ensureLocationAccess();
    } catch (_) {
      if (allowCachedFallback) {
        if (cached != null) return cached;
        if (persistentFallback != null) return persistentFallback;
      }
      rethrow;
    }

    try {
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: _singleFixSettings(),
      ).timeout(
        const Duration(seconds: 9),
        onTimeout: () => throw TimeoutException(
          'La ubicación tardó demasiado en responder.',
          const Duration(seconds: 9),
        ),
      );
      if (!isUsablePosition(
        fresh,
        maxAccuracyMeters: _freshAccuracyLimitMeters,
      )) {
        if (allowCachedFallback) {
          if (cached != null) return cached;
          if (persistentFallback != null) return persistentFallback;
        }
        throw StateError(
          'La señal GPS es demasiado imprecisa. Muévete a un lugar con mejor señal e intenta nuevamente.',
        );
      }
      primeStartupPosition(fresh);
      return fresh;
    } catch (_) {
      if (allowCachedFallback) {
        if (cached != null) return cached;
        if (persistentFallback != null) return persistentFallback;
      }
      rethrow;
    }
  }

  Future<void> _ensureLocationAccess() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError('Activa la ubicación del dispositivo para continuar.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // No aplicamos timeout al diálogo del sistema: el usuario puede necesitar
      // unos segundos para leer y decidir el permiso.
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw StateError('Necesitamos permiso de ubicación para usar el mapa.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'El permiso de ubicación está bloqueado. Habilítalo desde la configuración del dispositivo.',
      );
    }
  }

  Future<Position?> _lastKnownPosition({
    required Duration maxAge,
    required double maxAccuracyMeters,
  }) async {
    final position = await Geolocator.getLastKnownPosition();
    if (position == null ||
        !isRecentUsablePosition(
          position,
          maxAge: maxAge,
          maxAccuracyMeters: maxAccuracyMeters,
        )) {
      return null;
    }
    return position;
  }

  bool isRecentUsablePosition(
    Position position, {
    required Duration maxAge,
    required double maxAccuracyMeters,
    DateTime? now,
    bool allowMocked = true,
  }) {
    if (!isUsablePosition(
      position,
      maxAccuracyMeters: maxAccuracyMeters,
      allowMocked: allowMocked,
    )) {
      return false;
    }

    final referenceTime = (now ?? DateTime.now()).toUtc();
    final age = referenceTime.difference(position.timestamp.toUtc());
    return !age.isNegative && age <= maxAge;
  }

  bool isUsablePosition(
    Position position, {
    double maxAccuracyMeters = 150,
    bool allowMocked = true,
  }) {
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude < -90 ||
        position.latitude > 90 ||
        position.longitude < -180 ||
        position.longitude > 180) {
      return false;
    }

    final accuracy = position.accuracy;
    if (!accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > maxAccuracyMeters) {
      return false;
    }

    if (!allowMocked && position.isMocked) return false;
    return true;
  }

  Stream<Position> positionStream({bool highFrequency = false}) {
    return Geolocator.getPositionStream(
      locationSettings: _trackingSettings(highFrequency: highFrequency),
    ).map((position) {
      primeStartupPosition(position);
      return position;
    });
  }

  double distanceMeters({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    return Geolocator.distanceBetween(
      fromLatitude,
      fromLongitude,
      toLatitude,
      toLongitude,
    );
  }
}
