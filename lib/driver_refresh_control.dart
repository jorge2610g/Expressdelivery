class DriverRefreshThrottle {
  DriverRefreshThrottle({
    this.window = const Duration(seconds: 2),
  });

  final Duration window;
  DateTime? _lastAcceptedAt;

  DateTime? get lastAcceptedAt => _lastAcceptedAt;

  bool accept(DateTime now) {
    final normalized = now.toUtc();
    final previous = _lastAcceptedAt;
    if (previous != null && normalized.difference(previous) < window) {
      return false;
    }
    _lastAcceptedAt = normalized;
    return true;
  }

  void mark(DateTime at) {
    _lastAcceptedAt = at.toUtc();
  }
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
  if (eventZone != null && eventZone.isNotEmpty && eventZone != expectedZone) {
    return false;
  }

  final eventChannel = record['channel']?.toString().trim().toLowerCase();
  if (eventChannel != null &&
      eventChannel.isNotEmpty &&
      eventChannel != expectedChannel) {
    return false;
  }

  // The Realtime subscription is already server-filtered by zone_id.
  // Missing fields can occur in oldRecord payloads (for example DELETE),
  // so absence alone must not turn a correctly scoped server event into a miss.
  return true;
}
