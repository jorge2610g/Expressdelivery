/// Client-side filter for Postgres Realtime refreshes of the driver's home.
///
/// This prevents changes in an unrelated service zone / runtime from causing
/// an expensive refresh. Missing fields deliberately preserve the previous
/// refresh behavior: the server remains authoritative for offer visibility.
/// This is not a replacement for RLS or server-scoped realtime channels.
bool expressDriverRealtimeShouldRefresh({
  required Map<String, dynamic> record,
  required String? zoneId,
  required String channel,
}) {
  final expectedZone = zoneId?.trim() ?? '';
  final changedZone = record['zone_id']?.toString().trim() ?? '';
  if (expectedZone.isNotEmpty && changedZone.isNotEmpty &&
      expectedZone != changedZone) {
    return false;
  }
  final expectedChannel = channel.trim().toLowerCase();
  final changedChannel =
      record['channel']?.toString().trim().toLowerCase() ?? '';
  if (expectedChannel.isNotEmpty && changedChannel.isNotEmpty &&
      expectedChannel != changedChannel) {
    return false;
  }
  return true;
}
