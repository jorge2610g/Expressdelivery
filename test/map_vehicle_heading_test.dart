import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:expressdelivery/map_vehicle_heading.dart';

void main() {
  test('GPS drift at rest preserves heading, then movement turns east', () {
    final course = MapVehicleHeading();
    course.update(const LatLng(-14.8, -64.9), reportedDegrees: 350);
    expect(
      course.update(const LatLng(-14.800001, -64.9), reportedDegrees: 80),
      350,
    );
    expect(
      course.update(const LatLng(-14.8, -64.8998), reportedDegrees: 90),
      90,
    );
    expect(
      course.update(
        const LatLng(-14.8, -64.8997),
        reportedDegrees: 200,
        speedMps: 0,
      ),
      90,
    );
  });

  test(
    'invalid GPS course uses movement bearing, reverse movement reverses course',
    () {
      final course = MapVehicleHeading();
      course.update(const LatLng(0, 0), reportedDegrees: -1);
      expect(
        course.update(const LatLng(0, .001), reportedDegrees: double.nan),
        closeTo(90, .1),
      );
      expect(
        course.update(const LatLng(0, 0), reportedDegrees: -1),
        closeTo(270, .1),
      );
    },
  );

  test('wraparound takes a two degree turn, not a full revolution', () {
    expect(MapVehicleHeading.shortestTurn(359, 1), 361);
    expect(MapVehicleHeading.shortestTurn(1, 359), -1);
  });

  test('bad teleport does not invent a new course', () {
    final course = MapVehicleHeading();
    course.update(const LatLng(0, 0), reportedDegrees: 45);
    expect(course.update(const LatLng(1, 1), reportedDegrees: 200), 45);
  });

  test(
    'vehicle identity is explicit and Motocar never matches motorcycle fallback',
    () {
      expect(expressMapVehicleType('motorcycle'), 'motorcycle');
      expect(expressMapVehicleType('car'), 'car');
      expect(expressMapVehicleType('xl'), 'car');
      expect(expressMapVehicleType('motocar'), 'motocar');
      expect(expressMapVehicleType(null, summary: 'Motocar verde'), 'motocar');
      expect(expressMapVehicleType(null, summary: 'Moto azul'), 'motorcycle');
      expect(expressMapVehicleType(null), 'unknown');
    },
  );
}
