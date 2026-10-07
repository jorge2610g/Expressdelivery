String? expressPushStableKey({
  required String channel,
  String? notificationId,
  String? messageId,
}) {
  final notification = notificationId?.trim();
  final firebaseMessage = messageId?.trim();
  final raw = notification != null && notification.isNotEmpty
      ? notification
      : firebaseMessage != null && firebaseMessage.isNotEmpty
          ? firebaseMessage
          : null;
  if (raw == null) return null;
  return channel.trim().toLowerCase() + ':' + raw;
}

int expressPushStableNotificationId(String key) {
  var hash = 17;
  for (final codeUnit in key.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}
