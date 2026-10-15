import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source-contract tests for ORDEN 009. The overlays and guards live inside
// large State classes with Supabase and Mapbox dependencies, so these checks
// lock in the visual and safety decisions at the source level.
void main() {
  late String home;

  setUpAll(() {
    home = File('lib/video_style_home.dart').readAsStringSync();
  });

  test('no full-screen darkening layer remains on the map screens', () {
    expect(home, isNot(contains('color: const Color(0x52000000)')),
        reason: 'transition scrim (32%) was removed');
    expect(home, isNot(contains('color: const Color(0x73000000)')),
        reason: 'driver offer scrim (45%) was removed');
    expect(home, isNot(contains('color: Colors.black.withValues(alpha: .38)')),
        reason: 'earnings summary scrim was removed');
  });

  test('the offer-wait card no longer absorbs map taps', () {
    final start = home.indexOf('class _DriverOfferWaitingOverlay');
    final end = home.indexOf('\n}\n', start);
    final body = home.substring(start, end);
    expect(body, isNot(contains('AbsorbPointer(')));
    expect(body, contains('IgnorePointer('));
    expect(body, contains('Alignment.bottomCenter'));
  });

  test('the transition indicator sits at the top without absorbing taps', () {
    final start = home.indexOf('class _ExpressTransitionOverlay');
    final end = home.indexOf('\n}\n', start);
    final body = home.substring(start, end);
    expect(body, contains('IgnorePointer('));
    expect(body, contains('Alignment.topCenter'));
    expect(body, isNot(contains('color: const Color(0x52000000)')));
  });

  test('both map screens show the offline banner above the map', () {
    final occurrences = RegExp('const ExpressOfflineBanner\\(\\)').allMatches(home).length;
    expect(occurrences, 2);
  });

  test('critical actions are blocked while offline', () {
    expect(home, contains('if (_expressOfflineBlocked(context)) return;'));
    expect(RegExp('_expressOfflineBlocked\\(context\\)').allMatches(home).length,
        greaterThanOrEqualTo(3),
        reason: 'the three guarded entry points');
    expect(home, contains('Future<void> _selectOffer('));
    expect(home, contains('Future<void> _advanceTrip('));
    expect(home, contains('Future<void> _createServiceBody('));
  });

  test('both home screens probe connectivity and record refresh outcomes', () {
    expect(
      RegExp('ExpressConnectivityMonitor.instance.probe =').allMatches(home).length,
      2,
    );
    expect(home, contains("recordSuccess('passenger_home')"));
    expect(home, contains("recordSuccess('driver_home')"));
    expect(home, contains('recordFailure(error)'));
  });

  test('tile layers hand over only after a real tile is ready', () {
    final provider = File('lib/map_provider.dart').readAsStringSync();
    expect(provider, isNot(contains('AnimatedSwitcher(')),
        reason: 'the fixed 900 ms switcher dropped the old layer blindly');
    expect(provider, contains('TileHandoverController()'));
    expect(provider, contains('previous.provider.freeze()'));
    expect(provider, contains('ExpressMapProvider.attributionUsesMapbox'));
  });
}
