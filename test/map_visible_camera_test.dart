import 'dart:io';
import 'dart:ui' show Offset;

import 'package:expressdelivery/map_visible_camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('visibleAreaCenterOffset', () {
    test('no bottom panel: center moves to the middle of the usable area', () {
      // Área útil 80..800 => centro 440; viewport 800 => centro 400.
      final offset = visibleAreaCenterOffset(
        viewportHeight: 800,
        topInset: 80,
        bottomOccludedHeight: 0,
      );
      expect(offset.dx, 0);
      expect(offset.dy, 40);
    });

    test('bottom panel occupies 300 px: point is centered above the panel', () {
      // Área visible 80..500 => centro 290; viewport 800 => centro 400.
      final offset = visibleAreaCenterOffset(
        viewportHeight: 800,
        topInset: 80,
        bottomOccludedHeight: 300,
      );
      expect(offset.dy, -110);
    });

    test('a panel taller than the viewport collapses to the top inset', () {
      final offset = visibleAreaCenterOffset(
        viewportHeight: 800,
        topInset: 80,
        bottomOccludedHeight: 900,
      );
      // Área visible de altura 0 en y=80 => offset = 80 - 400.
      expect(offset.dy, -320);
    });

    test('zero viewport returns no offset', () {
      expect(
        visibleAreaCenterOffset(
          viewportHeight: 0,
          topInset: 80,
          bottomOccludedHeight: 300,
        ),
        Offset.zero,
      );
    });

    test('the offset never moves the point horizontally', () {
      final offset = visibleAreaCenterOffset(
        viewportHeight: 1200,
        topInset: 120,
        bottomOccludedHeight: 500,
      );
      expect(offset.dx, 0);
    });
  });

  group('visibleAreaCenterAlignmentY', () {
    test('matches the offset as a fraction of half the viewport', () {
      // Offset -110 sobre viewport 800 => -110 / 400 = -0.275.
      expect(
        visibleAreaCenterAlignmentY(
          viewportHeight: 800,
          topInset: 80,
          bottomOccludedHeight: 300,
        ),
        closeTo(-0.275, 1e-9),
      );
    });

    test('is clamped to the Alignment range', () {
      expect(
        visibleAreaCenterAlignmentY(
          viewportHeight: 800,
          topInset: 80,
          bottomOccludedHeight: 900,
        ),
        greaterThanOrEqualTo(-1),
      );
    });
  });

  test('passenger and driver maps use the visible-area helper', () {
    final home = File('lib/video_style_home.dart').readAsStringSync();
    expect(home, contains("import 'map_visible_camera.dart';"));
    expect(home, contains('visibleAreaCenterOffset('));
  });
}
