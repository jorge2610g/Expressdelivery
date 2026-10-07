import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class ExpressLocationService {
  const ExpressLocationService();

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
        distanceFilter: 5,
        intervalDuration: Duration(seconds: 3),
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
    Duration cachedMaxAge = const Duration(seconds: 45),
    double cachedMaxAccuracyMeters = 100,
  }) {
    return _currentPosition(
      cachedMaxAge: cachedMaxAge,
      cachedMaxAccuracyMeters: cachedMaxAccuracyMeters,
    ).timeout(
      const Duration(seconds: 9),
      onTimeout: () => throw TimeoutException(
        'La ubicación tardó demasiado en responder.',
        const Duration(seconds: 9),
      ),
    );
  }

  Future<Position> _currentPosition({
    required Duration cachedMaxAge,
    required double cachedMaxAccuracyMeters,
  }) async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError('Activa la ubicación del dispositivo para continuar.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
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

    // A recent, accurate fix avoids a cold GPS wait on first screen/open.
    // It stays in device memory managed by the OS; Express does not persist a
    // separate passenger location cache.
    final cached = await Geolocator.getLastKnownPosition();
    if (_isUsableCachedPosition(
      cached,
      maxAge: cachedMaxAge,
      maxAccuracyMeters: cachedMaxAccuracyMeters,
    )) {
      return cached!;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: _singleFixSettings(),
    );
  }

  bool _isUsableCachedPosition(
    Position? position, {
    required Duration maxAge,
    required double maxAccuracyMeters,
  }) {
    if (position == null) return false;
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      return false;
    }
    if (position.latitude < -90 ||
        position.latitude > 90 ||
        position.longitude < -180 ||
        position.longitude > 180) {
      return false;
    }
    if (!position.accuracy.isFinite ||
        position.accuracy < 0 ||
        position.accuracy > maxAccuracyMeters) {
      return false;
    }

    final age = DateTime.now().toUtc().difference(position.timestamp.toUtc());
    if (age.isNegative) return false;
    return age <= maxAge;
  }

  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: _trackingSettings(),
    );
  }

  @visibleForTesting
  bool isUsableCachedPositionForTest(
    Position? position, {
    Duration maxAge = const Duration(seconds: 45),
    double maxAccuracyMeters = 100,
  }) {
    return _isUsableCachedPosition(
      position,
      maxAge: maxAge,
      maxAccuracyMeters: maxAccuracyMeters,
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
