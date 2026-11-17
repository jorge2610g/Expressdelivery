import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_service.dart';
import 'phone_utils.dart';

/// País de la ubicación actual del usuario, resuelto por el servidor con las
/// zonas de servicio (RPC phone_country_for_point). Solo devuelve el código ISO
/// de 2 letras. Las coordenadas no se guardan ni se envían a terceros.
/// Devuelve null si no hay ubicación, permiso o zona que lo cubra.
Future<String?> expressLocatedPhoneCountry(SupabaseClient client) async {
  try {
    final position = await const ExpressLocationService()
        .passivePosition(cacheMaxAge: const Duration(minutes: 15))
        .timeout(const Duration(seconds: 8));
    if (position == null) return null;
    final value = await client.rpc('phone_country_for_point', params: {
      'p_lat': position.latitude,
      'p_lng': position.longitude,
    }).timeout(const Duration(seconds: 8));
    final code = value?.toString().trim().toUpperCase();
    return code != null && code.length == 2 ? code : null;
  } catch (_) {
    return null;
  }
}

/// Código de marcación del país: primero el catálogo del servidor, luego la
/// tabla local. Null si el país no está soportado.
String? expressDialCodeFor(
  String? countryCode,
  List<Map<String, dynamic>> catalog,
) {
  final code = countryCode?.trim().toUpperCase();
  if (code == null || code.isEmpty) return null;
  for (final row in catalog) {
    if (row['country_code']?.toString().toUpperCase() == code) {
      final dial = row['calling_code']?.toString().trim();
      if (dial != null && dial.isNotEmpty) return dial;
    }
  }
  return expressPhoneDialCodes[code];
}

/// Une el código de país con lo que escribió el usuario. Si ya escribió «+»,
/// el número es completo y no se le antepone nada.
String expressNormalizeWithDial(String dial, String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('+')) {
    return '+${trimmed.replaceAll(RegExp(r'[^0-9]'), '')}';
  }
  final dialDigits = dial.replaceAll(RegExp(r'[^0-9]'), '');
  var digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith(dialDigits)) {
    digits = digits.substring(dialDigits.length);
  }
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return '+$dialDigits$digits';
}

/// Código de marcación del usuario para preseleccionar en formularios:
/// 1) el país guardado en su cuenta, 2) el de su número guardado,
/// 3) el de su ubicación actual, 4) Chile como último recurso.
Future<String> expressUserDialCode(
  SupabaseClient client,
  Map<String, dynamic>? user,
  List<Map<String, dynamic>> catalog,
) async {
  final saved = user?['phone_country_code']?.toString();
  final savedDial = expressDialCodeFor(saved, catalog);
  if (savedDial != null) return savedDial;

  final savedPhone = user?['phone']?.toString().trim() ?? '';
  if (savedPhone.startsWith('+')) {
    final fromNumber =
        expressDialCodeFor(expressPhoneCountryFromNumber(savedPhone), catalog);
    if (fromNumber != null) return fromNumber;
  }

  final located = await expressLocatedPhoneCountry(client);
  final locatedDial = expressDialCodeFor(located, catalog);
  if (locatedDial != null) return locatedDial;

  return expressDialCodeFor('CL', catalog) ?? '+56';
}
