import 'dart:async';

import 'package:expressdelivery/offline_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeTimer implements Timer {
  _FakeTimer(this.callback);
  final void Function() callback;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

class _Harness {
  _Harness() {
    monitor = ExpressConnectivityMonitor(
      scheduler: (delay, callback) {
        final timer = _FakeTimer(callback);
        scheduled.add(_Scheduled(delay, timer));
        return timer;
      },
      clock: () => now,
    );
  }

  late final ExpressConnectivityMonitor monitor;
  final List<_Scheduled> scheduled = <_Scheduled>[];
  DateTime now = DateTime.utc(2026, 10, 15, 12);
}

class _Scheduled {
  _Scheduled(this.delay, this.timer);
  final Duration delay;
  final _FakeTimer timer;
}

void main() {
  group('isExpressNetworkFailure', () {
    test('timeouts and HTTP client failures are network failures', () {
      expect(isExpressNetworkFailure(TimeoutException('t')), isTrue);
      expect(isExpressNetworkFailure(http.ClientException('no route')), isTrue);
    });

    test('server data errors are not network failures', () {
      expect(isExpressNetworkFailure(StateError('bad state')), isFalse);
      expect(isExpressNetworkFailure(Exception('postgres 23505')), isFalse);
    });
  });

  test('one network failure moves to reconnecting, three to offline', () {
    final h = _Harness();
    h.monitor.recordFailure(http.ClientException('x'));
    expect(h.monitor.state, ExpressConnectionState.reconnecting);
    h.monitor.recordFailure(http.ClientException('x'));
    expect(h.monitor.state, ExpressConnectionState.reconnecting);
    h.monitor.recordFailure(http.ClientException('x'));
    expect(h.monitor.state, ExpressConnectionState.offline);
  });

  test('a non-network error does not change the connection state', () {
    final h = _Harness();
    h.monitor.recordFailure(StateError('server said no'));
    expect(h.monitor.state, ExpressConnectionState.online);
    expect(h.scheduled, isEmpty);
  });

  test('a successful read restores online and resets the failure count', () {
    final h = _Harness();
    for (var i = 0; i < 3; i++) {
      h.monitor.recordFailure(http.ClientException('x'));
    }
    expect(h.monitor.state, ExpressConnectionState.offline);
    h.monitor.recordSuccess('passenger_home');
    expect(h.monitor.state, ExpressConnectionState.online);
    // After recovery it takes three new failures to go offline again.
    h.monitor.recordFailure(http.ClientException('x'));
    expect(h.monitor.state, ExpressConnectionState.reconnecting);
  });

  test('lastValidAt is set only by successful reads, never by failures', () {
    final h = _Harness();
    h.monitor.recordFailure(http.ClientException('x'));
    expect(h.monitor.lastValidAt('passenger_home'), isNull);
    h.monitor.recordSuccess('passenger_home');
    expect(h.monitor.lastValidAt('passenger_home'), h.now);
  });

  test('backoff grows 2, 4, 8, 16 and then stays at 30 seconds', () {
    final h = _Harness();
    for (var i = 0; i < 7; i++) {
      h.monitor.recordFailure(http.ClientException('x'));
    }
    final delays = h.scheduled.map((s) => s.delay.inSeconds).toList();
    expect(delays, <int>[2, 4, 8, 16, 30, 30, 30]);
  });

  test('a new failure cancels the pending probe and reschedules it', () {
    final h = _Harness();
    h.monitor.recordFailure(http.ClientException('x'));
    h.monitor.recordFailure(http.ClientException('x'));
    expect(h.scheduled[0].timer.cancelled, isTrue);
    expect(h.scheduled[1].timer.cancelled, isFalse);
  });

  test('a successful probe restores online', () async {
    final h = _Harness();
    h.monitor.probe = () async {};
    h.monitor.recordFailure(http.ClientException('x'));
    await h.monitor.probeNow();
    expect(h.monitor.state, ExpressConnectionState.online);
    expect(h.monitor.lastValidAt('probe'), h.now);
  });

  test('a failing probe keeps the connection offline and schedules again', () async {
    final h = _Harness();
    h.monitor.probe = () async => throw http.ClientException('still down');
    for (var i = 0; i < 3; i++) {
      h.monitor.recordFailure(http.ClientException('x'));
    }
    final before = h.scheduled.length;
    await h.monitor.probeNow();
    expect(h.monitor.state, ExpressConnectionState.offline);
    expect(h.scheduled.length, greaterThan(before));
  });

  test('a probe that reaches the server with a data error counts as online', () async {
    final h = _Harness();
    h.monitor.probe = () async => throw StateError('server answered');
    h.monitor.recordFailure(http.ClientException('x'));
    await h.monitor.probeNow();
    expect(h.monitor.state, ExpressConnectionState.online);
  });

  test('returning to the foreground probes immediately when not online', () async {
    final h = _Harness();
    var probes = 0;
    h.monitor.probe = () async => probes++;
    h.monitor.recordFailure(http.ClientException('x'));
    h.monitor.onAppResumed();
    await Future<void>.delayed(Duration.zero);
    expect(probes, 1);
  });

  test('returning to the foreground does nothing when already online', () async {
    final h = _Harness();
    var probes = 0;
    h.monitor.probe = () async => probes++;
    h.monitor.onAppResumed();
    await Future<void>.delayed(Duration.zero);
    expect(probes, 0);
  });

  test('listeners hear only real state changes', () {
    final h = _Harness();
    var notified = 0;
    h.monitor.addListener(() => notified++);
    h.monitor.recordFailure(http.ClientException('x'));
    h.monitor.recordFailure(http.ClientException('x'));
    h.monitor.recordFailure(http.ClientException('x'));
    expect(notified, 2); // online→reconnecting, reconnecting→offline
  });

  test('freshness label describes the age of saved data', () {
    final saved = DateTime.utc(2026, 10, 15, 12);
    expect(expressFreshnessLabel(saved, saved.add(const Duration(seconds: 20))),
        'hace un momento');
    expect(expressFreshnessLabel(saved, saved.add(const Duration(minutes: 9))),
        'hace 9 min');
    expect(expressFreshnessLabel(saved, saved.add(const Duration(hours: 3))),
        'hace 3 h');
    expect(expressFreshnessLabel(saved, saved.add(const Duration(days: 2))),
        'hace 2 días');
  });

  test('network failure, recovery and user change: reset forgets the previous account', () async {
    final h = _Harness();
    var probes = 0;
    h.monitor.probe = () async {
      probes++;
      throw http.ClientException('down');
    };
    h.monitor.recordSuccess('passenger_home');
    expect(h.monitor.lastValidAt('passenger_home'), isNotNull);

    for (var i = 0; i < ExpressConnectivityMonitor.offlineAfterFailures; i++) {
      h.monitor.recordFailure(http.ClientException('down'));
    }
    expect(h.monitor.state, ExpressConnectionState.offline);
    expect(h.scheduled, isNotEmpty);

    h.monitor.resetForAccountChange();
    expect(h.monitor.state, ExpressConnectionState.online);
    expect(h.monitor.lastValidAt('passenger_home'), isNull);
    expect(h.scheduled.last.timer.cancelled, isTrue,
        reason: 'the previous account probe must not keep running');

    h.monitor.onAppResumed();
    await Future<void>.delayed(Duration.zero);
    expect(probes, 0, reason: 'no probe remains after the reset');
  });

  test('recovery: a successful probe restores online and records the time', () async {
    final h = _Harness();
    var fail = true;
    h.monitor.probe = () async {
      if (fail) throw http.ClientException('down');
    };
    h.monitor.recordFailure(http.ClientException('down'));
    expect(h.monitor.state, ExpressConnectionState.reconnecting);

    fail = false;
    await h.monitor.probeNow();
    expect(h.monitor.state, ExpressConnectionState.online);
    expect(h.monitor.lastValidAt('probe'), isNotNull);
  });
}
