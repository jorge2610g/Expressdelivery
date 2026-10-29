import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:expressdelivery/location_service.dart';

Position _position({
  required DateTime timestamp,
  double latitude = -33.4489,
  double longitude = -70.6693,
  double accuracy = 25,
}) {
  return Position(
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
  );
}

void main() {
  const service = ExpressLocationService();

  test('passenger idle map follow does not request the ongoing location notification', () {
    final settings = service.trackingSettings(
      highFrequency: false,
      foregroundService: false,
    ) as AndroidSettings;

    expect(settings.foregroundNotificationConfig, isNull);
    expect(settings.distanceFilter, 15);
  });

  test('driver tracking keeps the ongoing foreground notification by default', () {
    final settings = service.trackingSettings(highFrequency: true) as AndroidSettings;

    expect(settings.foregroundNotificationConfig, isNotNull);
    expect(settings.foregroundNotificationConfig!.setOngoing, isTrue);
  });

  test('startup cache policy is 45 seconds and 100 meters', () {
    expect(
      ExpressLocationService.recentCacheMaxAge,
      const Duration(seconds: 45),
    );
    expect(ExpressLocationService.recentCacheMaxAccuracyMeters, 100);
  });

  test('accepts a recent accurate cached position', () {
    final now = DateTime.utc(2026, 10, 7, 9);
    final position = _position(
      timestamp: now.subtract(const Duration(seconds: 44)),
      accuracy: 100,
    );

    expect(
      service.isRecentUsablePosition(
        position,
        now: now,
        maxAge: ExpressLocationService.recentCacheMaxAge,
        maxAccuracyMeters:
            ExpressLocationService.recentCacheMaxAccuracyMeters,
      ),
      isTrue,
    );
  });

  test('rejects a cached position older than 45 seconds', () {
    final now = DateTime.utc(2026, 10, 7, 9);
    final position = _position(
      timestamp: now.subtract(const Duration(seconds: 46)),
      accuracy: 20,
    );

    expect(
      service.isRecentUsablePosition(
        position,
        now: now,
        maxAge: ExpressLocationService.recentCacheMaxAge,
        maxAccuracyMeters:
            ExpressLocationService.recentCacheMaxAccuracyMeters,
      ),
      isFalse,
    );
  });

  test('rejects a cached position worse than 100 meters', () {
    final now = DateTime.utc(2026, 10, 7, 9);
    final position = _position(
      timestamp: now.subtract(const Duration(seconds: 10)),
      accuracy: 101,
    );

    expect(
      service.isRecentUsablePosition(
        position,
        now: now,
        maxAge: ExpressLocationService.recentCacheMaxAge,
        maxAccuracyMeters:
            ExpressLocationService.recentCacheMaxAccuracyMeters,
      ),
      isFalse,
    );
  });

  test('rejects invalid coordinates and future timestamps', () {
    final now = DateTime.utc(2026, 10, 7, 9);
    final invalidCoordinates = _position(
      timestamp: now.subtract(const Duration(seconds: 10)),
      latitude: 91,
    );
    final future = _position(
      timestamp: now.add(const Duration(seconds: 1)),
    );

    expect(
      service.isRecentUsablePosition(
        invalidCoordinates,
        now: now,
        maxAge: ExpressLocationService.recentCacheMaxAge,
        maxAccuracyMeters:
            ExpressLocationService.recentCacheMaxAccuracyMeters,
      ),
      isFalse,
    );
    expect(
      service.isRecentUsablePosition(
        future,
        now: now,
        maxAge: ExpressLocationService.recentCacheMaxAge,
        maxAccuracyMeters:
            ExpressLocationService.recentCacheMaxAccuracyMeters,
      ),
      isFalse,
    );
  });
}
