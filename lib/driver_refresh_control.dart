import 'dart:async';

typedef DriverRefreshClock = DateTime Function();
typedef DriverRefreshSchedule =
    void Function(Duration delay, void Function() task);

/// Coalesces complete driver-home refresh requests without losing an event.
///
/// The first request runs immediately. Requests received while a refresh is
/// running, or inside [window] after its successful completion, result in one
/// trailing refresh once both constraints allow it. The clock and scheduler are
/// injected so this timing contract can be tested without wall-clock waits.
class DriverRefreshCoordinator {
  DriverRefreshCoordinator({
    required void Function() onRefresh,
    DriverRefreshClock? clock,
    DriverRefreshSchedule? schedule,
    this.window = const Duration(seconds: 2),
  }) : _onRefresh = onRefresh,
       _clock = clock ?? _utcNow,
       _schedule = schedule ?? _timerSchedule;

  final void Function() _onRefresh;
  final DriverRefreshClock _clock;
  final DriverRefreshSchedule _schedule;
  final Duration window;

  bool _inFlight = false;
  bool _pending = false;
  bool _trailingScheduled = false;
  DateTime? _lastCompletedAt;

  bool get inFlight => _inFlight;
  DateTime? get lastCompletedAt => _lastCompletedAt;

  void request() {
    if (_inFlight) {
      _pending = true;
      return;
    }

    final delay = _delayUntilAllowed();
    if (delay == Duration.zero) {
      _start();
    } else {
      _pending = true;
      _scheduleTrailing(delay);
    }
  }

  /// Call exactly once when the complete refresh finishes, including failures,
  /// so a queued trailing request cannot be stranded.
  void complete({required bool succeeded}) {
    if (!_inFlight) return;
    _inFlight = false;
    if (succeeded) _lastCompletedAt = _now();
    if (!_pending) return;
    // The event arrived while a read was in flight. Running once more as soon
    // as that read settles is the trailing edge; another fresh window here
    // could delay a cancellation or assignment beyond two seconds.
    _start();
  }

  Duration _delayUntilAllowed() {
    final completedAt = _lastCompletedAt;
    if (completedAt == null) return Duration.zero;
    final elapsed = _now().difference(completedAt);
    if (elapsed.isNegative || elapsed >= window) return Duration.zero;
    return window - elapsed;
  }

  void _scheduleTrailing(Duration delay) {
    if (_trailingScheduled) return;
    _trailingScheduled = true;
    _schedule(delay, () {
      _trailingScheduled = false;
      if (_inFlight || !_pending) return;
      final remaining = _delayUntilAllowed();
      if (remaining > Duration.zero) {
        _scheduleTrailing(remaining);
        return;
      }
      _start();
    });
  }

  void _start() {
    _pending = false;
    _inFlight = true;
    _onRefresh();
  }

  DateTime _now() => _clock().toUtc();

  static DateTime _utcNow() => DateTime.now().toUtc();

  static void _timerSchedule(Duration delay, void Function() task) {
    Timer(delay, task);
  }
}

enum DriverAvailabilityRefreshDecision { apply, discard, discardAndRequeue }

/// Decides whether a light availability read is still safe to publish.
DriverAvailabilityRefreshDecision driverAvailabilityRefreshDecision({
  required int startedStateVersion,
  required int currentStateVersion,
  required bool fullRefreshInFlight,
  required bool currentStateEligible,
}) {
  if (!currentStateEligible) return DriverAvailabilityRefreshDecision.discard;
  if (fullRefreshInFlight || currentStateVersion != startedStateVersion) {
    return DriverAvailabilityRefreshDecision.discardAndRequeue;
  }
  return DriverAvailabilityRefreshDecision.apply;
}

bool driverFullRefreshIsRecent({
  required DateTime? lastCompletedAt,
  required DateTime now,
  Duration maxAge = const Duration(seconds: 12),
}) {
  if (lastCompletedAt == null) return false;
  final elapsed = now.toUtc().difference(lastCompletedAt.toUtc());
  return !elapsed.isNegative && elapsed < maxAge;
}

bool driverRideRequestMatchesScope({
  required Map<String, dynamic> record,
  required String zoneId,
  required String channel,
}) {
  final expectedZone = zoneId.trim();
  final expectedChannel = channel.trim().toLowerCase();
  if (expectedZone.isEmpty || expectedChannel.isEmpty) return false;

  final eventZone = record['zone_id']?.toString().trim();
  final eventChannel = record['channel']?.toString().trim().toLowerCase();

  // Fail closed for sparse oldRecord payloads. UPDATE/INSERT events include
  // both fields, while a DELETE without replica identity may only contain the
  // primary key; the 12-second backup refresh will reconcile that case.
  if (eventZone == null || eventZone.isEmpty) return false;
  if (eventChannel == null || eventChannel.isEmpty) return false;

  return eventZone == expectedZone && eventChannel == expectedChannel;
}
