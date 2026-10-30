import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Stable course, measured clockwise from north. Small GPS drift while stopped
/// must not rotate a vehicle. Keep an anchor until meaningful movement occurs.
class MapVehicleHeading {
  LatLng? _anchor;
  double degrees = 0;

  double update(LatLng point, {double? reportedDegrees, double? speedMps}) {
    final valid =
        reportedDegrees != null &&
        reportedDegrees.isFinite &&
        reportedDegrees >= 0 &&
        reportedDegrees < 360;
    final previous = _anchor;
    if (previous == null) {
      _anchor = point;
      if (valid) degrees = reportedDegrees;
      return degrees;
    }
    final moved = const Distance().as(LengthUnit.Meter, previous, point);
    if (moved < 4 ||
        (speedMps != null &&
            speedMps.isFinite &&
            speedMps >= 0 &&
            speedMps < .8)) {
      return degrees;
    }
    // A stale fix/teleport is not a trustworthy course measurement.
    if (moved > 500) {
      _anchor = point;
      return degrees;
    }
    degrees = valid ? reportedDegrees : bearing(previous, point);
    _anchor = point;
    return degrees;
  }

  static double bearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Accumulate the shortest turn, including crossing 359° -> 1°.
  static double shortestTurn(double previous, double targetDegrees) =>
      previous + ((targetDegrees - previous + 540) % 360 - 180);
}

String expressMapVehicleType(Object? raw, {String? summary}) {
  final type = raw?.toString().trim().toLowerCase() ?? '';
  if (const {
    'motocar',
    'trimoto',
    'tricycle',
    'cargo_tricycle',
  }.contains(type)) {
    return 'motocar';
  }
  if (const {'motorcycle', 'moto', 'mototaxi'}.contains(type)) {
    return 'motorcycle';
  }
  if (const {'car', 'auto', 'xl', 'suv', 'van'}.contains(type)) return 'car';
  final label = summary?.toLowerCase() ?? '';
  if (label.contains('motocar') || label.contains('trimoto')) return 'motocar';
  if (label.contains('moto')) return 'motorcycle';
  // Missing data is explicitly unknown, never mislabeled as a car or moto.
  return 'unknown';
}
