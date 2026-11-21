import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Los círculos de «conductores están viendo tu solicitud» deben mostrar la
/// foto de perfil actual del conductor, no la foto antigua de su cuenta.
void main() {
  test('el visor usa la foto de perfil autorizada cuando existe', () {
    final src = File('lib/video_style_home.dart').readAsStringSync();
    final start = src.indexOf('class _DriverViewerAvatar');
    final end = src.indexOf('class _ExpiringRideOfferCard', start);
    final block = src.substring(start, end);
    expect(block, contains("viewer['profile_photo_path']"));
    expect(block, contains('ExpressDriverPortrait('));
    expect(block, contains('startsWith(\'\$driverId/\')'));
  });
}
