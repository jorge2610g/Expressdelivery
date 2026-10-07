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

  Future<Position> currentPosition() async {
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

    return Geolocator.getCurrentPosition(
      locationSettings: _singleFixSettings(),
    );
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
