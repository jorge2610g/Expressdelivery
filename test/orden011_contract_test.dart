import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('web and mobile both switch the account cache before the first screen', () {
    final web = _read('lib/web_main.dart');
    final mobile = _read('lib/mobile_main.dart');
    final webRun = web.indexOf('runApp(');
    final mobileRun = mobile.indexOf('runApp(');
    final webSwitch = web.indexOf('switchAccountDeviceCachesIfNeeded(');
    final mobileSwitch = mobile.indexOf('switchAccountDeviceCachesIfNeeded(');
    expect(webSwitch, greaterThan(-1));
    expect(webSwitch, lessThan(webRun));
    expect(mobileSwitch, greaterThan(-1));
    expect(mobileSwitch, lessThan(mobileRun));
  });

  test('every read of device-global cache waits for pending account operations', () {
    final gated = <String, String>{
      'lib/location_service.dart': 'static Future<Position?> _readPersistedPosition',
      'lib/connected_shell.dart': 'Future<Map<String, dynamic>?> _readCachedPassengerLanding',
      'lib/push_notifications_native.dart': 'Future<bool> _claimPushMessage',
    };
    gated.forEach((path, signature) {
      final source = _read(path);
      final start = source.indexOf(signature);
      expect(start, greaterThan(-1), reason: path);
      // Compare the whole function body: a fixed 400-char window breaks as soon
      // as an explanatory comment is added before the gate.
      final bodyEnd = source.indexOf('\n}\n', start);
      final window = source.substring(
        start,
        bodyEnd == -1 ? source.length : bodyEnd,
      );
      expect(window.contains('awaitAccountDeviceCacheReady()'), isTrue, reason: path);
    });
  });

  test('sign-out and sign-in go through the same ordered queue', () {
    final source = _read('lib/core/account_device_cache.dart');
    expect(source.contains('_enqueue(() => _clearNow('), isTrue);
    expect(source.contains('return _enqueue(() async {'), isTrue);
  });

  test('a frozen outgoing layer stops network requests but keeps cache hits', () {
    final source = _read('lib/map_tile_handover.dart');
    expect(source.contains('ExpressFrozenTileImageProvider'), isFalse,
        reason: 'the stub blocked cached tiles on the outgoing layer');
    final freeze = source.indexOf('void freeze()');
    expect(freeze, greaterThan(-1));
    expect(source.substring(freeze, freeze + 200).contains('ownedClient?.close()'), isTrue);
  });

  test('the map does not remount when the theme changes', () {
    final source = _read('lib/video_style_home.dart');
    final start = source.indexOf('Widget _expressMapTileLayer(');
    expect(start, greaterThan(-1));
    expect(source.substring(start, start + 400).contains('ValueKey'), isFalse);
  });

  test('attribution follows the visible source while a handover is pending', () {
    final source = _read('lib/map_tile_handover.dart');
    expect(source.contains('(_outgoingMapbox ?? _activeMapbox) == true'), isTrue);
  });
}
