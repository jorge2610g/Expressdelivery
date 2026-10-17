import 'dart:async';

import 'package:expressdelivery/core/account_device_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> seed(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('sign-out clears location, push keys and per-account caches', () async {
    final prefs = await seed({
      'express_last_valid_location_v1': '{"lat":1}',
      'express_processed_push_keys_v1': '["a"]',
      'express_account_bootstrap_v1_uid-a': '{"name":"A"}',
      'express_passenger_landing_v1_uid-a': '{"trip":"x"}',
      accountUidMarkerKey: 'uid-a',
      'express_mapbox_quota_state_v1': '{"used":3}',
      'runtime_config_v1': '{"theme":"x"}',
    });
    var memoryCleared = 0;
    await clearAccountDeviceCaches(clearMemory: () => memoryCleared++);

    expect(prefs.getString('express_last_valid_location_v1'), isNull);
    expect(prefs.getString('express_processed_push_keys_v1'), isNull);
    expect(prefs.getString('express_account_bootstrap_v1_uid-a'), isNull);
    expect(prefs.getString('express_passenger_landing_v1_uid-a'), isNull);
    expect(prefs.getString(accountUidMarkerKey), isNull);
    expect(memoryCleared, 1);
  });

  test('clearing keeps unrelated app settings and the Mapbox quota state', () async {
    final prefs = await seed({
      'express_last_valid_location_v1': '{"lat":1}',
      'express_mapbox_quota_state_v1': '{"used":3}',
      'runtime_config_v1': '{"theme":"x"}',
    });
    await clearAccountDeviceCaches();
    expect(prefs.getString('express_mapbox_quota_state_v1'), '{"used":3}');
    expect(prefs.getString('runtime_config_v1'), '{"theme":"x"}');
  });

  test('switching to another account clears the previous account cache', () async {
    final prefs = await seed({
      'express_last_valid_location_v1': '{"lat":1}',
      'express_account_bootstrap_v1_uid-a': '{"name":"A"}',
      accountUidMarkerKey: 'uid-a',
    });
    var memoryCleared = 0;
    await switchAccountDeviceCachesIfNeeded('uid-b',
        clearMemory: () => memoryCleared++);

    expect(prefs.getString('express_last_valid_location_v1'), isNull);
    expect(prefs.getString('express_account_bootstrap_v1_uid-a'), isNull);
    expect(prefs.getString(accountUidMarkerKey), 'uid-b');
    expect(memoryCleared, 1);
  });

  test('the same account keeps its cache on a repeated sign-in', () async {
    final prefs = await seed({
      'express_last_valid_location_v1': '{"lat":1}',
      accountUidMarkerKey: 'uid-a',
    });
    var memoryCleared = 0;
    await switchAccountDeviceCachesIfNeeded('uid-a',
        clearMemory: () => memoryCleared++);

    expect(prefs.getString('express_last_valid_location_v1'), '{"lat":1}');
    expect(memoryCleared, 0);
  });

  test('a missing user id is a no-op', () async {
    final prefs = await seed({
      'express_last_valid_location_v1': '{"lat":1}',
    });
    await switchAccountDeviceCachesIfNeeded(null);
    await switchAccountDeviceCachesIfNeeded('');
    expect(prefs.getString('express_last_valid_location_v1'), '{"lat":1}');
  });

  test('a device without a marker is treated as unknown and rebuilt', () async {
    final prefs = await seed({
      'express_last_valid_location_v1': '{"lat":1}',
    });
    await switchAccountDeviceCachesIfNeeded('uid-a');
    expect(prefs.getString('express_last_valid_location_v1'), isNull);
    expect(prefs.getString(accountUidMarkerKey), 'uid-a');
  });

  test('a cache read started during a user switch waits and never sees the old account', () async {
    final prefs = await seed({
      'express_last_valid_location_v1': '{"lat":1}',
      accountUidMarkerKey: 'uid-a',
    });
    // Switch starts without being awaited, as on an auth event.
    final pending = switchAccountDeviceCachesIfNeeded('uid-b');
    await awaitAccountDeviceCacheReady();
    expect(prefs.getString('express_last_valid_location_v1'), isNull);
    expect(prefs.getString(accountUidMarkerKey), 'uid-b');
    await pending;
  });

  test('sign-out followed at once by another sign-in keeps the order', () async {
    final prefs = await seed({
      'express_last_valid_location_v1': '{"lat":1}',
      accountUidMarkerKey: 'uid-a',
    });
    unawaited(clearAccountDeviceCaches());
    unawaited(switchAccountDeviceCachesIfNeeded('uid-b'));
    await awaitAccountDeviceCacheReady();
    expect(prefs.getString('express_last_valid_location_v1'), isNull);
    expect(prefs.getString(accountUidMarkerKey), 'uid-b');
  });
}
