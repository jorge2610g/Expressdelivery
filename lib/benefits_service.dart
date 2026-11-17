import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';

/// Read only surface for the account's available benefits. Campaigns and
/// rewards are never redeemed here; ride settlement remains authoritative.
class BenefitsService {
  /// [role] es 'driver' o 'passenger'; el servidor solo devuelve los
  /// programas dirigidos a ese público.
  Future<Map<String, dynamic>> overview({String? role}) async {
    final raw = await supabase.rpc('my_benefits_overview', params: {
      'p_channel': ExpressRuntimeChannel.name,
      'p_role': role,
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

  /// Read-only check of a ride coupon before the ride is created.
  Future<Map<String, dynamic>> validateCoupon({
    required String code,
    required double latitude,
    required double longitude,
    required String category,
    required num fare,
    required String paymentMethod,
  }) async {
    final raw = await supabase.rpc('validate_benefit_coupon', params: {
      'p_code': code.trim().toUpperCase(),
      'p_channel': ExpressRuntimeChannel.name,
      'p_lat': latitude,
      'p_lng': longitude,
      'p_category': category,
      'p_fare': fare,
      'p_payment_method': paymentMethod,
    });
    if (raw is! Map) throw StateError('No se pudo validar el cupón.');
    return Map<String, dynamic>.from(raw);
  }
}
