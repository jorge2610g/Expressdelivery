import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:express_delivery/location_service.dart';

Position position({
  required DateTime timestamp,
  double latitude = -33.45,
  double longitude = -70.66,
  double accuracy = 20,
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
  );
}

void main() {
  const service = ExpressLocationService();

  test('accepts only a recent accurate OS location fix', () {
    final recent = position(
      timestamp: DateTime.now().toUtc().subtract(const Duration(seconds: 10)),
    );
    expect(service.isUsableCachedPositionForTest(recent), isTrue);
  });

  test('rejects stale or inaccurate cached locations', () {
    final stale = position(
      timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
    );
    final inaccurate = position(
      timestamp: DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
      accuracy: 250,
    );

    expect(service.isUsableCachedPositionForTest(stale), isFalse);
    expect(service.isUsableCachedPositionForTest(inaccurate), isFalse);
  });

  test('rejects invalid coordinates', () {
    final invalid = position(
      timestamp: DateTime.now().toUtc(),
      latitude: 95,
    );
    expect(service.isUsableCachedPositionForTest(invalid), isFalse);
  });
}
