/// Connect to dispatch only after Supabase has acknowledged the new GPS fix.
/// A failed location write must never set the driver online.
Future<void> saveDriverGpsThenConnect({
  required Future<void> Function() savePosition,
  required Future<void> Function() setOnline,
}) async {
  await savePosition();
  await setOnline();
}
