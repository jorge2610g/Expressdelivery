import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';

/// A championship is visible only when the server confirms that the signed-in
/// driver is eligible and there is an active championship in their own zone
/// and runtime. Fail closed on permission, network or backend errors.
Future<bool> hasActiveDriverChampionship() async {
  try {
    final result = await supabase.rpc(
      'driver_championships_for_driver',
      params: {'p_channel': ExpressRuntimeChannel.name},
    );
    return result is Map && result['available'] == true;
  } catch (_) {
    return false;
  }
}
