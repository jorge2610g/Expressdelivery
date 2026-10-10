import 'package:expressdelivery/driver_refresh_control.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRefreshScheduler {
  _FakeRefreshScheduler(this.now);

  DateTime now;
  final List<({DateTime at, void Function() task})> _tasks = [];

  void schedule(Duration delay, void Function() task) {
    _tasks.add((at: now.add(delay), task: task));
  }

  void advance(Duration duration) {
    final target = now.add(duration);
    while (true) {
      final due = _tasks.where((task) => !task.at.isAfter(target)).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final next = due.first;
      _tasks.remove(next);
      now = next.at;
      next.task();
    }
    now = target;
  }
}

void main() {
  group('DriverRefreshCoordinator', () {
    late _FakeRefreshScheduler scheduler;
    late DriverRefreshCoordinator coordinator;
    var runs = 0;

    setUp(() {
      runs = 0;
      scheduler = _FakeRefreshScheduler(DateTime.utc(2026, 10, 10, 3, 43));
      coordinator = DriverRefreshCoordinator(
        onRefresh: () => runs++,
        clock: () => scheduler.now,
        schedule: scheduler.schedule,
      );
    });

    test(
      'B1-a: request one second after a refresh runs trailing by two seconds',
      () {
        coordinator.request();
        coordinator.complete(succeeded: true);
        scheduler.advance(const Duration(seconds: 1));
        coordinator.request();

        scheduler.advance(const Duration(milliseconds: 999));
        expect(runs, 1);
        scheduler.advance(const Duration(milliseconds: 1));
        expect(runs, 2);
      },
    );

    test(
      'B1-b: twenty requests in one second produce one immediate and one trailing run',
      () {
        coordinator.request();
        for (var i = 0; i < 20; i++) {
          scheduler.advance(const Duration(milliseconds: 50));
          coordinator.request();
        }
        coordinator.complete(succeeded: true);

        scheduler.advance(const Duration(seconds: 2));
        expect(runs, 2);
      },
    );

    test(
      'B1-c: request during an in-flight refresh repeats exactly once after completion',
      () {
        coordinator.request();
        coordinator.request();
        coordinator.request();
        coordinator.complete(succeeded: true);

        scheduler.advance(const Duration(seconds: 2));
        expect(runs, 2);
        coordinator.complete(succeeded: true);
        scheduler.advance(const Duration(seconds: 3));
        expect(runs, 2);
      },
    );
  });

  group('driverAvailabilityRefreshDecision', () {
    test(
      'B2-a: discards a light result when the full state version changed',
      () {
        expect(
          driverAvailabilityRefreshDecision(
            startedStateVersion: 7,
            currentStateVersion: 8,
            fullRefreshInFlight: false,
            currentStateEligible: true,
          ),
          DriverAvailabilityRefreshDecision.discardAndRequeue,
        );
      },
    );

    test(
      'B2-b: does not apply a stale availability result over a published active trip',
      () {
        expect(
          driverAvailabilityRefreshDecision(
            startedStateVersion: 7,
            currentStateVersion: 8,
            fullRefreshInFlight: false,
            currentStateEligible: false,
          ),
          DriverAvailabilityRefreshDecision.discard,
        );
      },
    );

    test(
      'B2-c: does not apply when the latest profile is offline or has active work',
      () {
        expect(
          driverAvailabilityRefreshDecision(
            startedStateVersion: 7,
            currentStateVersion: 7,
            fullRefreshInFlight: true,
            currentStateEligible: false,
          ),
          DriverAvailabilityRefreshDecision.discard,
        );
      },
    );
  });

  group('driverFullRefreshIsRecent', () {
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
          record: const {'zone_id': 'zone-trinidad', 'channel': 'preview'},
          zoneId: 'zone-trinidad',
          channel: 'preview',
        ),
        isTrue,
      );
    });
    test('rejects a request from another zone', () {
      expect(
        driverRideRequestMatchesScope(
          record: const {'zone_id': 'zone-iquique', 'channel': 'preview'},
          zoneId: 'zone-trinidad',
          channel: 'preview',
        ),
        isFalse,
      );
    });
    test('rejects a request from another runtime channel', () {
      expect(
        driverRideRequestMatchesScope(
          record: const {'zone_id': 'zone-trinidad', 'channel': 'production'},
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
