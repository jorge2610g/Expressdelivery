import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';

/// Read only surface for the account's available benefits. Campaigns and
/// rewards are never redeemed here; ride settlement remains authoritative.
class BenefitsService {
  Future<Map<String, dynamic>> overview() async {
    final raw = await supabase.rpc('my_benefits_overview', params: {
      'p_channel': ExpressRuntimeChannel.name,
    });
    if (raw is! Map) throw StateError('Beneficios no disponibles.');
    return Map<String, dynamic>.from(raw);
  }
}
