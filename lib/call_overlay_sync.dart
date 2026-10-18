import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_floating_offers.dart';
import 'services/express_service.dart';

/// Último estado confirmado por el servidor. Evita escrituras repetidas en cada
/// vuelta a primer plano; se refresca como máximo cada 6 horas.
class _DriverPushState {
  static bool? enabled;
  static String? token;
  static DateTime? confirmedAt;
}

const _driverPushRefresh = Duration(hours: 6);

/// Conductor: guarda por token la barra efectiva (permiso AND opción activa).
/// Solo marca el estado como sincronizado cuando el servidor lo confirma. Si falla
/// cualquier paso, el servidor trata el token como desconocido: notificación normal.
Future<void> syncDriverPushOverlayState(
  ExpressService service, {
  bool force = false,
}) async {
  try {
    final granted = await isOverlayGranted();
    final barOn = await DriverFloatingOfferSettings(accountId: service.userId).isEnabled();
    final enabled = granted && barOn;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;

    final now = DateTime.now();
    final unchanged = _DriverPushState.enabled == enabled &&
        _DriverPushState.token == token &&
        _DriverPushState.confirmedAt != null &&
        now.difference(_DriverPushState.confirmedAt!) < _driverPushRefresh;
    if (unchanged && !force) return;

    final confirmed = await service.setPushTokenOverlayState(token: token, enabled: enabled);
    if (!confirmed) return;
    _DriverPushState.enabled = enabled;
    _DriverPushState.token = token;
    _DriverPushState.confirmedAt = now;
  } catch (_) {
    // Sin token, sin migración o sin red: se reintenta en el próximo cambio de estado.
  }
}

/// Cierre de sesión (sin ExpressService): el token de este dispositivo deja de tener barra.
Future<void> clearDriverPushOverlayStateWith() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      await Supabase.instance.client.rpc(
        'set_push_token_overlay_state',
        params: {'p_token': token, 'p_enabled': false},
      );
    }
  } catch (_) {
    // Sin escritura, el servidor ve un estado caducado y usa notificación normal.
  }
  _DriverPushState.enabled = null;
  _DriverPushState.token = null;
  _DriverPushState.confirmedAt = null;
}

/// Al cerrar sesión, el token de este dispositivo deja de tener barra.
Future<void> clearDriverPushOverlayState(ExpressService service) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      await service.setPushTokenOverlayState(token: token, enabled: false);
    }
  } catch (_) {
    // Si no se puede escribir, el servidor ve un estado caducado y usa notificación normal.
  }
  _DriverPushState.enabled = null;
  _DriverPushState.token = null;
  _DriverPushState.confirmedAt = null;
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

const _bubbleRequestPrefix = 'overlay_bubble_requested:';

/// El conductor toca «Activar burbuja» y va a Ajustes de Android. Se recuerda esa
/// petición expresa: solo así el regreso con permiso concedido activa la opción.
Future<void> requestBubbleActivation(String accountId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_bubbleRequestPrefix$accountId', true);
  } catch (_) {
    // Sin preferencias: el conductor puede volver a tocar el botón.
  }
}

/// Al regresar de Ajustes. Con petición expresa y permiso concedido, la burbuja queda
/// activada por elección del conductor. Sin petición, el permiso por sí solo nunca
/// la activa. La petición se consume en cada regreso y luego se sincroniza el token.
Future<void> completeBubbleActivationAfterSettings(ExpressService service) async {
  final accountId = service.userId;
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_bubbleRequestPrefix$accountId';
    if (prefs.getBool(key) == true) {
      await prefs.remove(key);
      if (await isOverlayGranted()) {
        await DriverFloatingOfferSettings(accountId: accountId).setEnabled(true);
      }
    }
  } catch (_) {
    // Sin preferencias: se conserva la opción actual.
  }
  await syncDriverPushOverlayState(service);
}

/// Opción explícita del conductor: encender o apagar la burbuja desde la pantalla de
/// permisos. Después sincroniza el estado por token.
Future<void> setBubbleEnabledByDriver(ExpressService service, bool enabled) async {
  await DriverFloatingOfferSettings(accountId: service.userId).setEnabled(enabled);
  await syncDriverPushOverlayState(service, force: true);
}

/// Abre los ajustes de Android donde el usuario activa la sobreposición. Solo se
/// llama tras un toque del usuario; nunca de forma automática.
Future<void> openOverlayPermissionSettings() async {
  try {
    await _floatingChannel.invokeMethod<void>('openPermissionSettings');
  } catch (_) {}
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
      title: Text(driver ? 'Ventana flotante' : 'Llamadas en segundo plano'),
      content: Text(
        driver
            ? 'Puede mostrar la burbuja sobre otras aplicaciones cuando Express está en segundo plano. Es opcional y depende de los permisos del teléfono.\n\nSi no la activas, la burbuja queda apagada.'
            : 'Si activas la sobreposición de pantalla, podrás recibir llamadas de tu conductor aunque tengas la app cerrada o en segundo plano.\n\nEs opcional. Si no la activas, tu viaje sigue normal.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('No, ahora no'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(driver ? 'Acceso a la burbuja flotante' : 'Sí, activar'),
        ),
      ],
    ),
  );
  if (activate == true && context.mounted) {
    // Petición expresa del conductor: al regresar, la burbuja se activa solo si el
    // permiso quedó concedido.
    if (driver) await requestBubbleActivation(service.userId);
    await openOverlayPermissionSettings();
  }
  if (context.mounted) {
    unawaited(syncOverlayCallPreference(service));
  }
}
