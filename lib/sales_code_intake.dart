import 'dart:async';

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/supabase_client.dart';
import 'sales_advisor.dart';

/// Captura el código del asesor en la app (Android):
///  1. Enlace https://expressviajes.online/r/CODIGO (app ya instalada).
///  2. Referrer de Google Play tras instalar desde el enlace del QR.
/// Después del primer inicio de sesión se envía al servidor.
class SalesCodeIntake {
  SalesCodeIntake._();

  static const _referrerCheckedKey = 'express_sales_referrer_checked';
  static StreamSubscription<Uri>? _linkSubscription;

  static Future<void> start() async {
    if (kIsWeb) return;
    await _readInstallReferrer();
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) await _saveFromUri(initial);
      _linkSubscription ??= links.uriLinkStream.listen(_saveFromUri);
    } catch (_) {
      // Sin enlaces no se bloquea la app.
    }
  }

  static Future<void> _readInstallReferrer() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_referrerCheckedKey) == true) return;
      final details = await AndroidPlayInstallReferrer.installReferrer;
      final code = salesCodeFromReferrer(details.installReferrer ?? '');
      if (code != null) await SalesCodeStore.save(code);
      // Solo se marca como leído si Google Play respondió.
      await prefs.setBool(_referrerCheckedKey, true);
    } catch (_) {
      // Se vuelve a intentar en la siguiente apertura.
    }
  }

  static Future<void> _saveFromUri(Uri uri) async {
    final code = salesCodeFromUri(uri);
    if (code != null) await SalesCodeStore.save(code);
  }

  /// Envía el código pendiente al servidor. El servidor decide si la cuenta
  /// puede atribuirse (solo cuentas nuevas y sin asesor previo).
  static Future<void> attachPending() async {
    if (supabase.auth.currentSession == null) return;
    final code = await SalesCodeStore.read();
    if (code == null) return;
    try {
      await supabase.rpc('sales_attach_my_code', params: {'p_code': code});
      await SalesCodeStore.clear();
    } catch (_) {
      // Sin conexión: se reintenta en la siguiente apertura.
    }
  }
}
