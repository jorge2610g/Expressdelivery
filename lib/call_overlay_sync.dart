import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driver_floating_offers.dart';
import 'services/express_service.dart';

/// Conductor: guarda por token la barra efectiva (permiso AND opción activa).
/// Si falla cualquier paso, no se escribe nada y el servidor usará notificación normal.
Future<void> syncDriverPushOverlayState(ExpressService service) async {
  try {
    final granted = await isOverlayGranted();
    final barOn = await DriverFloatingOfferSettings(accountId: service.userId).isEnabled();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await service.setPushTokenOverlayState(token: token, enabled: granted && barOn);
  } catch (_) {
    // Sin token, sin migración o sin red: se reintenta en el próximo cambio de estado.
  }
}

const _floatingChannel = MethodChannel('express/floating_offers');

/// Lee el permiso real de sobreposición de pantalla (Android).
Future<bool> isOverlayGranted() async {
  try {
    return await _floatingChannel.invokeMethod<bool>('hasPermission') ?? false;
  } catch (_) {
    return false;
  }
}

/// Guarda en el servidor si la sobreposición está activa y devuelve ese estado.
/// Las llamadas por internet siguen a ese permiso. Solo escribe si cambió.
Future<bool> syncOverlayCallPreference(ExpressService service) async {
  try {
    final granted = await isOverlayGranted();
    final prefs = await service.myCallPreferences();
    final stored = prefs['overlay_enabled'] == true;
    final storedInternet = prefs['internet_calls_enabled'] == true;
    if (stored == granted && storedInternet == granted) return granted;
    await service.setMyCallPreferences(
      overlayEnabled: granted,
      internetCallsEnabled: granted,
      sharePhoneForCalls: false,
    );
    return granted;
  } catch (_) {
    // Sin sesión o sin canal nativo: se reintenta en el próximo cambio.
    return false;
  }
}

/// Devuelve true solo la primera vez que se pregunta para este viaje, y lo recuerda.
/// Así, reabrir la app no vuelve a preguntar, y se respeta la respuesta.
/// Pasajero y conductor llevan recuerdos separados.
Future<bool> claimTripOverlayPrompt(String tripId, {bool driver = false}) async {
  final key = driver ? 'overlay_prompted_trip_id_driver' : 'overlay_prompted_trip_id';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(key) == tripId) return false;
  await prefs.setString(key, tripId);
  return true;
}

/// Pregunta al usuario si quiere activar la sobreposición, explicando para qué
/// sirve. Es opcional: «No» deja el viaje normal. «Sí» abre los ajustes para que
/// el usuario la active él mismo. Solo se llama al empezar un viaje.
Future<void> promptOverlayIfNeeded(
  BuildContext context,
  ExpressService service, {
  bool driver = false,
}) async {
  if (await isOverlayGranted()) return;
  if (!context.mounted) return;
  final activate = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(driver ? 'Ofertas y llamadas en segundo plano' : 'Llamadas en segundo plano'),
      content: Text(
        driver
            ? 'Si activas la sobreposición de pantalla, podrás ver ofertas flotantes, usar la burbuja y recibir llamadas aunque tengas la app cerrada o en segundo plano.\n\nEs opcional. Si no la activas, esas opciones quedarán apagadas hasta que la actives.'
            : 'Si activas la sobreposición de pantalla, podrás recibir llamadas de tu conductor aunque tengas la app cerrada o en segundo plano.\n\nEs opcional. Si no la activas, tu viaje sigue normal.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('No, ahora no'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Sí, activar'),
        ),
      ],
    ),
  );
  if (activate == true && context.mounted) {
    try {
      await _floatingChannel.invokeMethod<void>('openPermissionSettings');
    } catch (_) {}
  }
  if (context.mounted) {
    unawaited(syncOverlayCallPreference(service));
  }
}
