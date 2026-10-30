import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'map_vehicle_heading.dart';

/// Shared marker for passenger and driver. Artwork points north; rotation stays
/// map-relative so panning/rotating the map does not change geographic heading.
class ExpressMapVehicleMarker extends StatefulWidget {
  final String vehicleType;
  final double? headingDegrees;
  final LatLng? position;
  final bool navigating;
  final double scale;

  const ExpressMapVehicleMarker({
    super.key,
    required this.vehicleType,
    this.headingDegrees,
    this.position,
    this.navigating = false,
    this.scale = 1,
  });

  @override
  State<ExpressMapVehicleMarker> createState() =>
      _ExpressMapVehicleMarkerState();
}

class _ExpressMapVehicleMarkerState extends State<ExpressMapVehicleMarker> {
  final _course = MapVehicleHeading();
  double _angle = 0;

  void _updateCourse() {
    final point = widget.position;
    final raw = widget.headingDegrees;
    final heading = point == null
        ? (raw != null && raw.isFinite && raw >= 0 && raw < 360 ? raw : 0.0)
        : _course.update(point, reportedDegrees: raw);
    _angle = MapVehicleHeading.shortestTurn(_angle, heading);
  }

  @override
  void initState() {
    super.initState();
    _updateCourse();
  }

  @override
  void didUpdateWidget(ExpressMapVehicleMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCourse();
  }

  @override
  Widget build(BuildContext context) {
    final type = expressMapVehicleType(widget.vehicleType);
    final label = switch (type) {
      'motorcycle' => 'Moto',
      'motocar' => 'Motocar',
      'car' => 'Auto',
      _ => 'Vehículo',
    };
    return Semantics(
      label: widget.navigating ? '$label en viaje' : label,
      image: true,
      child: Transform.scale(
        scale: widget.scale,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: _angle, end: _angle),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, angle, child) =>
              Transform.rotate(angle: angle * math.pi / 180, child: child),
          child: widget.navigating
              ? const CustomPaint(
                  size: Size(52, 52),
                  painter: _NavigationArrow(),
                )
              : type == 'unknown'
              ? const Icon(
                  Icons.location_on_rounded,
                  size: 34,
                  color: Color(0xFF0B57D0),
                )
              : Image.asset(
                  'assets/map_markers/$type.png',
                  width: 48,
                  height: 56,
                  fit: BoxFit.contain,
                  cacheWidth: 144,
                  filterQuality: FilterQuality.high,
                ),
        ),
      ),
    );
  }
}

class _NavigationArrow extends CustomPainter {
  const _NavigationArrow();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 52, size.height / 52);
    canvas.drawCircle(
      const Offset(26, 26),
      24,
      Paint()..color = const Color(0x220B57D0),
    );
    final arrow = Path()
      ..moveTo(26, 5)
      ..quadraticBezierTo(27, 5, 28, 8)
      ..lineTo(43, 43)
      ..quadraticBezierTo(44, 47, 40, 45)
      ..lineTo(26, 36)
      ..lineTo(12, 45)
      ..quadraticBezierTo(8, 47, 9, 43)
      ..lineTo(24, 8)
      ..quadraticBezierTo(25, 5, 26, 5)
      ..close();
    canvas.drawShadow(arrow, const Color(0xAA001E4A), 4, false);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      arrow,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF24B6FF), Color(0xFF0753D9)],
        ).createShader(const Rect.fromLTWH(8, 5, 36, 42)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(26, 8)
        ..lineTo(26, 36)
        ..lineTo(40, 45)
        ..close(),
      Paint()..color = const Color(0x55002D8F),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NavigationArrow oldDelegate) => false;
}
