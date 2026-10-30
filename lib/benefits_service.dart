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

  Future<Map<String, dynamic>> driverReferralStatus() async {
    final raw = await supabase.rpc('my_driver_referral_status', params: {
      'p_channel': ExpressRuntimeChannel.name,
    });
    if (raw is! Map) throw StateError('Referidos de conductores no disponibles.');
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> applyDriverReferralCode(String code) async {
    final raw = await supabase.rpc('apply_driver_referral_code', params: {
      'p_code': code.trim().toUpperCase(),
      'p_channel': ExpressRuntimeChannel.name,
    });
    if (raw is! Map) throw StateError('No se pudo aplicar el código.');
    return Map<String, dynamic>.from(raw);
  }
}
