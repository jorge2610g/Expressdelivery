import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('driver advance never shows a confirmed status before the server answers', () {
    final source = _read('lib/video_style_home.dart');
    final start = source.indexOf('Future<void> _advanceTrip(');
    final call = source.indexOf('await runExpressStateTransition<void>(', start);
    expect(start, greaterThan(-1));
    expect(call, greaterThan(start));
    // The completion branch applies its state only after advanceTrip returns;
    // the check covers the generic branch, which starts at the PIN/step block.
    final beforeCall = source.substring(source.indexOf('String? pin;', start), call);
    expect(beforeCall.contains('cachedData = '), isFalse,
        reason: 'the optimistic status must be applied only in onSuccess');
    final successIndex = source.indexOf('onSuccess: (_) {', call);
    expect(successIndex, greaterThan(call));
    expect(source.substring(successIndex, successIndex + 1200).contains('cachedData = optimistic'),
        isTrue);
  });

  test('a wallet charge with an unclear outcome blocks the same plan until reload', () {
    final source = _read('lib/driver_subscription_page.dart');
    expect(source.contains('_walletOutcomeUncertain.contains(planId)'), isTrue);
    expect(source.contains('outcomeUncertain = isExpressNetworkFailure(e)'), isTrue);
    expect(source.contains('if (!silent) _walletOutcomeUncertain.clear();'), isTrue);
  });

  test('the wallet balance pre-check has a bounded wait', () {
    final source = _read('lib/driver_subscription_page.dart');
    final start = source.indexOf("'ensure_country_wallet_v2'");
    expect(start, greaterThan(-1));
    expect(source.substring(start, start + 200).contains('timeout(const Duration(seconds: 15))'),
        isTrue);
  });

  test('sign-out and account change clear device caches and in-memory account state', () {
    final mobile = _read('lib/mobile_main.dart');
    final web = _read('lib/web_main.dart');
    for (final source in [mobile, web]) {
      expect(source.contains('clearAccountDeviceCaches(clearMemory: forgetAccountMemory)'),
          isTrue);
      expect(source.contains('switchAccountDeviceCachesIfNeeded('), isTrue);
    }
    expect(mobile.contains('switchAccountDeviceCachesIfNeeded('), isTrue);
    final reset = _read('lib/account_memory_reset.dart');
    expect(reset.contains('resetForAccountChange()'), isTrue);
    expect(reset.contains('forgetInMemoryPosition()'), isTrue);
    expect(reset.contains('forgetPreloadedPassengerState()'), isTrue);
    expect(reset.contains('clearRouteMemory()'), isTrue);
  });

  test('the device cache never removes the Mapbox quota or runtime configuration', () {
    final source = _read('lib/core/account_device_cache.dart');
    expect(source.contains('express_mapbox_quota_state_v1'), isFalse);
    expect(source.contains('runtime_config_v1'), isFalse);
  });
}
