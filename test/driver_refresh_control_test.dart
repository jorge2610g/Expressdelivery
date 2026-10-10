import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/driver_refresh_control.dart';

void main() {
  group('DriverRefreshThrottle', () {
    test('N triggers inside one second produce one accepted refresh', () {
      final throttle = DriverRefreshThrottle();
      final start = DateTime.utc(2026, 10, 10, 3, 43);

      var accepted = 0;
      for (var i = 0; i < 20; i++) {
        final at = start.add(Duration(milliseconds: i * 50));
        if (throttle.accept(at)) accepted++;
      }

      expect(accepted, 1);
      expect(
        throttle.accept(start.add(const Duration(seconds: 2))),
        isTrue,
      );
    });

    test('backup timer skips a full refresh completed less than 12s ago', () {
      final completed = DateTime.utc(2026, 10, 10, 3, 43);

      expect(
        driverFullRefreshIsRecent(
          lastCompletedAt: completed,
          now: completed.add(const Duration(seconds: 11)),
        ),
        isTrue,
      );
      expect(
        driverFullRefreshIsRecent(
          lastCompletedAt: completed,
          now: completed.add(const Duration(seconds: 12)),
        ),
        isFalse,
      );
    });
  });

  group('driverRideRequestMatchesScope', () {
    test('accepts the same zone and runtime channel', () {
      expect(
        driverRideRequestMatchesScope(
          record: const {
            'zone_id': 'zone-trinidad',
            'channel': 'preview',
          },
          zoneId: 'zone-trinidad',
          channel: 'preview',
        ),
        isTrue,
      );
    });

    test('rejects a request from another zone', () {
      expect(
        driverRideRequestMatchesScope(
          record: const {
            'zone_id': 'zone-iquique',
            'channel': 'preview',
          },
          zoneId: 'zone-trinidad',
          channel: 'preview',
        ),
        isFalse,
      );
    });

    test('rejects a request from another runtime channel', () {
      expect(
        driverRideRequestMatchesScope(
          record: const {
            'zone_id': 'zone-trinidad',
            'channel': 'production',
          },
          zoneId: 'zone-trinidad',
          channel: 'preview',
        ),
        isFalse,
      );
    });

    test('rejects sparse oldRecord without zone/channel', () {
      expect(
        driverRideRequestMatchesScope(
          record: const {'id': 'ride-id'},
          zoneId: 'zone-trinidad',
          channel: 'preview',
        ),
        isFalse,
      );
    });
  });
}
