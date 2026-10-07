import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class ExpressLocationService {
  const ExpressLocationService();

  static const recentCacheMaxAge = Duration(seconds: 45);
  static const recentCacheMaxAccuracyMeters = 100.0;
  static Position? _startupPosition;

  /// Keeps only the current-process startup fix so the passenger Home can
  /// reuse the GPS result obtained behind the splash without a second cold
  /// lookup or any persistent passenger location history.
  static void primeStartupPosition(Position position) {
    _startupPosition = position;
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

  LocationSettings _trackingSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 8,
        intervalDuration: Duration(seconds: 5),
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

    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
    );
  }

  Future<Position> currentPosition({
    bool preferRecent = false,
    bool allowCachedFallback = true,
  }) async {
    await _ensureLocationAccess();

    if (preferRecent) {
      final primed = _startupPosition;
      if (primed != null &&
          isRecentUsablePosition(
            primed,
            maxAge: recentCacheMaxAge,
            maxAccuracyMeters: recentCacheMaxAccuracyMeters,
          )) {
        return primed;
      }
      _startupPosition = null;
    }

    Position? cached;
    try {
      cached = await _lastKnownPosition(
        maxAge: preferRecent
            ? recentCacheMaxAge
            : const Duration(minutes: 10),
        maxAccuracyMeters:
            preferRecent ? recentCacheMaxAccuracyMeters : 250,
      );
    } catch (_) {
      cached = null;
    }

    if (preferRecent && cached != null) {
      _startupPosition = cached;
      return cached;
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
      if (!isUsablePosition(fresh, maxAccuracyMeters: 300)) {
        if (allowCachedFallback && cached != null) return cached;
        throw StateError(
          'La señal GPS es demasiado imprecisa. Muévete a un lugar con mejor señal e intenta nuevamente.',
        );
      }
      _startupPosition = fresh;
      return fresh;
    } catch (_) {
      if (allowCachedFallback && cached != null) return cached;
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

  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: _trackingSettings(),
    );
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
