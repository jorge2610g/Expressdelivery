import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Passenger map back/GPS controls sit above the route quote sheet', () {
    // Regression: a full-screen SingleChildScrollView appeared later in the
    // map Stack than the back arrow and swallowed taps on the arrow.
    final source = File('lib/video_style_home.dart').readAsStringSync();
    final chooser = source.indexOf('// The Taxi / Envíos chooser must size');
    final topBar = source.indexOf('if (effectivePassengerOffers.isEmpty)\n'
        '                Positioned(\n'
        '                  top: 10,');
    expect(chooser, greaterThanOrEqualTo(0));
    expect(topBar, greaterThan(chooser),
        reason: 'Map buttons must be painted/hit-tested over the quote scroller');
    final backCallback = source.indexOf('? _backFromPassengerSetup', topBar);
    expect(backCallback, greaterThan(topBar));
    expect(source.indexOf('_locate(resetPickupToGps: true)', topBar),
        greaterThan(topBar));
  });
}
